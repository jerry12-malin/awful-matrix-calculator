`timescale 1ns/1ps

module clk_enable_gen #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer EN_HZ  = 1
)(
    input  wire clk,
    input  wire rst_n,
    output reg  en_pulse
);
    localparam integer COUNT_MAX = CLK_HZ / EN_HZ;
    function integer clog2;
        input integer value;
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1) begin
                value = value >> 1;
            end
            clog2 = i;
        end
    endfunction
    localparam integer CNT_W = clog2(COUNT_MAX + 1);

    reg [CNT_W-1:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= {CNT_W{1'b0}};
            en_pulse <= 1'b0;
        end else begin
            if (cnt == COUNT_MAX - 1) begin
                cnt <= {CNT_W{1'b0}};
                en_pulse <= 1'b1;
            end else begin
                cnt <= cnt + 1'b1;
                en_pulse <= 1'b0;
            end
        end
    end
endmodule