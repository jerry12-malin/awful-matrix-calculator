`timescale 1ns/1ps

module edge_detect(
    input  wire clk,
    input  wire rst_n,
    input  wire sig,
    output reg  rise
);
    reg sig_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sig_d <= 1'b0;
            rise <= 1'b0;
        end else begin
            rise <= sig & ~sig_d;
            sig_d <= sig;
        end
    end
endmodule