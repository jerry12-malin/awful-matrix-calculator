`timescale 1ns/1ps

module mat_add #(
    parameter integer MAX_M = 5,
    parameter integer MAX_N = 5,
    parameter integer DATA_W = 16
)(
    input  wire [2:0] m,
    input  wire [2:0] n,
    input  wire [DATA_W*MAX_M*MAX_N-1:0] a_mat,
    input  wire [DATA_W*MAX_M*MAX_N-1:0] b_mat,
    output reg  [DATA_W*MAX_M*MAX_N-1:0] out_mat
);
    localparam integer MAX_ELEMS = MAX_M * MAX_N;
    integer idx;
    reg signed [DATA_W-1:0] a_val;
    reg signed [DATA_W-1:0] b_val;

    function [DATA_W-1:0] get_elem;
        input [DATA_W*MAX_ELEMS-1:0] vec;
        input integer id;
        begin
            get_elem = vec[id*DATA_W +: DATA_W];
        end
    endfunction

    task set_elem;
        input integer id;
        input [DATA_W-1:0] val;
        begin
            out_mat[id*DATA_W +: DATA_W] = val;
        end
    endtask

    always @(*) begin
        out_mat = {DATA_W*MAX_ELEMS{1'b0}};
        for (idx = 0; idx < MAX_ELEMS; idx = idx + 1) begin
            if (idx < m*n) begin
                a_val = get_elem(a_mat, idx);
                b_val = get_elem(b_mat, idx);
                set_elem(idx, a_val + b_val);
            end
        end
    end
endmodule