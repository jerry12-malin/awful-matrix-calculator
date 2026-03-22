`timescale 1ns/1ps

module matrix_calculator_top #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200,
    parameter integer MAX_M  = 5,
    parameter integer MAX_N  = 5,
    parameter integer MAX_PER_DIM = 5,
    parameter integer DATA_W = 16
)(
    input  wire clk100mhz,
    input  wire rst_n,
    input  wire uart_rxd,
    output wire uart_txd,
    input  wire [9:0] sw,
    input  wire btn_confirm,
    output wire [15:0] led,
    output wire [7:0] seg,
    output wire [7:0] an
);
    wire rx_valid;
    wire [7:0] rx_byte;
    wire tx_ready;
    wire tx_valid;
    wire [7:0] tx_byte;

    uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_rx (
        .clk(clk100mhz),
        .rst_n(rst_n),
        .uart_rxd(uart_rxd),
        .rx_valid(rx_valid),
        .rx_byte(rx_byte)
    );
    
    uart_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_tx (
        .clk(clk100mhz),
        .rst_n(rst_n),
        .tx_valid(tx_valid),
        .tx_byte(tx_byte),
        .tx_ready(tx_ready),
        .uart_txd(uart_txd)
    );
     wire parser_valid;
    wire signed [DATA_W-1:0] parser_number;

    ascii_number_parser #(
        .DATA_W(DATA_W)
    ) u_parser (
        .clk(clk100mhz),
        .rst_n(rst_n),
        .rx_valid(rx_valid),
        .rx_byte(rx_byte),
        .number_valid(parser_valid),
        .number(parser_number)
    );
    
    wire debounced_btn;
    //wire debounced_btn = btn_confirm;
    debounce u_debounce (
        .clk(clk100mhz),
        .rst_n(rst_n),
        .noisy(btn_confirm),
        .clean(debounced_btn)
    );
    
    wire btn_pulse;
    edge_detect u_edge (
        .clk(clk100mhz),
        .rst_n(rst_n),
        .sig(debounced_btn),
        .rise(btn_pulse)
    );
    wire printer_busy;
    wire byte_valid;
    wire [7:0] byte_data;
    wire num_valid;
    wire signed [31:0] num_value;
    wire [1:0] num_term;

    uart_printer u_printer (
        .clk(clk100mhz),
        .rst_n(rst_n),
        .byte_valid(byte_valid),
        .byte_data(byte_data),
        .num_valid(num_valid),
        .num_value(num_value),
        .num_term(num_term),
        .busy(printer_busy),
        .tx_valid(tx_valid),
        .tx_byte(tx_byte),
        .tx_ready(tx_ready)
    );
    
    wire [2:0] cfg_max_per_dim;
    wire signed [DATA_W-1:0] cfg_elem_min;
    wire signed [DATA_W-1:0] cfg_elem_max;
    wire [7:0] cfg_countdown;

    wire store_start;
    wire [2:0] store_m;
    wire [2:0] store_n;
    wire store_data_valid;
    wire [5:0] store_index;
    wire signed [DATA_W-1:0] store_data;
    wire store_done;
    wire [2:0] store_id;
    wire [2:0] rd_m;
    wire [2:0] rd_n;
    wire [2:0] rd_id;
    wire [5:0] rd_index;
    wire signed [DATA_W-1:0] rd_data;
    wire [2:0] rd_count;

    matrix_store #(
        .MAX_M(MAX_M),
        .MAX_N(MAX_N),
        .MAX_PER_DIM(MAX_PER_DIM),
        .DATA_W(DATA_W)
    ) u_store (
        .clk(clk100mhz),
        .rst_n(rst_n),
        .cfg_max_per_dim(cfg_max_per_dim),
        .store_start(store_start),
        .store_m(store_m),
        .store_n(store_n),
        .store_data_valid(store_data_valid),
        .store_index(store_index),
        .store_data(store_data),
        .store_done(store_done),
        .store_id(store_id),
        .rd_m(rd_m),
        .rd_n(rd_n),
        .rd_id(rd_id),
        .rd_index(rd_index),
        .rd_data(rd_data),
        .rd_count(rd_count)
    );
     wire rng_enable;
    wire [15:0] rng_value;

    lfsr_rng u_rng (
        .clk(clk100mhz),
        .rst_n(rst_n),
         .enable(rng_enable),
        .value(rng_value)
    );
    
    wire countdown_start;
    wire [7:0] countdown_value;
    wire countdown_active;
    wire [7:0] countdown_remain;

    countdown_timer #(
        .CLK_HZ(CLK_HZ)
    ) u_countdown (
        .clk(clk100mhz),
        .rst_n(rst_n),
        .start(countdown_start),
        .start_value(countdown_value),
        .active(countdown_active),
        .remaining(countdown_remain)
    );
    
    wire [63:0] sevenseg_chars;
    wire led_error;

    controller_fsm #(
        .MAX_M(MAX_M),
        .MAX_N(MAX_N),
        .MAX_PER_DIM(MAX_PER_DIM),
        .DATA_W(DATA_W)
    ) u_ctrl (
        .clk(clk100mhz),
        .rst_n(rst_n),
        .sw(sw),
        .btn_confirm(btn_pulse),
        .rx_valid(rx_valid),
        .rx_byte(rx_byte),
        .number_valid(parser_valid),
        .number(parser_number),
        .led_error(led_error),
        .sevenseg_chars(sevenseg_chars),
        .store_start(store_start),
        .store_m(store_m),
        .store_n(store_n),
        .store_data_valid(store_data_valid),
        .store_index(store_index),
        .store_data(store_data),
        .store_done(store_done),
        .store_id(store_id),
        .rd_m(rd_m),
        .rd_n(rd_n),
        .rd_id(rd_id),
        .rd_index(rd_index),
        .rd_data(rd_data),
        .rd_count(rd_count),
        .byte_valid(byte_valid),
        .byte_data(byte_data),
        .num_valid(num_valid),
        .num_value(num_value),
        .num_term(num_term),
        .printer_busy(printer_busy),
        .rng_enable(rng_enable),
        .rng_value(rng_value),
        .countdown_start(countdown_start),
        .countdown_value(countdown_value),
        .countdown_active(countdown_active),
        .countdown_remain(countdown_remain),
        .cfg_max_per_dim(cfg_max_per_dim),
        .cfg_elem_min(cfg_elem_min),
        .cfg_elem_max(cfg_elem_max),
        .cfg_countdown(cfg_countdown)
    );
    sevenseg_driver u_sevenseg (
        .clk(clk100mhz),
        .rst_n(rst_n),
        .chars(sevenseg_chars),
        .seg(~seg),
        .an(~an)
    );
    
    assign led[0] = printer_busy;
    assign led[1] = tx_valid;
    assign led[2] = tx_ready;
    assign led[3] = rx_valid;
    assign led[15:4] = 12'd0;

    //assign led = {15'd0, led_error};
    
endmodule
