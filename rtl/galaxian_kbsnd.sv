//============================================================================
//
//  King & Balloon speech board (MAME kingball_sound_map / _portmap): Z80 at
//  2.5 MHz, 8K ROM at 0000-1FFF (A15-A14 ignored, 2000-3FFF open), no IRQs;
//  any I/O read returns the command latch, any I/O write drives a 4-bit DAC
//  from D7-D4. The RAM MAME maps under the ROM is never readable.
//
//============================================================================

module galaxian_kbsnd
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               pause,

    input         [7:0] latch,

    input        [12:0] rom_addr,
    input         [7:0] rom_data,
    input               rom_we,

    output reg    [3:0] dac = 4'd0
);

// 2.5 MHz = 49.152 MHz x 625 / 12288
reg [13:0] frac = 14'd0;
reg        cen = 1'b0;
always @(posedge clk) begin
    if (frac >= 14'd11663) begin frac <= frac - 14'd11663; cen <= ~pause; end
    else                   begin frac <= frac + 14'd625;   cen <= 1'b0;   end
end

wire        m1_n, mreq_n, iorq_n, rd_n, wr_n;
wire [15:0] addr;
wire  [7:0] dout, rom_q;

dpram_dc #(.widthad_a(13)) rom
(
    .clock_a(clk), .address_a(rom_addr), .data_a(rom_data), .wren_a(rom_we),
    .clock_b(clk), .address_b(addr[12:0]), .q_b(rom_q)
);

wire [7:0] din = ~iorq_n ? latch : !addr[13] ? rom_q : 8'hFF;

T80sed cpu
(
    .RESET_n(~reset),
    .CLK_n(clk),
    .CLKEN(cen),
    .WAIT_n(1'b1),
    .INT_n(1'b1),
    .NMI_n(1'b1),
    .BUSRQ_n(1'b1),
    .M1_n(m1_n),
    .MREQ_n(mreq_n),
    .IORQ_n(iorq_n),
    .RD_n(rd_n),
    .WR_n(wr_n),
    .RFSH_n(),
    .HALT_n(),
    .BUSAK_n(),
    .A(addr),
    .DI(din),
    .DO(dout)
);

always @(posedge clk) if (~iorq_n & m1_n & ~wr_n) dac <= dout[7:4];

endmodule
