`timescale 1ns/1ps

module mat_transpose #(
    parameter integer MAX_M = 5,
    parameter integer MAX_N = 5,
    parameter integer DATA_W = 16
)(
    input  wire [2:0] m,
    input  wire [2:0] n,
    input  wire [DATA_W*MAX_M*MAX_N-1:0] in_mat,
    output reg  [DATA_W*MAX_M*MAX_N-1:0] out_mat
);
    localparam integer MAX_ELEMS = MAX_M * MAX_N;
    integer i, j;
    reg signed [DATA_W-1:0] in_val;

    function [DATA_W-1:0] get_elem;
        input [DATA_W*MAX_ELEMS-1:0] vec;
        input integer idx;
        begin
            get_elem = vec[idx*DATA_W +: DATA_W];
        end
    endfunction

    task set_elem;
        input integer idx;
        input [DATA_W-1:0] val;
        begin
            out_mat[idx*DATA_W +: DATA_W] = val;
        end
    endtask

    always @(*) begin
        out_mat = {DATA_W*MAX_ELEMS{1'b0}};
        for (i = 0; i < MAX_M; i = i + 1) begin
            for (j = 0; j < MAX_N; j = j + 1) begin
                if (i < m && j < n) begin
                    in_val = get_elem(in_mat, i*n + j);
                    set_elem(j*m + i, in_val);
                end
            end
        end
    end
endmodule