`timescale 1ns/1ps

module mat_mul #(
    parameter integer MAX_M  = 5,
    parameter integer MAX_N  = 5,
    parameter integer DATA_W = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,   // 1-cycle pulse
    output reg                          busy,
    output reg                          done,    // 1-cycle pulse when finished

    input  wire [2:0]                   m,
    input  wire [2:0]                   n,
    input  wire [2:0]                   p,
    input  wire [DATA_W*MAX_M*MAX_N-1:0] a_mat,
    input  wire [DATA_W*MAX_M*MAX_N-1:0] b_mat,
    output reg  [DATA_W*MAX_M*MAX_N-1:0] out_mat
);
    localparam integer MAX_ELEMS = MAX_M * MAX_N;

    // 累加位宽：16x16=32，再加最多5项，留足裕量
    localparam integer ACC_W = DATA_W*2 + 4; // 36

    // i,j,k 计数器（i:0..m-1, j:0..p-1, k:0..n-1）
    reg [2:0] i_r, j_r, k_r;
    reg signed [ACC_W-1:0] acc_r;

    // 取向量中第 idx 个元素（signed）
    function automatic signed [DATA_W-1:0] get_elem_s;
        input [DATA_W*MAX_ELEMS-1:0] vec;
        input [5:0] idx;
        begin
            get_elem_s = vec[idx*DATA_W +: DATA_W];
        end
    endfunction

    // 计算索引（小位宽乘法，开销很小）
    wire [5:0] a_idx_w   = i_r * n + k_r; // A[i,k]
    wire [5:0] b_idx_w   = k_r * p + j_r; // B[k,j]
    wire [5:0] out_idx_w = i_r * p + j_r; // C[i,j]

    wire signed [DATA_W-1:0] a_val_w = get_elem_s(a_mat, a_idx_w);
    wire signed [DATA_W-1:0] b_val_w = get_elem_s(b_mat, b_idx_w);

    // 让乘法尽量推 DSP
    (* use_dsp = "yes" *) wire signed [2*DATA_W-1:0] prod_w = a_val_w * b_val_w;
    wire signed [ACC_W-1:0] prod_ext_w = {{(ACC_W-2*DATA_W){prod_w[2*DATA_W-1]}}, prod_w};
    wire signed [ACC_W-1:0] acc_plus_prod;
    assign acc_plus_prod = acc_r + prod_ext_w;
    
    integer t;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy   <= 1'b0;
            done   <= 1'b0;
            i_r    <= 3'd0;
            j_r    <= 3'd0;
            k_r    <= 3'd0;
            acc_r  <= 0;
            out_mat <= 0;
        end else begin
            done <= 1'b0; // 默认不完成

            // 启动：清输出、清计数器
            if (start && !busy) begin
                busy  <= 1'b1;
                i_r   <= 3'd0;
                j_r   <= 3'd0;
                k_r   <= 3'd0;
                acc_r <= 0;

                // 清 out_mat（固定 25 个元素，不会炸资源）
                for (t = 0; t < MAX_ELEMS; t = t + 1) begin
                    out_mat[t*DATA_W +: DATA_W] <= 0;
                end

                // 若维度非法，直接结束（防御）
                if (m == 0 || n == 0 || p == 0) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
            else if (busy) begin
                // 每拍做一次乘加：acc += A[i,k]*B[k,j]
                // k==0 时 acc_r 仍是 0，这里统一写成累加
//                acc_r <= acc_r + prod_ext_w;
                acc_r <= acc_plus_prod;

                if (k_r == (n - 1'b1)) begin
                    // 本点积结束：写 C[i,j]，然后推进到下一个 (i,j)
                    // 本拍 acc_r 更新是 non-blocking，因此写入用 (acc_r + prod_ext_w)
                    out_mat[out_idx_w*DATA_W +: DATA_W] <= acc_plus_prod[DATA_W-1:0];

                    // 推进 (i,j)
                    if ((i_r == (m - 1'b1)) && (j_r == (p - 1'b1))) begin
                        // 全部完成
                        busy <= 1'b0;
                        done <= 1'b1;
                        // 计数器可不管
                        acc_r <= 0;
                        k_r   <= 3'd0;
                    end else begin
                        // 下一个输出点
                        if (j_r == (p - 1'b1)) begin
                            j_r <= 3'd0;
                            i_r <= i_r + 1'b1;
                        end else begin
                            j_r <= j_r + 1'b1;
                        end
                        k_r   <= 3'd0;
                        acc_r <= 0; // 为下一个点积清零
                    end
                end else begin
                    // 点积未结束：k++
                    k_r <= k_r + 1'b1;
                end
            end
        end
    end
endmodule
