`timescale 1ns/1ps

module conv2d #(
    parameter integer DATA_W = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [DATA_W*9-1:0] kernel,
    output reg  done,
    output reg  [15:0] cycle_count,
    output reg  [DATA_W*80-1:0] out_mat
);
    reg [3:0] row;
    reg [3:0] col;
    reg [3:0] kidx;
    reg signed [DATA_W+8:0] acc;
    reg active;
    wire [6:0] rom_addr;
    wire [3:0] rom_data;
    reg signed [DATA_W-1:0] k_val;

    input_image_rom u_rom (
        .clk(clk),
        .addr(rom_addr),
        .data(rom_data)
    );

    assign rom_addr = (row + (kidx / 3)) * 12 + (col + (kidx % 3));

    function [DATA_W-1:0] get_kernel;
        input [DATA_W*9-1:0] vec;
        input integer idx;
        begin
            get_kernel = vec[idx*DATA_W +: DATA_W];
        end
    endfunction

    task set_out;
        input integer idx;
        input [DATA_W-1:0] val;
        begin
            out_mat[idx*DATA_W +: DATA_W] = val;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row <= 4'd0;
            col <= 4'd0;
            kidx <= 4'd0;
            acc <= 0;
            active <= 1'b0;
            done <= 1'b0;
            cycle_count <= 16'd0;
            out_mat <= {DATA_W*80{1'b0}};
        end else begin
            done <= 1'b0;
            if (start) begin
                row <= 4'd0;
                col <= 4'd0;
                kidx <= 4'd0;
                acc <= 0;
                active <= 1'b1;
                cycle_count <= 16'd0;
            end else if (active) begin
                cycle_count <= cycle_count + 1'b1;
                k_val <= get_kernel(kernel, kidx);
                acc <= acc + $signed({1'b0, rom_data}) * k_val;
                if (kidx == 4'd8) begin
                    set_out(row*10 + col, acc[DATA_W-1:0]);
                    acc <= 0;
                    kidx <= 4'd0;
                    if (col == 4'd9) begin
                        col <= 4'd0;
                        if (row == 4'd7) begin
                            active <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            row <= row + 1'b1;
                        end
                    end else begin
                        col <= col + 1'b1;
                    end
                end else begin
                    kidx <= kidx + 1'b1;
                end
            end
        end
    end
endmodule