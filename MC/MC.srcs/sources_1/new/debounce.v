`timescale 1ns/1ps

module debounce #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst_n,
    input  wire noisy,
    output reg  clean
);

    localparam integer COUNT_MAX = (CLK_HZ / 1000) * DEBOUNCE_MS;
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
    reg sync_0, sync_1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0 <= 1'b0;
            sync_1 <= 1'b0;
        end else begin
            sync_0 <= noisy;
            sync_1 <= sync_0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= {CNT_W{1'b0}};
            clean <= 1'b0;
        end else begin
            if (sync_1 == clean) begin
                cnt <= {CNT_W{1'b0}};
            end else begin
                if (cnt == COUNT_MAX[CNT_W-1:0]) begin
                    clean <= sync_1;
                    cnt <= {CNT_W{1'b0}};
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end
endmodule
                