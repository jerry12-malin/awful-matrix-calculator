`timescale 1ns/1ps

module matrix_store #(
    parameter integer MAX_M = 5,
    parameter integer MAX_N = 5,
    parameter integer MAX_PER_DIM = 5,
    parameter integer DATA_W = 16
)(
    input  wire clk,
    input  wire rst_n,

    input  wire [2:0] cfg_max_per_dim,

    input  wire store_start,
    input  wire [2:0] store_m,
    input  wire [2:0] store_n,
    input  wire store_data_valid,
    input  wire [5:0] store_index,
    input  wire signed [DATA_W-1:0] store_data,
    input  wire store_done,
    output reg  [2:0] store_id,

    input  wire [2:0] rd_m,
    input  wire [2:0] rd_n,
    input  wire [2:0] rd_id,
    input  wire [5:0] rd_index,
    output reg  signed [DATA_W-1:0] rd_data,
    output reg  [2:0] rd_count
);
    localparam integer MAX_ELEMS   = MAX_M * MAX_N;                 // 25
    localparam integer DIM_COUNT   = MAX_M * MAX_N;                 // 25
    localparam integer DIM_STRIDE  = MAX_PER_DIM * MAX_ELEMS;       // 125
    localparam integer USED_DEPTH  = DIM_COUNT * DIM_STRIDE;        // 3125

    // Pad 到 4096（2^12），更利于 BRAM 推断
    localparam integer MEM_DEPTH   = 4096;
    localparam integer ADDR_W      = 12; // log2(4096)

    reg [2:0] count [0:DIM_COUNT-1];
    reg [2:0] wptr  [0:DIM_COUNT-1];
    integer i;

    // (m-1)*MAX_N+(n-1)
    wire [5:0] dim_idx    = (store_m - 1'b1) * MAX_N + (store_n - 1'b1);
    wire [5:0] rd_dim_idx = (rd_m    - 1'b1) * MAX_N + (rd_n    - 1'b1);

    // 地址：dim*DIM_STRIDE + id*MAX_ELEMS + elem
    wire [ADDR_W-1:0] waddr =
        (dim_idx    * DIM_STRIDE) + (wptr[dim_idx] * MAX_ELEMS) + store_index;

    wire [ADDR_W-1:0] raddr =
        (rd_dim_idx * DIM_STRIDE) + (rd_id         * MAX_ELEMS) + rd_index;

    // BRAM
    (* ram_style = "block" *)
    reg [DATA_W-1:0] mem [0:MEM_DEPTH-1];

    // 读地址打一拍（同步读延迟 1）
    //reg [ADDR_W-1:0] raddr_r;

    // 控制寄存器（允许 async reset）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < DIM_COUNT; i = i + 1) begin
                count[i] <= 3'd0;
                wptr[i]  <= 3'd0;
            end
            store_id <= 3'd0;
        end else begin
            if (store_start) begin
                store_id <= wptr[dim_idx];
            end

            if (store_done) begin
                if (count[dim_idx] < cfg_max_per_dim)
                    count[dim_idx] <= count[dim_idx] + 1'b1;

                if (wptr[dim_idx] == (cfg_max_per_dim - 1'b1))
                    wptr[dim_idx] <= 3'd0;
                else
                    wptr[dim_idx] <= wptr[dim_idx] + 1'b1;
            end
        end
    end

    // 写口：单独 always，**不要 reset**
    always @(posedge clk) begin
        if (store_data_valid) begin
            mem[waddr] <= store_data[DATA_W-1:0];
        end
    end

    // 读口：单独 always，**不要 async reset**
//    always @(posedge clk) begin
//        raddr_r <= raddr;
//        rd_data <= $signed(mem[raddr_r]);
//    end

    always @(posedge clk) begin
        //raddr_r <= raddr;
        rd_data <= $signed(mem[raddr]);
    end

    // 计数：组合输出
    always @(*) begin
        rd_count = count[rd_dim_idx];
    end

endmodule
