`timescale 1ns/1ps

module controller_fsm #(
    parameter integer MAX_M = 5,
    parameter integer MAX_N = 5,
    parameter integer MAX_PER_DIM = 5,
    parameter integer DATA_W = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [9:0] sw,
    input  wire btn_confirm,
    input  wire rx_valid,
    input  wire [7:0] rx_byte,
    input  wire number_valid,
    input  wire signed [DATA_W-1:0] number,
    output reg  led_error,
    output reg  [63:0] sevenseg_chars,

    output reg  store_start,
    output reg  [2:0] store_m,
    output reg  [2:0] store_n,
    output reg  store_data_valid,
    output reg  [5:0] store_index,
    output reg  signed [DATA_W-1:0] store_data,
    output reg  store_done,
    input  wire [2:0] store_id,

    output reg  [2:0] rd_m,
    output reg  [2:0] rd_n,
    output reg  [2:0] rd_id,
    output reg  [5:0] rd_index,
    input  wire signed [DATA_W-1:0] rd_data,     // 同步读，延迟1拍
    input  wire [2:0] rd_count,

    output reg  byte_valid,
    output reg  [7:0] byte_data,
    output reg  num_valid,
    output reg  signed [31:0] num_value,
    output reg  [1:0] num_term,
    input  wire printer_busy,

    output reg  rng_enable,
    input  wire [15:0] rng_value,

    output reg  countdown_start,
    output reg  [7:0] countdown_value,
    input  wire countdown_active,
    input  wire [7:0] countdown_remain,

    output reg  [2:0] cfg_max_per_dim,
    output reg  signed [DATA_W-1:0] cfg_elem_min,
    output reg  signed [DATA_W-1:0] cfg_elem_max,
    output reg  [7:0] cfg_countdown
);
    localparam integer MAX_ELEMS = MAX_M * MAX_N;

    reg [5:0] state;
    reg [2:0] mode;
    reg [2:0] op_type;
    reg [5:0] elem_idx;
    reg [2:0] mat_id_a;
    reg [2:0] mat_id_b;
    reg [2:0] mat_m_a;
    reg [2:0] mat_n_a;
    reg [2:0] mat_m_b;
    reg [2:0] mat_n_b;
    reg signed [DATA_W-1:0] scalar;
    reg [2:0] gen_count;

    reg [DATA_W*MAX_ELEMS-1:0] mat_a;
    reg [DATA_W*MAX_ELEMS-1:0] mat_b;

    wire [DATA_W*MAX_ELEMS-1:0] out_transpose;
    wire [DATA_W*MAX_ELEMS-1:0] out_add;
    wire [DATA_W*MAX_ELEMS-1:0] out_scalar;
    wire [DATA_W*MAX_ELEMS-1:0] out_mul;

    mat_transpose #(.MAX_M(MAX_M), .MAX_N(MAX_N), .DATA_W(DATA_W)) u_trans (
        .m(mat_m_a),
        .n(mat_n_a),
        .in_mat(mat_a),
        .out_mat(out_transpose)
    );

    mat_add #(.MAX_M(MAX_M), .MAX_N(MAX_N), .DATA_W(DATA_W)) u_add (
        .m(mat_m_a),
        .n(mat_n_a),
        .a_mat(mat_a),
        .b_mat(mat_b),
        .out_mat(out_add)
    );

    mat_scalar_mul #(.MAX_M(MAX_M), .MAX_N(MAX_N), .DATA_W(DATA_W)) u_scalar (
        .m(mat_m_a),
        .n(mat_n_a),
        .scalar(scalar),
        .a_mat(mat_a),
        .out_mat(out_scalar)
    );

    // ===== 串行矩阵乘 =====
    wire mul_busy, mul_done;
    reg  mul_start;

    mat_mul #(.MAX_M(MAX_M), .MAX_N(MAX_N), .DATA_W(DATA_W)) u_mul (
        .clk(clk),
        .rst_n(rst_n),
        .start(mul_start),
        .busy(mul_busy),
        .done(mul_done),
        .m(mat_m_a),
        .n(mat_n_a),
        .p(mat_n_b),
        .a_mat(mat_a),
        .b_mat(mat_b),
        .out_mat(out_mul)
    );

    // ======== 卷积 conv2d：作为 op_type == 3'd4（由 sw[4:2] 选择）========
    reg  conv_start;                          // 1-cycle pulse
    wire conv_done;
    wire [15:0] conv_cycle_count;
    wire [DATA_W*80-1:0] conv_out_mat;

    reg        conv_done_latch;               // 粘住 done，避免错过 1 拍 done
    reg [DATA_W*9-1:0] conv_kernel;           // 9 个 kernel（行优先）
    reg [3:0]          conv_kidx;             // 0..8
    reg [6:0]          conv_out_idx;          // 0..79
    reg [3:0]          conv_col;              // 0..9

    conv2d #(
        .DATA_W(DATA_W)
    ) u_conv2d (
        .clk(clk),
        .rst_n(rst_n),
        .start(conv_start),
        .kernel(conv_kernel),
        .done(conv_done),
        .cycle_count(conv_cycle_count),
        .out_mat(conv_out_mat)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conv_done_latch <= 1'b0;
        end else begin
            if (conv_start)         conv_done_latch <= 1'b0; // 新启动清零
            else if (conv_done)     conv_done_latch <= 1'b1; // done 粘住
        end
    end

    // ===== 用 mul-high 替换 %，避免除法器 =====
    wire [15:0] span_u16 =
        (cfg_elem_max >= cfg_elem_min) ? (cfg_elem_max - cfg_elem_min + 16'sd1) : 16'd1;
    wire [31:0] rng_scaled = rng_value * span_u16;
    wire signed [DATA_W-1:0] rng_in_range = cfg_elem_min + $signed(rng_scaled[31:16]);

    function [7:0] msg_char;
        input [2:0] msg_id;
        input [5:0] idx;
        begin
            case (msg_id)
                3'd0: begin
                    case (idx)
                        6'd0: msg_char = "M";
                        6'd1: msg_char = "E";
                        6'd2: msg_char = "N";
                        6'd3: msg_char = "U";
                        6'd4: msg_char = "\n";
                        default: msg_char = 8'h00;
                    endcase
                end
                3'd1: begin
                    case (idx)
                        6'd0: msg_char = "O";
                        6'd1: msg_char = "K";
                        6'd2: msg_char = "\n";
                        default: msg_char = 8'h00;
                    endcase
                end
                3'd2: begin
                    case (idx)
                        6'd0: msg_char = "E";
                        6'd1: msg_char = "R";
                        6'd2: msg_char = "R";
                        6'd3: msg_char = "\n";
                        default: msg_char = 8'h00;
                    endcase
                end
                3'd3: begin
                    case (idx)
                        6'd0: msg_char = "R";
                        6'd1: msg_char = "E";
                        6'd2: msg_char = "A";
                        6'd3: msg_char = "D";
                        6'd4: msg_char = "Y";
                        6'd5: msg_char = "\n";
                        default: msg_char = 8'h00;
                    endcase
                end
                default: msg_char = 8'h00;
            endcase
        end
    endfunction

    function [5:0] msg_len;
        input [2:0] msg_id;
        begin
            case (msg_id)
                3'd0: msg_len = 6'd5;
                3'd1: msg_len = 6'd3;
                3'd2: msg_len = 6'd4;
                3'd3: msg_len = 6'd6;
                default: msg_len = 6'd0;
            endcase
        end
    endfunction

    reg [2:0] msg_id;
    reg [5:0] msg_idx;

    localparam S_BOOT         = 6'd0;
    localparam S_MENU         = 6'd1;
    localparam S_MSG          = 6'd2;
    localparam S_IN_M         = 6'd3;
    localparam S_IN_N         = 6'd4;
    localparam S_IN_ELEM      = 6'd5;
    localparam S_GEN_M        = 6'd6;
    localparam S_GEN_N        = 6'd7;
    localparam S_GEN_K        = 6'd8;
    localparam S_GEN_ELEM     = 6'd9;
    localparam S_DISPLAY_M    = 6'd10;
    localparam S_DISPLAY_N    = 6'd11;
    localparam S_DISPLAY_LOOP = 6'd12;
    localparam S_DISPLAY_WAIT = 6'd13;
    localparam S_DISPLAY_DATA = 6'd14;

    localparam S_OP_SELECT    = 6'd15;
    localparam S_OP_M         = 6'd16;
    localparam S_OP_N         = 6'd17;
    localparam S_OP_IDA       = 6'd18;
    localparam S_OP_MB        = 6'd19;
    localparam S_OP_NB        = 6'd20;
    localparam S_OP_IDB       = 6'd21;
    localparam S_OP_SCALAR    = 6'd22;

    localparam S_LOAD_A_ADDR  = 6'd23;
    localparam S_LOAD_A_WAIT  = 6'd24;
    localparam S_LOAD_A_DATA  = 6'd25;

    localparam S_LOAD_B_ADDR  = 6'd26;
    localparam S_LOAD_B_WAIT  = 6'd27;
    localparam S_LOAD_B_DATA  = 6'd28;

    localparam S_WAIT_MUL     = 6'd29;
    localparam S_PRINT_RESULT = 6'd30;

    // 卷积新增状态
    localparam S_CONV_KIN     = 6'd31;  // 输入 9 个 kernel
    localparam S_CONV_START   = 6'd32;  // start pulse
    localparam S_CONV_WAIT    = 6'd33;  // 等 done（latch）
    localparam S_CONV_PRINT   = 6'd34;  // 打印 80 个输出（8x10）

    reg [2:0] cmd_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_BOOT;
            mode <= 3'd0;
            op_type <= 3'd0;
            msg_id <= 3'd0;
            msg_idx <= 6'd0;
            led_error <= 1'b0;

            store_start <= 1'b0;
            store_data_valid <= 1'b0;
            store_done <= 1'b0;
            store_index <= 6'd0;
            store_data <= {DATA_W{1'b0}};
            store_m <= 3'd0;
            store_n <= 3'd0;

            rd_m <= 3'd1;
            rd_n <= 3'd1;
            rd_id <= 3'd0;
            rd_index <= 6'd0;

            byte_valid <= 1'b0;
            byte_data <= 8'h00;
            num_valid <= 1'b0;
            num_value <= 32'sd0;
            num_term <= 2'd0;

            rng_enable <= 1'b0;
            countdown_start <= 1'b0;
            countdown_value <= 8'd0;

            cfg_max_per_dim <= 3'd5;
            cfg_elem_min <= 0;
            cfg_elem_max <= 9;
            cfg_countdown <= 8'd10;

            elem_idx <= 6'd0;
            mat_id_a <= 3'd0;
            mat_id_b <= 3'd0;
            mat_m_a <= 3'd0;
            mat_n_a <= 3'd0;
            mat_m_b <= 3'd0;
            mat_n_b <= 3'd0;
            scalar <= 0;
            gen_count <= 3'd0;
            cmd_pending <= 3'd0;

            sevenseg_chars <= {8{8'h20}};
            mul_start <= 1'b0;

            mat_a <= {DATA_W*MAX_ELEMS{1'b0}};
            mat_b <= {DATA_W*MAX_ELEMS{1'b0}};

            // conv init
            conv_start   <= 1'b0;
            conv_kernel  <= {DATA_W*9{1'b0}};
            conv_kidx    <= 4'd0;
            conv_out_idx <= 7'd0;
            conv_col     <= 4'd0;
        end else begin
            // default pulses
            store_start <= 1'b0;
            store_data_valid <= 1'b0;
            store_done <= 1'b0;
            byte_valid <= 1'b0;
            num_valid <= 1'b0;
            rng_enable <= 1'b0;
            countdown_start <= 1'b0;
            mul_start <= 1'b0;
            conv_start <= 1'b0;

            if (rx_valid) begin
                if (rx_byte == "X") cmd_pending <= 3'd1;
                else if (rx_byte == "L") cmd_pending <= 3'd2;
                else if (rx_byte == "U") cmd_pending <= 3'd3;
                else if (rx_byte == "C") cmd_pending <= 3'd4;
            end

            if (number_valid && cmd_pending != 3'd0) begin
                case (cmd_pending)
                    3'd1: cfg_max_per_dim <= number[2:0];
                    3'd2: cfg_elem_min <= number;
                    3'd3: cfg_elem_max <= number;
                    3'd4: cfg_countdown <= number[7:0];
                    default: ;
                endcase
                cmd_pending <= 3'd0;
                msg_id <= 3'd1;
                msg_idx <= 6'd0;
                state <= S_MSG;
            end

            case (state)
                S_BOOT: begin
                    msg_id <= 3'd0;
                    msg_idx <= 6'd0;
                    state <= S_MSG;
                end

                S_MSG: begin
                    if (!printer_busy) begin
                        if (msg_idx < msg_len(msg_id)) begin
                            byte_valid <= 1'b1;
                            byte_data <= msg_char(msg_id, msg_idx);
                            msg_idx <= msg_idx + 1'b1;
                        end else begin
                            state <= S_MENU;
                        end
                    end
                end

                S_MENU: begin
                    if (btn_confirm) begin
                        mode <= sw[1:0];
                        led_error <= 1'b0;
                        case (sw[1:0])
                            2'd0: state <= S_IN_M;
                            2'd1: state <= S_GEN_M;
                            2'd2: state <= S_DISPLAY_M;
                            2'd3: state <= S_OP_SELECT;
                            default: state <= S_IN_M;
                        endcase
                    end
                end

                // ===== 输入矩阵 =====
                S_IN_M: begin
                    sevenseg_chars <= {"I","N","P"," "," "," "," "," "};
                    if (number_valid) begin
                        if (number < 1 || number > MAX_M) begin
                            led_error <= 1'b1;
                            msg_id <= 3'd2; msg_idx <= 6'd0;
                            state <= S_MSG;
                        end else begin
                            store_m <= number[2:0];
                            led_error <= 1'b0;
                            state <= S_IN_N;
                        end
                    end
                end

                S_IN_N: begin
                    if (number_valid) begin
                        if (number < 1 || number > MAX_N) begin
                            led_error <= 1'b1;
                            msg_id <= 3'd2; msg_idx <= 6'd0;
                            state <= S_MSG;
                        end else begin
                            store_n <= number[2:0];
                            elem_idx <= 6'd0;
                            store_start <= 1'b1;
                            state <= S_IN_ELEM;
                        end
                    end
                end

                S_IN_ELEM: begin
                    if (number_valid) begin
                        if (number < cfg_elem_min || number > cfg_elem_max) begin
                            led_error <= 1'b1;
                            msg_id <= 3'd2; msg_idx <= 6'd0;
                            state <= S_MSG;
                        end else begin
                            store_data_valid <= 1'b1;
                            store_data <= number;
                            store_index <= elem_idx;
                            if (elem_idx == store_m * store_n - 1) begin
                                store_done <= 1'b1;
                                msg_id <= 3'd1; msg_idx <= 6'd0;
                                state <= S_MSG;
                            end
                            elem_idx <= elem_idx + 1'b1;
                        end
                    end
                end

                // ===== 生成矩阵 =====
                S_GEN_M: if (number_valid) begin store_m <= number[2:0]; state <= S_GEN_N; end
                S_GEN_N: if (number_valid) begin store_n <= number[2:0]; state <= S_GEN_K; end

                S_GEN_K: begin
                    if (number_valid) begin
                        gen_count <= number[2:0];
                        elem_idx <= 6'd0;
                        store_start <= 1'b1;
                        state <= S_GEN_ELEM;
                    end
                end

                S_GEN_ELEM: begin
                    rng_enable <= 1'b1;
                    store_data_valid <= 1'b1;
                    store_index <= elem_idx;
                    store_data <= rng_in_range;
                    if (elem_idx == store_m * store_n - 1) begin
                        store_done <= 1'b1;
                        if (gen_count > 1) begin
                            gen_count <= gen_count - 1'b1;
                            elem_idx <= 6'd0;
                            store_start <= 1'b1;
                        end else begin
                            msg_id <= 3'd1; msg_idx <= 6'd0;
                            state <= S_MSG;
                        end
                    end else begin
                        elem_idx <= elem_idx + 1'b1;
                    end
                end

                // ===== 显示矩阵（同步读：LOOP->WAIT->DATA）=====
                S_DISPLAY_M: if (number_valid) begin rd_m <= number[2:0]; state <= S_DISPLAY_N; end

                S_DISPLAY_N: begin
                    if (number_valid) begin
                        rd_n <= number[2:0];
                        rd_id <= 3'd0;
                        elem_idx <= 6'd0;
                        state <= S_DISPLAY_LOOP;
                    end
                end

                S_DISPLAY_LOOP: begin
                    if (rd_id < rd_count) begin
                        rd_index <= elem_idx;
                        state <= S_DISPLAY_WAIT;
                    end else begin
                        state <= S_MENU;
                    end
                end

                S_DISPLAY_WAIT: begin
                    state <= S_DISPLAY_DATA;
                end

                S_DISPLAY_DATA: begin
                    if (!printer_busy) begin
                        num_valid <= 1'b1;
                        num_value <= rd_data;
                        if (elem_idx == rd_m * rd_n - 1) begin
                            num_term <= 2'd2;
                            elem_idx <= 6'd0;
                            rd_id <= rd_id + 1'b1;
                        end else begin
                            num_term <= 2'd1;
                            elem_idx <= elem_idx + 1'b1;
                        end
                        state <= S_DISPLAY_LOOP;
                    end
                end

                // ===== 运算选择（sw[4:2]：0T/1A/2B/3C/4V）=====
                S_OP_SELECT: begin
                    op_type <= sw[4:2];
                    case (sw[4:2])
                        3'd0: sevenseg_chars <= {"T"," "," "," "," "," "," "," "};
                        3'd1: sevenseg_chars <= {"A"," "," "," "," "," "," "," "};
                        3'd2: sevenseg_chars <= {"B"," "," "," "," "," "," "," "};
                        3'd3: sevenseg_chars <= {"C"," "," "," "," "," "," "," "};
                        3'd4: sevenseg_chars <= {"V"," "," "," "," "," "," "," "};
                        default: sevenseg_chars <= {"?"," "," "," "," "," "," "," "};
                    endcase

                    if (btn_confirm) begin
                        if (sw[4:2] == 3'd4) begin
                            // 进入卷积：先输入 9 个 kernel
                            conv_kidx   <= 4'd0;
                            conv_kernel <= {DATA_W*9{1'b0}};
                            state       <= S_CONV_KIN;
                        end else begin
                            state <= S_OP_M;
                        end
                    end
                end

                S_OP_M: if (number_valid) begin mat_m_a <= number[2:0]; state <= S_OP_N; end
                S_OP_N: if (number_valid) begin mat_n_a <= number[2:0]; state <= S_OP_IDA; end

                S_OP_IDA: begin
                    if (number_valid) begin
                        mat_id_a <= number[2:0];
                        if (op_type == 3'd0 || op_type == 3'd2) begin
                            state <= (op_type == 3'd2) ? S_OP_SCALAR : S_LOAD_A_ADDR;
                        end else begin
                            state <= S_OP_MB;
                        end
                    end
                end

                S_OP_MB: if (number_valid) begin mat_m_b <= number[2:0]; state <= S_OP_NB; end
                S_OP_NB: if (number_valid) begin mat_n_b <= number[2:0]; state <= S_OP_IDB; end
                S_OP_IDB: if (number_valid) begin mat_id_b <= number[2:0]; state <= S_LOAD_A_ADDR; end

                S_OP_SCALAR: if (number_valid) begin scalar <= number; state <= S_LOAD_A_ADDR; end

                // ===== 读 A（同步读：ADDR->WAIT->DATA）=====
                S_LOAD_A_ADDR: begin
                    rd_m <= mat_m_a;
                    rd_n <= mat_n_a;
                    rd_id <= mat_id_a;
                    rd_index <= elem_idx;
                    state <= S_LOAD_A_WAIT;
                end

                S_LOAD_A_WAIT: begin
                    state <= S_LOAD_A_DATA;
                end

                S_LOAD_A_DATA: begin
                    mat_a[elem_idx*DATA_W +: DATA_W] <= rd_data;
                    if (elem_idx == mat_m_a * mat_n_a - 1) begin
                        elem_idx <= 6'd0;
                        if (op_type == 3'd0 || op_type == 3'd2) begin
                            state <= S_PRINT_RESULT;
                        end else begin
                            state <= S_LOAD_B_ADDR;
                        end
                    end else begin
                        elem_idx <= elem_idx + 1'b1;
                        state <= S_LOAD_A_ADDR;
                    end
                end

                // ===== 读 B（同步读：ADDR->WAIT->DATA）=====
                S_LOAD_B_ADDR: begin
                    rd_m <= mat_m_b;
                    rd_n <= mat_n_b;
                    rd_id <= mat_id_b;
                    rd_index <= elem_idx;
                    state <= S_LOAD_B_WAIT;
                end

                S_LOAD_B_WAIT: begin
                    state <= S_LOAD_B_DATA;
                end

                S_LOAD_B_DATA: begin
                    mat_b[elem_idx*DATA_W +: DATA_W] <= rd_data;
                    if (elem_idx == mat_m_b * mat_n_b - 1) begin
                        elem_idx <= 6'd0;
                        if (op_type == 3'd3) begin
                            mul_start <= 1'b1;
                            state <= S_WAIT_MUL;
                        end else begin
                            state <= S_PRINT_RESULT;
                        end
                    end else begin
                        elem_idx <= elem_idx + 1'b1;
                        state <= S_LOAD_B_ADDR;
                    end
                end

                // ===== 等矩阵乘完成 =====
                S_WAIT_MUL: begin
                    if (mul_done) begin
                        elem_idx <= 6'd0;
                        state <= S_PRINT_RESULT;
                    end
                end

                // ===== 打印结果 =====
                S_PRINT_RESULT: begin
                    if (!printer_busy) begin
                        num_valid <= 1'b1;
                        case (op_type)
                            3'd0: num_value <= out_transpose[elem_idx*DATA_W +: DATA_W];
                            3'd1: num_value <= out_add[elem_idx*DATA_W +: DATA_W];
                            3'd2: num_value <= out_scalar[elem_idx*DATA_W +: DATA_W];
                            3'd3: num_value <= out_mul[elem_idx*DATA_W +: DATA_W];
                            default: num_value <= 0;
                        endcase

                        if (elem_idx == mat_m_a * (op_type == 3'd3 ? mat_n_b : mat_n_a) - 1) begin
                            num_term <= 2'd2;
                            elem_idx <= 6'd0;
                            state <= S_MENU;
                        end else begin
                            num_term <= 2'd1;
                            elem_idx <= elem_idx + 1'b1;
                        end
                    end
                end

                // ===== 卷积：输入 9 个 kernel（UART 输入 9 个数字）=====
                S_CONV_KIN: begin
                    if (number_valid) begin
                        conv_kernel[conv_kidx*DATA_W +: DATA_W] <= number[DATA_W-1:0];
                        if (conv_kidx == 4'd8) begin
                            state <= S_CONV_START;
                        end else begin
                            conv_kidx <= conv_kidx + 1'b1;
                        end
                    end
                end

                // ===== 卷积：启动（1-cycle pulse）=====
                S_CONV_START: begin
                    conv_start   <= 1'b1;
                    conv_out_idx <= 7'd0;
                    conv_col     <= 4'd0;
                    state        <= S_CONV_WAIT;
                end

                // ===== 卷积：等待 done（latch）=====
                S_CONV_WAIT: begin
                    if (conv_done_latch) begin
                        state <= S_CONV_PRINT;
                    end
                end

                // ===== 卷积：打印 8x10 = 80 个输出 =====
                S_CONV_PRINT: begin
                    if (!printer_busy) begin
                        num_valid <= 1'b1;
                        num_value <= $signed(conv_out_mat[conv_out_idx*DATA_W +: DATA_W]);

                        if (conv_out_idx == 7'd79) begin
                            num_term <= 2'd2;
                            state    <= S_MENU;
                        end else if (conv_col == 4'd9) begin
                            num_term    <= 2'd2;
                            conv_col    <= 4'd0;
                            conv_out_idx<= conv_out_idx + 1'b1;
                        end else begin
                            num_term    <= 2'd1;
                            conv_col    <= conv_col + 1'b1;
                            conv_out_idx<= conv_out_idx + 1'b1;
                        end
                    end
                end

                default: state <= S_MENU;
            endcase
        end
    end

endmodule
