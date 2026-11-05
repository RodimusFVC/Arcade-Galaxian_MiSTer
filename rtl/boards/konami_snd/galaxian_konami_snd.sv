//  Based on MAME galaxian.cpp (Aaron Giles, Couriersud, Stephane Humbert, Robbbert, BSD-3-Clause)

module galaxian_konami_snd
(
    input               clk,
    input               reset,
    input               two_ay,
    input               fr_timer,
    input               timer_9000,
    input               no_filter,
    input               hb_map,
    input               rom12k,
    input               hs_map,
    input               irq_set,
    input               scorpion,
    input               harem,
    input               ad2083,
    input               tms_prom_we,
    input               pause,

    input               latch_we,
    input         [7:0] latch_d,
    input         [7:0] control,        // PPI 1 port B: [3] falling edge = IRQ, [4] mute

    output chip_pool_pkg::z80sed_i_t     z80sed_1_i,
    input  chip_pool_pkg::z80sed_o_t     z80sed_1_o,
    output chip_pool_pkg::ayr_i_t        ay_2_i,
    input  chip_pool_pkg::ay_o_t         ay_2_o,
    output chip_pool_pkg::ayr_i_t        ay_3_i,
    input  chip_pool_pkg::ay_o_t         ay_3_o,
    output chip_pool_pkg::ayr_i_t        ay_4_i,
    input  chip_pool_pkg::ay_o_t         ay_4_o,
    output chip_pool_pkg::tmsprom_i_t    tmsprom_0_i,
    input  chip_pool_pkg::tmsprom_o_t    tmsprom_0_o,
    output chip_pool_pkg::tms5110_i_t    tms5110_0_i,
    input  chip_pool_pkg::tms5110_o_t    tms5110_0_o,
    output chip_pool_pkg::digitalker_i_t digitalker_0_i,
    input  chip_pool_pkg::digitalker_o_t digitalker_0_o,
    output       [13:0] rom0_a,
    input         [7:0] rom0_d,
    output ram_pool_pkg::pram_i_t [8:0] pr_i,
    input  ram_pool_pkg::pram_o_t [8:0] pr_o,

    input        [13:0] rom_addr,
    input         [7:0] rom_data,
    input               rom_swap01,
    input               swap4k,

    output signed [15:0] out
);

reg [9:0] frac = 10'd0;
reg       cen = 1'b0;
always @(posedge clk) begin
    if (frac >= 10'd794) begin frac <= frac - 10'd794; cen <= ~pause; end
    else                 begin frac <= frac + 10'd30;  cen <= 1'b0;   end
end

wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
wire [15:0] addr;
wire  [7:0] dout;
reg   [7:0] din;
reg         int_n = 1'b1;
wire               dk_intr;
wire signed [15:0] dk_out;

assign z80sed_1_i.reset_n = ~reset;
assign z80sed_1_i.wait_n  = 1'b1;
assign z80sed_1_i.ce      = cen;
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

reg [7:0] latch = 8'd0;
reg       ctl3_d = 1'b0;
wire      latch_rd;
always @(posedge clk) begin
    if (latch_we) latch <= latch_d;
    ctl3_d <= control[3];
    if (reset | (hs_map ? latch_rd : ~iorq_n & ~m1_n)) int_n <= 1'b1;
    else if (irq_set | (~hs_map & ctl3_d & ~control[3])) int_n <= 1'b0;
end

wire mem = ~mreq_n & rfsh_n;
wire io  = ~iorq_n & m1_n;

wire rom_cs = mem && (hb_map ? addr[15:14] == 2'b00 : two_ay ? addr[15:13] == 3'b000 || (rom12k && addr[15:12] == 4'h2) :
                      addr[14:13] == 2'b00);
wire ram_cs = mem && (hb_map || harem ? addr[15:12] == 4'h8 : two_ay ? addr[15] && !addr[12] : addr[14:13] == 2'b10);
wire flt_cs = mem && ~wr_n && !hb_map && !harem && (two_ay ? addr[15] && addr[12] : addr[14:13] == 2'b11);

wire [7:0] rom_q, ram_q;
wire [7:0] rom_d = rom_swap01 && addr[13:12] == 2'b00 && (swap4k || !addr[11]) ? {rom_q[7:2], rom_q[0], rom_q[1]} : rom_q;

assign rom0_a = addr[13:0];
assign rom_q  = rom0_d;

assign pr_i[7].a_addr = {4'd0, hb_map ? addr[11:10] : 2'b00, addr[9:0]};
assign pr_i[7].a_d    = dout;
assign pr_i[7].a_we   = ram_cs & ~wr_n;
assign pr_i[7].b_addr = 16'd0;
assign pr_i[7].b_d    = 8'd0;
assign pr_i[7].b_we   = 1'b0;
assign ram_q = pr_o[7].a_q;
assign pr_i[6:0] = '0;
assign pr_i[8]   = '0;

wire io_w = io & ~wr_n;
wire io_r = io & ~rd_n;
wire ay_k    = (two_ay | hb_map) & ~hs_map;
wire a1_addr_w = io_w & (ay_k ? addr[6] : ~addr[6] & addr[7]);
wire a1_data_w = io_w & (ay_k ? ~addr[6] & addr[7] : addr[6]);
wire a1_rd     = io_r & (ay_k ? addr[7] : addr[6]);

reg  [7:0] a1_reg = 8'd0;
always @(posedge clk) if (a1_addr_w) a1_reg <= dout;
assign latch_rd = a1_rd & (a1_reg == 8'h0E);
wire a2_addr_w = two_ay & io_w & addr[4];
wire a2_data_w = two_ay & io_w & ~addr[4] & addr[5];
wire a2_rd     = two_ay & io_r & addr[5];
wire a3_addr_w = scorpion & io_w & addr[2];
wire a3_data_w = scorpion & io_w & ~addr[2] & addr[3];
wire a3_rd     = scorpion & io_r & addr[3];

reg [15:0] tcnt = 16'd0;
always @(posedge clk) if (cen) tcnt <= tcnt >= 16'd40952 ? 16'd0 : tcnt + 16'd8;
wire        t_hi  = tcnt >= 16'd20480;
wire [15:0] t_low = t_hi ? tcnt - 16'd20480 : tcnt;
wire  [7:0] timer = {t_hi, t_low[14], t_low[13], t_low[11], 4'b1110};
wire  [7:0] timer_fr = {timer[7:6], timer[3], timer[4], timer[5], timer[2:0]};

wire [7:0] a1_dout, a2_dout;
wire [7:0] a1A, a1B, a1C, a2A, a2B, a2C;

assign ay_2_i.rst_n  = ~reset;
assign ay_2_i.ce     = cen;
assign ay_2_i.bdir   = a1_addr_w | a1_data_w;
assign ay_2_i.bc1    = a1_addr_w | a1_rd;
assign ay_2_i.din    = dout;
assign ay_2_i.ioa_in = latch;
assign ay_2_i.iob_in = two_ay && !fr_timer ? timer : timer_fr;
assign a1_dout = ay_2_o.dout;  assign a1A = ay_2_o.a;  assign a1B = ay_2_o.b;  assign a1C = ay_2_o.c;

assign ay_3_i.rst_n  = ~reset;
assign ay_3_i.ce     = cen;
assign ay_3_i.bdir   = a2_addr_w | a2_data_w;
assign ay_3_i.bc1    = a2_addr_w | a2_rd;
assign ay_3_i.din    = dout;
assign ay_3_i.ioa_in = ad2083 ? timer : 8'hFF;
assign ay_3_i.iob_in = 8'hFF;
assign a2_dout = ay_3_o.dout;  assign a2A = ay_3_o.a;  assign a2B = ay_3_o.b;  assign a2C = ay_3_o.c;

wire [7:0] a3_dout, a3A, a3B, a3C;

assign ay_4_i.rst_n  = ~reset & scorpion;
assign ay_4_i.ce     = cen;
assign ay_4_i.bdir   = a3_addr_w | a3_data_w;
assign ay_4_i.bc1    = a3_addr_w | a3_rd;
assign ay_4_i.din    = dout;
assign ay_4_i.ioa_in = 8'hFF;
assign ay_4_i.iob_in = 8'hFF;
assign a3_dout = ay_4_o.dout;  assign a3A = ay_4_o.a;  assign a3B = ay_4_o.b;  assign a3C = ay_4_o.c;

always @(*) begin
    din = 8'hFF;
    if      (scorpion && mem && addr[15:12] == (harem ? 4'h6 : 4'h3)) din = {7'd0, dk_intr};
    else if (rom_cs) din = rom_d;
    else if (ram_cs) din = ram_q;
    else if (io_r)   din = (a1_rd ? a1_dout : 8'hFF) & (a2_rd ? a2_dout : 8'hFF) & (a3_rd ? a3_dout : 8'hFF);
    else if (timer_9000 && mem && addr == 16'h9000) din = timer;
end

reg [11:0] flt = 12'd0;
always @(posedge clk) if (cen && flt_cs) flt <= addr[11:0];

reg [9:0] dc_div = 10'd0;
always @(posedge clk) dc_div <= dc_div + 10'd1;
wire cen_dc = dc_div == 10'd0;

function signed [15:0] pick(input [1:0] fsel, input signed [15:0] d, input signed [15:0] l, input signed [15:0] m,
                            input signed [15:0] h);
    case (fsel)
        2'b00: pick = d;
        2'b10: pick = l;
        2'b01: pick = m;
        default: pick = h;
    endcase
endfunction

wire [7:0] ch_raw [6];
assign ch_raw[0] = a1A; assign ch_raw[1] = a1B; assign ch_raw[2] = a1C;
assign ch_raw[3] = a2A; assign ch_raw[4] = a2B; assign ch_raw[5] = a2C;

wire signed [15:0] ch_out [6];
genvar i;
generate
    for (i = 0; i < 6; i = i + 1) begin : chan
        wire signed [15:0] dcr, lt, md, hv;
        jt49_dcrm2 #(16) dcrm(.clk(clk), .cen(cen_dc), .rst(reset), .din({3'd0, ch_raw[i], 5'd0}), .dout(dcr));
        tp_lpf_light  f_l(.clk(clk), .reset(reset), .in(dcr), .out(lt));
        tp_lpf_medium f_m(.clk(clk), .reset(reset), .in(dcr), .out(md));
        tp_lpf_heavy  f_h(.clk(clk), .reset(reset), .in(dcr), .out(hv));
        wire [1:0] sel = i < 3 ? {flt[7 + 2 * i], flt[6 + 2 * i]} : {flt[1 + 2 * (i - 3)], flt[2 * (i - 3)]};
        assign ch_out[i] = no_filter ? dcr : pick(sel, dcr, lt, md, hv);
    end
endgenerate

reg  [3:0] a3_reg = 4'd0;
reg  [7:0] dk_data = 8'hFF;
reg  [2:0] dk_ctl = 3'b111;
always @(posedge clk) begin
    if (reset) begin a3_reg <= 4'd0; dk_data <= 8'hFF; dk_ctl <= 3'b111; end
    else begin
        if (a3_addr_w) a3_reg <= dout[3:0];
        else if (a3_data_w && a3_reg == 4'd14) dk_data <= dout;
        else if (a3_data_w && a3_reg == 4'd15) dk_ctl <= dout[2:0];
    end
end

assign digitalker_0_i.reset = reset | ~scorpion;
assign digitalker_0_i.data  = dk_data;
assign digitalker_0_i.cs    = dk_ctl[0];
assign digitalker_0_i.cms   = dk_ctl[1];
assign digitalker_0_i.wr    = dk_ctl[2];
assign dk_intr = digitalker_0_o.intr;
assign dk_out  = digitalker_0_o.sample;

// A.D. 2083 speech: I/O 01 D2-D0 = ROM bit (reversed), D7-D3 = 1 / 3 selects ROM 1 / 0
reg  [2:0] tms_bit = 3'd0;
reg        io_w_d = 1'b0;
reg        tms_en = 1'b0, tms_en_lo = 1'b0, tms_cs0 = 1'b1, tms_cs1 = 1'b1;
always @(posedge clk) begin
    tms_cs0 <= 1'b1;
    tms_cs1 <= 1'b1;
    if (reset) begin
        tms_bit <= 3'd0; tms_en <= 1'b0; tms_en_lo <= 1'b0;
    end
    else if (tms_en_lo) begin
        tms_en    <= 1'b1;
        tms_en_lo <= 1'b0;
    end
    else if (ad2083 && io_w && addr[7:0] == 8'h01 && !io_w_d) begin
        tms_bit   <= {dout[0], dout[1], dout[2]};
        tms_cs1   <= dout[7:3] != 5'd1;
        tms_cs0   <= dout[7:3] != 5'd3;
        tms_en    <= 1'b0;
        tms_en_lo <= 1'b1;
    end
end
always @(posedge clk) io_w_d <= io_w;

reg  [9:0] tms_acc = 10'd0;
reg  [5:0] tms_div = 6'd0;
reg        tms_ce = 1'b0, tms_smp = 1'b0;
always @(posedge clk) begin
    tms_ce  <= 1'b0;
    tms_smp <= 1'b0;
    if (pause) ;
    else if (tms_acc >= 10'd763) begin
        tms_acc <= tms_acc - 10'd763;
        tms_ce  <= 1'b1;
        tms_div <= tms_div == 6'd39 ? 6'd0 : tms_div + 6'd1;
        tms_smp <= tms_div == 6'd39;
    end
    else tms_acc <= tms_acc + 10'd5;
end

wire  [3:0] tms_ctl;
wire        tms_pdc, tms_m0, tms_data, tms_busy;
wire signed [15:0] tms_out;

assign tmsprom_0_i.reset      = reset | ~ad2083;
assign tmsprom_0_i.ce_romclk  = tms_ce;
assign tmsprom_0_i.chip_busy  = tms_busy;
assign tmsprom_0_i.enable     = tms_en;
assign tmsprom_0_i.bit_sel    = tms_bit;
assign tmsprom_0_i.csq0       = tms_cs0;
assign tmsprom_0_i.csq1       = tms_cs1;
assign tmsprom_0_i.prom_wr    = tms_prom_we;
assign tmsprom_0_i.prom_waddr = rom_addr[4:0];
assign tmsprom_0_i.prom_wdata = rom_data;
assign tmsprom_0_i.m0         = tms_m0;
assign tms_data = tmsprom_0_o.data_bit;
assign tms_ctl  = tmsprom_0_o.ctl;
assign tms_pdc  = tmsprom_0_o.pdc;

assign tms5110_0_i.reset     = reset | ~ad2083;
assign tms5110_0_i.ce_sample = tms_smp;
assign tms5110_0_i.ctl       = tms_ctl;
assign tms5110_0_i.pdc       = tms_pdc;
assign tms5110_0_i.data_bit  = tms_data;
assign tms_m0   = tms5110_0_o.m0;
assign tms_busy = tms5110_0_o.busy;
assign tms_out  = tms5110_0_o.sample;

wire [9:0]  a3_sum = {2'b00, a3A} + {2'b00, a3B} + {2'b00, a3C};
wire signed [15:0] a3_dcr;
jt49_dcrm2 #(16) a3_dcrm(.clk(clk), .cen(cen_dc), .rst(reset), .din({1'b0, a3_sum, 5'd0}), .dout(a3_dcr));
wire signed [18:0] a3_out = scorpion ? (19'(a3_dcr) >>> 2) * 19'sd3 : 19'sd0;

wire signed [18:0] sum = 19'(ch_out[0]) + 19'(ch_out[1]) + 19'(ch_out[2]) +
                         (two_ay ? 19'(ch_out[3]) + 19'(ch_out[4]) + 19'(ch_out[5]) : 19'sd0) + a3_out;
// Digitalker: Scorpion >>> 3 (HW OK 2026-11-04); Harem >>> 2 (user by ear on HW 2026-11-04: speech ~2x)
wire signed [18:0] amp = (control[4] ? 19'sd0 : -sum) + (scorpion ? 19'(dk_out >>> (harem ? 2 : 3)) : 19'sd0) +
                         (ad2083 ? 19'(tms_out >>> 3) : 19'sd0);
assign out = amp > 19'sd32767 ? 16'sd32767 : amp < -19'sd32767 ? -16'sd32767 : amp[15:0];

endmodule
