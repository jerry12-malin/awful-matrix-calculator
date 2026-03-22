`timescale 1ns/1ps

module lfsr_rng #(
    parameter integer WIDTH = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    output reg  [WIDTH-1:0] value
);
    wire feedback = value[WIDTH-1] ^ value[2] ^ value[1] ^ value[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            //value <= {WIDTH{1'b1}};
            value<=16'hACE1;
        end else if (enable) begin
            value <= {value[WIDTH-2:0], feedback};
        end
    end
endmodule