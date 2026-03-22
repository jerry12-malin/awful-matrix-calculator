`timescale 1ns/1ps

module ascii_number_parser #(
    parameter integer DATA_W = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire rx_valid,
    input  wire [7:0] rx_byte,
    output reg  number_valid,
    output reg  signed [DATA_W-1:0] number
);
    reg signed [DATA_W-1:0] accum;
    reg neg;
    reg in_number;

    function is_digit;
        input [7:0] c;
        begin
            is_digit = (c >= 8'd48 && c <= 8'd57);
        end
    endfunction

    function is_space;
        input [7:0] c;
        begin
            is_space = (c == 8'd32 || c == 8'd10 || c == 8'd13 || c == 8'd9);
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            number_valid <= 1'b0;
            number <= {DATA_W{1'b0}};
            accum <= {DATA_W{1'b0}};
            neg <= 1'b0;
            in_number <= 1'b0;
        end else begin
            number_valid <= 1'b0;
            if (rx_valid) begin
                if (is_digit(rx_byte)) begin
                    if (!in_number) begin
                        accum <= {{(DATA_W-4){1'b0}}, rx_byte - 8'd48};
                        in_number <= 1'b1;
                    end else begin
                        accum <= accum * 10 + (rx_byte - 8'd48);
                    end
                end else if (rx_byte == 8'd45 && !in_number) begin
                    neg <= 1'b1;
                end else if (is_space(rx_byte)) begin
                    if (in_number) begin
                        number <= neg ? -accum : accum;
                        number_valid <= 1'b1;
                        accum <= {DATA_W{1'b0}};
                        neg <= 1'b0;
                        in_number <= 1'b0;
                    end else begin
                        neg <= 1'b0;
                    end
                end else begin
                    if (in_number) begin
                        number <= neg ? -accum : accum;
                        number_valid <= 1'b1;
                        accum <= {DATA_W{1'b0}};
                        neg <= 1'b0;
                        in_number <= 1'b0;
                    end
                end
            end
        end
    end
endmodule