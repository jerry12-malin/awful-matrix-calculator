`timescale 1ns/1ps

module uart_rx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rxd,
    output reg  rx_valid,
    output reg  [7:0] rx_byte
);
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam integer HALF_CLKS = CLKS_PER_BIT / 2;
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
    localparam integer CTR_W = clog2(CLKS_PER_BIT);

    reg [CTR_W-1:0] clk_ctr;
    reg [3:0] bit_idx;
    reg [7:0] data;
    reg busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_valid <= 1'b0;
            rx_byte  <= 8'h00;
            clk_ctr  <= {CTR_W{1'b0}};
            bit_idx  <= 4'd0;
            data     <= 8'h00;
            busy     <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            if (!busy) begin
                if (!uart_rxd) begin
                    busy    <= 1'b1;
                    clk_ctr <= {CTR_W{1'b0}};
                    bit_idx <= 4'd0;
                end
            end else begin
                if (clk_ctr == CLKS_PER_BIT - 1) begin
                    clk_ctr <= {CTR_W{1'b0}};
                    if (bit_idx < 4'd8) begin
                        data[bit_idx] <= uart_rxd;
                        bit_idx <= bit_idx + 1'b1;
                    end else begin
                        busy    <= 1'b0;
                        rx_byte <= data;
                        rx_valid <= 1'b1;
                        bit_idx <= 4'd0;
                    end
                end else if (clk_ctr == HALF_CLKS - 1 && bit_idx == 4'd0) begin
                    if (uart_rxd) begin
                        busy <= 1'b0;
                    end
                    clk_ctr <= clk_ctr + 1'b1;
                end else begin
                    clk_ctr <= clk_ctr + 1'b1;
                end
            end
        end
    end
endmodule