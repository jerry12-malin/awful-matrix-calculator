`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire tx_valid,
    input  wire [7:0] tx_byte,
    output reg  tx_ready,
    output reg  uart_txd
);
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
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
    reg [9:0] shift;
    reg busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_txd <= 1'b1;
            tx_ready <= 1'b1;
            clk_ctr  <= {CTR_W{1'b0}};
            bit_idx  <= 4'd0;
            shift    <= 10'h3FF;
            busy     <= 1'b0;
        end else begin
            if (!busy) begin
                uart_txd <= 1'b1;
                clk_ctr  <= {CTR_W{1'b0}};
                bit_idx  <= 4'd0;
                if (tx_valid) begin
                    shift    <= {1'b1, tx_byte, 1'b0};
                    busy     <= 1'b1;
                    tx_ready <= 1'b0;
                    uart_txd <= 1'b0;
                end else begin
                    tx_ready <= 1'b1;
                end
            end else begin
                if (clk_ctr == CLKS_PER_BIT - 1) begin
                    clk_ctr <= {CTR_W{1'b0}};
                    bit_idx <= bit_idx + 1'b1;
                    shift   <= {1'b1, shift[9:1]};
                    uart_txd <= shift[1];
                    if (bit_idx == 4'd9) begin
                        busy     <= 1'b0;
                        tx_ready <= 1'b1;
                        uart_txd <= 1'b1;
                        bit_idx  <= 4'd0;
                    end
                end else begin
                    clk_ctr <= clk_ctr + 1'b1;
                end
            end
        end
    end
endmodule