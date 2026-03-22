`timescale 1ns/1ps
module bringup_top(
    input  wire clk100mhz,
    input  wire rst_n,
    input  wire btn_confirm,
    input  wire [9:0] sw,
    output wire [15:0] led,
    output wire [7:0] seg,
    output wire [7:0] an,
    input  wire uart_rxd,
    output wire uart_txd
);
    // UART 不测，先保持空闲高
    assign uart_txd = 1'b1;

    // 1Hz heartbeat（在非 reset 时闪）
    reg [26:0] cnt;
    reg hb;
    always @(posedge clk100mhz or negedge rst_n) begin
        if(!rst_n) begin
            cnt <= 0;
            hb  <= 1'b0;
        end else begin
            if(cnt == 27'd100_000_000-1) begin
                cnt <= 0;
                hb  <= ~hb;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

    // LED：把 rst_n、btn_confirm、sw[3:0]、heartbeat 显示出来
    assign led[0]  = rst_n;        // 不按 reset 应为 1；按下应变 0
    assign led[1]  = ~rst_n;
    assign led[2]  = btn_confirm;  // 按下应为 1（你说按钮高有效）
    assign led[3]  = hb;           // 心跳
    assign led[7:4]= sw[3:0];      // 开关映射验证
    assign led[15:8]= 8'h00;

    // 数码管强制全灭：下面两组你二选一试
    // 方案1：若你的板子是"低电平点亮"(active-low)，全灭应输出全 1
    assign seg = 8'hFF;
    assign an  = 8'hFF;

    // 方案2：若你的板子是"高电平点亮"(active-high)，全灭应输出全 0
    // assign seg = 8'h00;
    // assign an  = 8'h00;
endmodule
