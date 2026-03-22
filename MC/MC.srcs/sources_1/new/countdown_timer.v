`timescale 1ns/1ps

module countdown_timer #(
    parameter integer CLK_HZ = 100_000_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [7:0] start_value,
    output reg  active,
    output reg  [7:0] remaining
);
    wire tick_1hz;

    clk_enable_gen #(
        .CLK_HZ(CLK_HZ),
        .EN_HZ(1)
    ) u_tick (
        .clk(clk),
        .rst_n(rst_n),
        .en_pulse(tick_1hz)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            remaining <= 8'd0;
        end else begin
            if (start) begin
                active <= 1'b1;
                remaining <= start_value;
            end else if (active && tick_1hz) begin
                if (remaining > 0) begin
                    remaining <= remaining - 1'b1;
                end else begin
                    active <= 1'b0;
                end
            end
        end
    end
endmodule