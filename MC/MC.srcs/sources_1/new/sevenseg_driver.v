`timescale 1ns/1ps

module sevenseg_driver #(
    parameter integer CLK_HZ = 100_000_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [63:0] chars,
    output reg  [7:0] seg,
    output reg  [7:0] an
);
    localparam integer REFRESH_HZ = 1000;
    wire tick;

    clk_enable_gen #(
        .CLK_HZ(CLK_HZ),
        .EN_HZ(REFRESH_HZ)
    ) u_refresh (
        .clk(clk),
        .rst_n(rst_n),
        .en_pulse(tick)
    );

    reg [2:0] idx;
    reg [7:0] cur_char;

    function [7:0] seg_map;
        input [7:0] c;
        begin
            case (c)
                "0": seg_map = 8'b11000000;
                "1": seg_map = 8'b11111001;
                "2": seg_map = 8'b10100100;
                "3": seg_map = 8'b10110000;
                "4": seg_map = 8'b10011001;
                "5": seg_map = 8'b10010010;
                "6": seg_map = 8'b10000010;
                "7": seg_map = 8'b11111000;
                "8": seg_map = 8'b10000000;
                "9": seg_map = 8'b10010000;
                "A": seg_map = 8'b10001000;
                "B": seg_map = 8'b10000011;
                "C": seg_map = 8'b11000110;
                "J": seg_map = 8'b11100001;
                "T": seg_map = 8'b10000111;
                "-": seg_map = 8'b10111111;
                default: seg_map = 8'b11111111;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx <= 3'd0;
            seg <= 8'hFF;
            an <= 8'hFF;
        end else begin
            if (tick) begin
                idx <= idx + 1'b1;
            end
            case (idx)
                3'd0: cur_char <= chars[7:0];
                3'd1: cur_char <= chars[15:8];
                3'd2: cur_char <= chars[23:16];
                3'd3: cur_char <= chars[31:24];
                3'd4: cur_char <= chars[39:32];
                3'd5: cur_char <= chars[47:40];
                3'd6: cur_char <= chars[55:48];
                3'd7: cur_char <= chars[63:56];
                default: cur_char <= 8'h20;
            endcase
            seg <= seg_map(cur_char);
            an <= ~(8'b00000001 << idx);
        end
    end
endmodule