//  Based on MAME galaxian.cpp (Aaron Giles, Couriersud, Stephane Humbert, Robbbert, BSD-3-Clause)

module galaxian_sndcpu
(
    input               clk,
    input               reset,
    input               mode,
    input               pause,

    input               cmd_wr,
    input         [7:0] cmd,
    input               vblank_irq,
    input               line8_irq,

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

reg [14:0] frac = 15'd0;
reg        cen = 1'b0;
always @(posedge clk) begin
    if (frac >= 15'd19805) begin frac <= frac - 15'd19805; cen <= 1'b1; end
    else                   begin frac <= frac + 15'd675;   cen <= 1'b0; end
end

wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
wire [15:0] addr;
wire  [7:0] dout;
reg   [7:0] din;
reg         int_n = 1'b1;
reg         nmi_n = 1'b1;
reg   [6:0] nmi_hold = 7'd0;

assign z80sed_1_i.reset_n = ~reset;
assign z80sed_1_i.wait_n  = 1'b1;
assign z80sed_1_i.ce      = cen & ~pause;
assign z80sed_1_i.int_n   = int_n;
assign z80sed_1_i.nmi_n   = nmi_n;
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
    if (cmd_wr) begin
        latch    <= cmd;
        nmi_hold <= 7'd127;
    end
    else if (nmi_hold != 7'd0) nmi_hold <= nmi_hold - 7'd1;
    nmi_n <= nmi_hold == 7'd0;

    if (reset | (~iorq_n & ~m1_n)) int_n <= 1'b1;
    else if (mode ? line8_irq : vblank_irq) int_n <= 1'b0;
end

wire mem = ~mreq_n & rfsh_n;
wire io  = ~iorq_n & m1_n;

wire rom_cs = mem && addr[15:12] == 4'h0;
wire ram_cs = mem && (mode ? addr[15:10] == 6'b100000 : addr[15:10] == 6'b001000);
wire ay_mem = mode && mem && addr[15:2] == 14'h2800;

wire [7:0] rom_q, ram_q;

assign rom0_a = {2'b00, addr[11:0]};
assign rom_q  = rom0_d;

assign pr_i[8].a_addr = {6'd0, addr[9:0]};
assign pr_i[8].a_d    = dout;
assign pr_i[8].a_we   = ram_cs & ~wr_n;
assign pr_i[8].b_addr = 16'd0;
assign pr_i[8].b_d    = 8'd0;
assign pr_i[8].b_we   = 1'b0;
assign ram_q = pr_o[8].a_q;
assign pr_i[7:0] = '0;

wire [7:0] port = addr[7:0];
wire ay_addr_w = ~wr_n & (mode ? ay_mem & addr[1:0] == 2'd0 : ~mode & io & port == 8'h04);
wire ay_data_w = ~wr_n & (mode ? ay_mem & addr[1:0] == 2'd1 : ~mode & io & port == 8'h05);
wire ay_rd     = ~rd_n & (mode ? ay_mem & addr[1:0] == 2'd2 : ~mode & io & port == 8'h06);

reg [17:0] cm_frac = 18'd0;
reg [14:0] cj_frac = 15'd0;
reg        cm_cen = 1'b0, cj_cen = 1'b0;
always @(posedge clk) begin
    if (cm_frac >= 18'd189449) begin cm_frac <= cm_frac - 18'd189449; cm_cen <= 1'b1; end
    else                       begin cm_frac <= cm_frac + 18'd7159;   cm_cen <= 1'b0; end
    if (cj_frac >= 15'd19805)  begin cj_frac <= cj_frac - 15'd19805;  cj_cen <= 1'b1; end
    else                       begin cj_frac <= cj_frac + 15'd675;    cj_cen <= 1'b0; end
end

wire [7:0] ay_dout = ay_0_o.dout;
assign ay_0_i.rst_n  = ~reset;
assign ay_0_i.ce     = ~pause & (mode ? cj_cen : cm_cen);
assign ay_0_i.bdir   = ay_addr_w | ay_data_w;
assign ay_0_i.bc1    = ay_addr_w | ay_rd;
assign ay_0_i.din    = dout;
assign ay_0_i.ioa_in = latch;
assign ay_0_i.iob_in = 8'hFF;

always @(*) begin
    din = 8'hFF;
    if      (rom_cs) din = rom_q;
    else if (ram_cs) din = ram_q;
    else if (ay_rd)  din = ay_dout;
    else if (io && !mode && port == 8'h03) din = latch;
end

endmodule
