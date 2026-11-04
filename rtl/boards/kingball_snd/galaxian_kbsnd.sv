//  Based on MAME galaxian.cpp (Aaron Giles, Couriersud, Stephane Humbert, Robbbert, BSD-3-Clause)

module galaxian_kbsnd
(
    input               clk,
    input               reset,
    input               pause,

    input         [7:0] latch,

    output chip_pool_pkg::z80sed_i_t z80sed_1_i,
    input  chip_pool_pkg::z80sed_o_t z80sed_1_o,
    output       [13:0] rom0_a,
    input         [7:0] rom0_d,

    output reg    [3:0] dac = 4'd0
);

reg [13:0] frac = 14'd0;
reg        cen = 1'b0;
always @(posedge clk) begin
    if (frac >= 14'd11663) begin frac <= frac - 14'd11663; cen <= ~pause; end
    else                   begin frac <= frac + 14'd625;   cen <= 1'b0;   end
end

wire        m1_n, mreq_n, iorq_n, rd_n, wr_n;
wire [15:0] addr;
wire  [7:0] dout, rom_q;

assign rom0_a = {1'b0, addr[12:0]};
assign rom_q  = rom0_d;

wire [7:0] din = ~iorq_n ? latch : !addr[13] ? rom_q : 8'hFF;

assign z80sed_1_i.reset_n = ~reset;
assign z80sed_1_i.wait_n  = 1'b1;
assign z80sed_1_i.ce      = cen;
assign z80sed_1_i.int_n   = 1'b1;
assign z80sed_1_i.nmi_n   = 1'b1;
assign z80sed_1_i.di      = din;
assign addr   = z80sed_1_o.a;
assign dout   = z80sed_1_o.dout;
assign m1_n   = z80sed_1_o.m1_n   | reset;
assign mreq_n = z80sed_1_o.mreq_n | reset;
assign iorq_n = z80sed_1_o.iorq_n | reset;
assign rd_n   = z80sed_1_o.rd_n   | reset;
assign wr_n   = z80sed_1_o.wr_n   | reset;

always @(posedge clk) if (~iorq_n & m1_n & ~wr_n) dac <= dout[7:4];

endmodule
