//  Based on MAME galaxold.cpp (Nicola Salmoria, Stephane Humbert, BSD-3-Clause)

// Nuova Videotron sound board (Donkey King Jr., Dingo, Jungle King): Z80 + AY-3-8910 at 1.536 MHz (49.152 MHz / 32).
// ROM 0000-1FFF, RAM 4000-43FF, command latch read at 7800 (written by the main CPU's OUT C0), AY data / address on
// I/O 80 / C0, IRQ at VBLANK held until acknowledged. 6000 / 6001 = Donkey King Jr.'s sprite / tile gfx banks.
module galaxian_vtsnd
(
    input               clk,
    input               reset,
    input               pause,

    input               cmd_wr,
    input         [7:0] cmd,
    input               vblank_irq,

    output              gb1_we,         // 6000: sprite bank
    output              gb0_we,         // 6001: tile bank
    output        [7:0] gb_d,

    output chip_pool_pkg::z80sed_i_t z80sed_1_i,
    input  chip_pool_pkg::z80sed_o_t z80sed_1_o,
    output chip_pool_pkg::ayr_i_t    ay_0_i,
    input  chip_pool_pkg::ayio_o_t   ay_0_o,
    output       [13:0] rom0_a,
    input         [7:0] rom0_d,
    output ram_pool_pkg::pram_i_t [8:0] pr_i,
    input  ram_pool_pkg::pram_o_t [8:0] pr_o
);

reg [7:0] latch = 8'd0;

reg [4:0] div = 5'd0;
wire      cen = div == 5'd0;
always @(posedge clk) div <= div + 5'd1;

wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
wire [15:0] addr;
wire  [7:0] dout;
reg   [7:0] din;
reg         int_n = 1'b1;

assign z80sed_1_i.reset_n = ~reset;
assign z80sed_1_i.wait_n  = 1'b1;
assign z80sed_1_i.ce      = cen & ~pause;
assign z80sed_1_i.int_n   = int_n;
assign z80sed_1_i.nmi_n   = 1'b1;
assign z80sed_1_i.di      = din;
assign addr   = z80sed_1_o.a;
assign dout   = z80sed_1_o.dout;
assign m1_n   = z80sed_1_o.m1_n   | reset;
assign mreq_n = z80sed_1_o.mreq_n | reset;
assign iorq_n = z80sed_1_o.iorq_n | reset;
assign rd_n   = z80sed_1_o.rd_n   | reset;
assign wr_n   = z80sed_1_o.wr_n   | reset;
assign rfsh_n = z80sed_1_o.rfsh_n | reset;

always @(posedge clk) begin
    if (cmd_wr) latch <= cmd;
    if (reset | (~iorq_n & ~m1_n)) int_n <= 1'b1;
    else if (vblank_irq)           int_n <= 1'b0;
end

wire mem = ~mreq_n & rfsh_n;
wire io  = ~iorq_n & m1_n;

wire rom_cs   = mem && addr[15:13] == 3'b000;
wire ram_cs   = mem && addr[15:10] == 6'b010000;
wire latch_rd = mem && addr == 16'h7800;

reg  wr_d = 1'b1;
always @(posedge clk) wr_d <= wr_n;
wire wr_p = ~wr_n & wr_d;

assign gb1_we = wr_p & mem & addr == 16'h6000;
assign gb0_we = wr_p & mem & addr == 16'h6001;
assign gb_d   = dout;

assign rom0_a = {1'b0, addr[12:0]};

wire [7:0] ram_q;
assign pr_i[8].a_addr = {6'd0, addr[9:0]};
assign pr_i[8].a_d    = dout;
assign pr_i[8].a_we   = ram_cs & ~wr_n;
assign pr_i[8].b_addr = 16'd0;
assign pr_i[8].b_d    = 8'd0;
assign pr_i[8].b_we   = 1'b0;
assign ram_q = pr_o[8].a_q;
assign pr_i[7:0] = '0;

wire ay_data_w = ~wr_n & io & addr[7:0] == 8'h80;
wire ay_addr_w = ~wr_n & io & addr[7:0] == 8'hC0;

assign ay_0_i.rst_n  = ~reset;
assign ay_0_i.ce     = cen & ~pause;
assign ay_0_i.bdir   = ay_addr_w | ay_data_w;
assign ay_0_i.bc1    = ay_addr_w;
assign ay_0_i.din    = dout;
assign ay_0_i.ioa_in = 8'hFF;
assign ay_0_i.iob_in = 8'hFF;

always @(*) begin
    din = 8'hFF;
    if      (rom_cs)   din = rom0_d;
    else if (ram_cs)   din = ram_q;
    else if (latch_rd) din = latch;
end

endmodule
