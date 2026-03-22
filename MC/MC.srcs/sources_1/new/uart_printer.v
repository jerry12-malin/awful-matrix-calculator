`timescale 1ns/1ps

module uart_printer #(
    parameter integer DATA_W = 32
)(
    input  wire clk,
    input  wire rst_n,

    input  wire       byte_valid,
    input  wire [7:0] byte_data,

    input  wire       num_valid,
    input  wire signed [DATA_W-1:0] num_value,
    input  wire [1:0] num_term, // 0 none, 1 space, 2 newline

    output wire busy,

    output reg        tx_valid,
    output reg  [7:0] tx_byte,
    input  wire       tx_ready
);

    // =========================================================
    // 1-entry queue (absorb controller's 1~2-cycle burst)
    // =========================================================
    reg        q_valid;
    reg        q_is_num;
    reg  [7:0] q_byte;
    reg signed [DATA_W-1:0] q_num;
    reg  [1:0] q_term;

    // current job
    reg        cur_is_num;
    reg  [7:0] cur_byte;
    reg signed [DATA_W-1:0] cur_num;
    reg  [1:0] cur_term;

    wire in_byte = byte_valid;
    wire in_num  = (!byte_valid) && num_valid; // byte 优先

    // =========================================================
    // UART send engine:
    // hold tx_valid HIGH until uart_tx "accepts" it (tx_ready goes LOW),
    // then wait until tx_ready returns HIGH (done).
    // =========================================================
    reg [1:0] send_state;
    localparam SEND_IDLE        = 2'd0;
    localparam SEND_WAIT_ACCEPT = 2'd1;
    localparam SEND_WAIT_DONE   = 2'd2;

    reg        send_req;
    reg  [7:0] send_data;
    reg        send_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            send_state <= SEND_IDLE;
            tx_valid   <= 1'b0;
            tx_byte    <= 8'h00;
            send_done  <= 1'b0;
        end else begin
            send_done <= 1'b0;

            case (send_state)
                SEND_IDLE: begin
                    tx_valid <= 1'b0;
                    if (send_req) begin
                        // launch: keep valid asserted until accepted
                        tx_byte    <= send_data;
                        tx_valid   <= 1'b1;
                        send_state <= SEND_WAIT_ACCEPT;
                    end
                end

                SEND_WAIT_ACCEPT: begin
                    tx_valid <= 1'b1;
                    if (!tx_ready) begin
                        tx_valid   <= 1'b0;
                        send_state <= SEND_WAIT_DONE;
                    end
                end

                SEND_WAIT_DONE: begin
                    tx_valid <= 1'b0;
                    if (tx_ready) begin
                        send_done  <= 1'b1;
                        send_state <= SEND_IDLE;
                    end
                end

                default: send_state <= SEND_IDLE;
            endcase
        end
    end

    wire sender_busy = (send_state != SEND_IDLE);

    // =========================================================
    // Decimal conversion: double-dabble (no / no %)
    // DATA_W=32 => max 10 digits
    // =========================================================
    localparam integer DIGS = 10;
    reg [4*DIGS-1:0] bcd;
    reg [DATA_W-1:0] bin_shift;
    reg [6:0]        conv_cnt;

    reg [3:0] scan_idx;
    reg [3:0] digit_idx;
    reg       neg_flag;

    reg [4*DIGS-1:0] bcd_next;
    reg [DATA_W-1:0] bin_next;

    integer i;

    function [DATA_W-1:0] abs_val;
        input signed [DATA_W-1:0] x;
        begin
            abs_val = x[DATA_W-1] ? (~x + {{(DATA_W-1){1'b0}},1'b1}) : x;
        end
    endfunction

    // =========================================================
    // Main FSM
    // =========================================================
    reg [3:0] state;
    localparam S_IDLE      = 4'd0;
    localparam S_LOAD_JOB  = 4'd1;
    localparam S_BYTE_SEND = 4'd2;

    localparam S_NUM_INIT  = 4'd3;
    localparam S_NUM_CONV  = 4'd4;
    localparam S_NUM_SIGN  = 4'd5;
    localparam S_NUM_FIND  = 4'd6;
    localparam S_NUM_DIGIT = 4'd7;
    localparam S_NUM_TERM  = 4'd8;

    // busy: combinational (no 1-cycle lag)
    assign busy = (state != S_IDLE) || q_valid || sender_busy || (!tx_ready);

    // queue capture (only when we're already busy)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_valid  <= 1'b0;
            q_is_num <= 1'b0;
            q_byte   <= 8'h00;
            q_num    <= {DATA_W{1'b0}};
            q_term   <= 2'd0;
        end else begin
            if ((in_byte || in_num) && busy) begin
                if (!q_valid) begin
                    q_valid  <= 1'b1;
                    q_is_num <= in_num;
                    q_byte   <= byte_data;
                    q_num    <= num_value;
                    q_term   <= num_term;
                end
            end

            // dequeue on load
            if (state == S_LOAD_JOB && q_valid) begin
                q_valid <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            send_req   <= 1'b0;
            send_data  <= 8'h00;

            cur_is_num <= 1'b0;
            cur_byte   <= 8'h00;
            cur_num    <= {DATA_W{1'b0}};
            cur_term   <= 2'd0;

            bcd        <= {4*DIGS{1'b0}};
            bin_shift  <= {DATA_W{1'b0}};
            conv_cnt   <= 7'd0;
            scan_idx   <= 4'd0;
            digit_idx  <= 4'd0;
            neg_flag   <= 1'b0;
        end else begin
            // defaults
            send_req <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (q_valid) begin
                        state <= S_LOAD_JOB;
                    end else if (in_byte || in_num) begin
                        cur_is_num <= in_num;
                        cur_byte   <= byte_data;
                        cur_num    <= num_value;
                        cur_term   <= num_term;
                        state      <= S_LOAD_JOB;
                    end
                end

                S_LOAD_JOB: begin
                    if (q_valid) begin
                        cur_is_num <= q_is_num;
                        cur_byte   <= q_byte;
                        cur_num    <= q_num;
                        cur_term   <= q_term;
                    end
                    state <= (q_valid ? q_is_num : cur_is_num) ? S_NUM_INIT : S_BYTE_SEND;
                end

                // -------- byte --------
                // 关键修复：send_done 优先，避免 done 那拍又发起 send_req
                S_BYTE_SEND: begin
                    if (send_done) begin
                        state <= S_IDLE;
                    end else if (!sender_busy) begin
                        send_data <= cur_byte;
                        send_req  <= 1'b1;
                    end
                end

                // -------- number --------
                S_NUM_INIT: begin
                    neg_flag  <= cur_num[DATA_W-1];
                    bcd       <= {4*DIGS{1'b0}};
                    bin_shift <= abs_val(cur_num);
                    conv_cnt  <= DATA_W[6:0];
                    state     <= S_NUM_CONV;
                end

                S_NUM_CONV: begin
                    if (conv_cnt != 0) begin
                        bcd_next = bcd;
                        for (i = 0; i < DIGS; i = i + 1) begin
                            if (bcd_next[i*4 +: 4] >= 4'd5)
                                bcd_next[i*4 +: 4] = bcd_next[i*4 +: 4] + 4'd3;
                        end
                        bin_next = {bin_shift[DATA_W-2:0], 1'b0};
                        bcd_next = {bcd_next[4*DIGS-2:0], bin_shift[DATA_W-1]};

                        bcd       <= bcd_next;
                        bin_shift <= bin_next;
                        conv_cnt  <= conv_cnt - 1'b1;
                    end else begin
                        state <= S_NUM_SIGN;
                    end
                end

                // 关键修复：send_done 优先
                S_NUM_SIGN: begin
                    if (neg_flag) begin
                        if (send_done) begin
                            scan_idx <= DIGS-1;
                            state    <= S_NUM_FIND;
                        end else if (!sender_busy) begin
                            send_data <= 8'h2D; // '-'
                            send_req  <= 1'b1;
                        end
                    end else begin
                        scan_idx <= DIGS-1;
                        state    <= S_NUM_FIND;
                    end
                end

                S_NUM_FIND: begin
                    if (bcd[scan_idx*4 +: 4] != 4'd0) begin
                        digit_idx <= scan_idx;
                        state     <= S_NUM_DIGIT;
                    end else if (scan_idx == 0) begin
                        digit_idx <= 0; // all zero => print single '0'
                        state     <= S_NUM_DIGIT;
                    end else begin
                        scan_idx <= scan_idx - 1'b1;
                    end
                end

                // 关键修复：send_done 优先
                S_NUM_DIGIT: begin
                    if (send_done) begin
                        if (digit_idx == 0) state <= S_NUM_TERM;
                        else digit_idx <= digit_idx - 1'b1;
                    end else if (!sender_busy) begin
                        send_data <= 8'h30 + {4'd0, bcd[digit_idx*4 +: 4]};
                        send_req  <= 1'b1;
                    end
                end

                // 关键修复：send_done 优先
                S_NUM_TERM: begin
                    if (cur_term != 2'd0) begin
                        if (send_done) begin
                            state <= S_IDLE;
                        end else if (!sender_busy) begin
                            send_data <= (cur_term == 2'd1) ? 8'h20 : 8'h0A;
                            send_req  <= 1'b1;
                        end
                    end else begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
