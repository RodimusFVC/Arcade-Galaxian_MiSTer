//  Based on MAME galaxian.cpp (Aaron Giles, Couriersud, Stephane Humbert, Robbbert, BSD-3-Clause)
//  Derived from "FPGA GALAXIAN" by Katsumi Degawa (c) 2004 and the MiSTer Galaxian port by Alexey Melnikov (Sorgelig)

module galaxian_board
(
    input               clk,
    input               reset,
    input         [2:0] ph,
    input               pause,

    input         [7:0] variant,
    input         [7:0] vflags,
    input         [7:0] bflags,         // [0] NMI enable on latch 0, [1] 2K work RAM, [2] stars cut, [3] Moon Cresta
    input         [7:0] bflags2,        // [0] no watchdog, [1] no discrete sound, [2] AY on Z80 I/O 00-02 (Bongo),
    input         [7:0] bflags3,
    input         [7:0] vflags2,
    input         [7:0] bflags4,        // [0] 1K object RAM, [1] Zig Zag ROM 2000/3000 swap on 7002, [2] Fantastic ROM
    input         [7:0] vflags3,
    input         [7:0] bflags5,        // [0] Konami sound board (Z80 + AY + filters), [1] its second AY (Scramble),
    input         [7:0] vflags4,
    input         [7:0] bflags6,        // Stern: [0] type 2 as Tazz-Mania 3 (plain PPIs, latches on A3-A0), [1] PPI 1
    input         [7:0] bflags7,        // [0] sound board without RC filters (Hustler), [1] Hustler bootleg sound map,
    input         [7:0] bflags8,
    input         [7:0] bflags9,
    input         [7:0] vflags5,
    input         [7:0] bflags10,
    input         [7:0] bflags12,       // [0] Space Battle (Hoei) speech board, sbhoei_map I/O, RGB -> RBG,
    input         [7:0] bflags13,       // [0] Rack + Roll (racknrol_map: objects 1400-14FF, INT from VBLANK, SENSE =
    input         [7:0] bflags11,
    input         [7:0] rom_top,        // end of program ROM >> 8 (0 = 40)
    input         [7:0] ext_mode,

    input         [7:0] in0,
    input         [7:0] dial1,
    input         [7:0] dial2,
    input         [7:0] in1,
    input         [7:0] in2,
    input         [7:0] in3,
    input         [7:0] dip4,

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               gfx0_we,
    input               gfx1_we,
    input               gfx2_we,
    input               gfxh_we,
    input               pal_we,
    input               bgp_we,
    input               rcg_we,

    input               crt_flip,
    input  signed [3:0] h_adj,
    input  signed [3:0] v_adj,

    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output reg          video_hs = 1'b0,
    output reg          video_vs = 1'b0,
    output reg          video_hblank = 1'b1,
    output reg          video_vblank = 1'b1,

    output        [8:0] hcnt_o,
    output        [8:0] vcnt_o,
    output              n3a_o,
    output        [3:0] lfo_o,
    output        [7:0] snd_o,
    output        [7:0] pitch_o,
    output        [1:0] sb_noise_o,
    output              vbl_irq_o,
    output              line8_irq_o,
    output              cmd_wr_o,
    output        [7:0] cpu_dout_o,
    output        [7:0] kb_latch_o,
    output              msh_trig_o,
    output        [7:0] msh_rate_o,
    output        [4:0] msh_vol_o,
    output              snd_irq_o,
    output              snd_cmd_we_o,
    output        [7:0] ppi_din_o,
    output        [7:0] snd_ctl_o,
    output              sb_cmd_we_o,
    input         [7:0] sb_p1,

    input        [15:0] hs_address,
    input         [7:0] hs_data_in,
    output        [7:0] hs_data_out,
    input               hs_write,

    output chip_pool_pkg::z80sed_i_t  z80sed_0_i,
    input  chip_pool_pkg::z80sed_o_t  z80sed_0_o,
    output chip_pool_pkg::s2650_i_t   s2650_0_i,
    input  chip_pool_pkg::s2650_o_t   s2650_0_o,
    output chip_pool_pkg::t65_i_t     t65_0_i,
    input  chip_pool_pkg::t65_o_t     t65_0_o,
    output chip_pool_pkg::sn76489_i_t sn76489_0_i,
    input  chip_pool_pkg::sn76489_o_t sn76489_0_o,
    output chip_pool_pkg::ayr_i_t     ay_0_i,
    input  chip_pool_pkg::ayio_o_t    ay_0_o,
    output chip_pool_pkg::ayr_i_t     ay_1_i,
    input  chip_pool_pkg::ay_o_t      ay_1_o,
    output chip_pool_pkg::i8255_i_t   i8255_0_i,
    input  chip_pool_pkg::i8255_o_t   i8255_0_o,
    output chip_pool_pkg::i8255_i_t   i8255_1_i,
    input  chip_pool_pkg::i8255_o_t   i8255_1_o,
    input               ppi1_pc_we,

    output       [15:0] rom_a,
    input         [7:0] rom_q,
    output ram_pool_pkg::pram_i_t [3:0] gr_i,
    input  ram_pool_pkg::pram_o_t [3:0] gr_o,
    output ram_pool_pkg::pram_i_t [8:0] pr_i,
    input  ram_pool_pkg::pram_o_t [8:0] pr_o
);

wire ce6 = (ph == 3'd0);

reg [8:0] hcnt = 9'h080;
reg [8:0] vcnt = 9'h0F8;
reg       vblank = 1'b1;

wire vcnt_step     = (hcnt == 9'h0AF);
wire rising_vblank = vcnt_step & (vcnt == 9'h1EF);

wire [8:0] hs_on    = 9'h0B0 + {{4{h_adj[3]}}, h_adj, 1'b0};
wire [8:0] v_line   = vcnt - 9'h0F8;
wire [8:0] vs_start = v_adj[3] ? 9'd264 + {{5{1'b1}}, v_adj} : {5'd0, v_adj};
wire [9:0] vs_end   = {1'b0, vs_start} + 10'd8;

always @(posedge clk) begin
    if (ce6) begin
        hcnt <= (hcnt == 9'h1FF) ? 9'h080 : hcnt + 9'd1;
        if (vcnt_step) begin
            vcnt <= (vcnt == 9'h1FF) ? 9'h0F8 : vcnt + 9'd1;
            if      (vcnt == 9'h1EF) vblank <= 1'b1;
            else if (vcnt == 9'h10F) vblank <= 1'b0;
        end

        video_hblank <= ~hcnt[8];
        video_vblank <= vblank;
        video_hs     <= hcnt >= hs_on && hcnt < hs_on + 9'h020;
        video_vs     <= (v_line >= vs_start && {1'b0, v_line} < vs_end) || (vs_end > 10'd264 && {1'b0, v_line} < vs_end - 10'd264);
    end
end

wire [7:0] top = rom_top == 8'd0 ? 8'h40 : rom_top;

function [16:0] decode(input [15:0] a);
    reg rom, ram, vid, obj, io;
    reg [11:0] ri;
    begin
        rom = a[15:8] < top;
        ri  = {1'b0, bflags[1] & a[10], a[9:0]};
        case (variant[4:0])
            5'd0: begin
                rom = a[15:8] < top || (bflags9[2] && a[15:11] == 5'b11000) || (bflags11[1] && a[15:11] == 5'b10000) ||
                      (bflags13[6] && a[15:13] == 3'b110);
                ram = a[15:11] == 5'b01000 || (bflags10[1] && a[15:11] == 5'b10000) || (bflags6[7] && (a[15:10] == 6'b010010 || a[15:7] == 9'b010110000));
                ri  = bflags10[1] && a[15] ? {1'b1, a[10:0]} :
                      !bflags6[7] ? {1'b0, bflags[1] & a[10], a[9:0]} : a[15:11] == 5'b01000 ? {1'b0, a[10:0]} :
                      a[12] ? {5'b11000, a[6:0]} : {2'b10, a[9:0]};
                vid = a[15:11] == 5'b01010;
                obj = a[15:11] == 5'b01011;
                io  = a[15:13] == 3'b011;
            end
            5'd1, 5'd30: begin
                rom = a[15:8] < top || (variant[4:0] == 5'd30 && a[15:13] == 3'b011);
                ram = a[15:11] == 5'b10000 || (variant[4:0] == 5'd30 && a[15:10] == 6'b010100);
                ri  = a[15] ? {1'b0, bflags[1] & a[10], a[9:0]} : {2'b10, a[9:0]};
                vid = a[15:11] == 5'b10010;
                obj = a[15:11] == 5'b10011;
                io  = a[15:13] == 3'b101;
            end
            5'd2: begin
                rom = a < 16'h4000 || (a >= 16'h5000 && a < 16'h6800);
                ram = a[15:11] == 5'b01000 || a[15:10] == 6'b100000;
                ri  = {a[15], a[10:0]};
                vid = a[15:11] == 5'b10010;
                obj = a[15:11] == 5'b10011;
                io  = a[15:13] == 3'b101;
            end
            5'd5: begin
                ram = a[15:11] == 5'b10000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b10101;
                obj = a[15:11] == 5'b10110;
                io  = 1'b0;
            end
            5'd6, 5'd15, 5'd16, 5'd18, 5'd19: begin
                rom = a[15:8] < top || (bflags7[4] && a[15:12] == 4'hA) || (ext_mode[3:0] == 4'd9 && a[15:14] == 2'b11) ||
                      (bflags11[6] && a >= 16'h5800 && a < 16'h6800) || (bflags13[7] && a >= 16'hA000 && a < 16'hE000);
                ram = a[15:11] == 5'b01000 || (bflags13[7] && a[15:10] == 6'b111010);
                ri  = a[15] ? {2'b10, a[9:0]} : {1'b0, a[10:0]};
                vid = a[15:11] == 5'b01001;
                obj = a[15:11] == 5'b01010;
                io  = variant[4:0] == 5'd18 && a[15:13] == 3'b011;
            end
            5'd20: begin
                ram = a[15:11] == 5'b10000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b10010;
                obj = a[15:11] == 5'b10001;
                io  = a[15:13] == 3'b101;
            end
            5'd17: begin
                rom = a < 16'h4000 || (a >= 16'h5800 && a < 16'h6800);
                ram = a[15:11] == 5'b01000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b01001;
                obj = a[15:11] == 5'b01010;
                io  = 1'b0;
            end
            5'd9: begin
                ram = a[15:11] == 5'b10000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b10001;
                obj = a[15:11] == 5'b10010;
                io  = 1'b0;
            end
            5'd10: begin
                rom = a < 16'h3000;
                ram = a[15:11] == 5'b10000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:10] == 6'b101010;
                obj = a[15:8] == 8'hB0;
                io  = 1'b0;
            end
            5'd11: begin
                ram = a[15:11] == 5'b10000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b10010;
                obj = a[15:8] == 8'h98;
                io  = 1'b0;
            end
            5'd13, 5'd14, 5'd24: begin
                ram = a[15:11] == 5'b10000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b10001;
                obj = a[15:11] == 5'b10010;
                io  = 1'b0;
            end
            5'd12: begin
                ram = a[15:11] == 5'b10000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b10010;
                obj = a[15:8] == 8'h88;
                io  = 1'b0;
            end
            5'd8, 5'd21: begin
                ram = a[15] && a[13:11] == 3'b000;
                ri  = {1'b0, a[10:0]};
                vid = a[15] && a[13:11] == 3'b010;
                obj = a[15] && a[13:11] == 3'b011;
                io  = 1'b0;
            end
            5'd7: begin
                rom = a[15:8] < top || (ext_mode[3:0] == 4'd9 && a[15:14] == 2'b11);
                ram = a[15] && a[13:11] == 3'b000;
                ri  = {1'b0, a[10:0]};
                vid = a[15] && a[13:11] == 3'b001;
                obj = a[15] && a[13:11] == 3'b010;
                io  = 1'b0;
            end
            5'd25, 5'd26: begin
                rom = a < 16'h0400 || (a >= 16'h4000 && a < 16'hC000 && !(variant[4:0] == 5'd26 && a[15:10] == 6'b011111));
                ram = a >= 16'h0400 && a < 16'h0C00;
                ri  = {1'b0, a[10:0]};
                vid = a[15:10] == 6'b000011 || (variant[4:0] == 5'd26 && a[15:10] == 6'b011111);
                obj = variant[4:0] == 5'd25 ? a[15:9] == 7'b0001001 : a[15:10] == 6'b001000;
                io  = 1'b0;
            end
            5'd27: begin
                ram = a >= 16'h0200 && a < 16'h0600;
                ri  = {2'b00, a[9:0]};
                vid = a >= 16'h1200 && a < 16'h1600;
                rom = a < 16'h5000 && !ram && !vid;
                obj = a[15:8] == 8'hFE;
                io  = a[15:13] == 3'b011;
            end
            5'd29: begin
                rom = ~a[15];
                ram = a[15:11] == 5'b11000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b11010;
                obj = a[15:11] == 5'b11011;
                io  = a[15:13] == 3'b111;
            end
            5'd28: begin
                rom = a[15:13] == 3'b000 || a[15:13] == 3'b100;
                ram = a[15:11] == 5'b00100 || (a[15:11] == 5'b01000 && a[10:8] != 3'd0);
                ri  = {a[14], a[10:0]};
                vid = a[15:11] == 5'b01001;
                obj = a[15:8] == 8'h40;
                io  = 1'b0;
            end
            5'd4: begin
                rom = a < 16'h4000 || (a >= 16'h8000 && a < 16'hB000);
                ram = a[15:11] == 5'b01000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b01001;
                obj = a[15:11] == 5'b01010;
                io  = a[15:13] == 3'b011;
            end
            default: begin
                rom = a[15:8] < top || (bflags9[7] && a >= 16'hD400 && a < 16'hE400);
                ram = a[15:11] == 5'b01100 || a[15:10] == 6'b011010;
                ri  = {a[11], a[10:0]};
                vid = a[15:10] == 6'b100100;
                obj = a[15:10] == 6'b100110;
                io  = variant[4:0] == 5'd22 ? a[15:12] == 4'hC : variant[4:0] == 5'd23 ? 1'b0 : a[15:13] == 3'b101;
            end
        endcase
        decode = {rom, ram, vid, obj, io, ri};
    end
endfunction

wire        cpu_m1_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n;
wire [15:0] cpu_addr;
wire  [7:0] cpu_dout;
wire        z80_m1_n, z80_mreq_n, z80_iorq_n, z80_rd_n, z80_wr_n, z80_rfsh_n;
wire [15:0] z80_addr;
wire  [7:0] z80_dout;
wire        s26 = bflags7[6];
reg   [7:0] cpu_din;
reg         cpu_nmi_n = 1'b1;
reg         cpu_int_n = 1'b1;
reg         wait_n = 1'b1;

reg   [7:0] ctl_9n = 8'd0;
reg   [7:0] snd_9l = 8'd0;
reg   [3:0] lfo_9m = 4'hF;
reg   [7:0] pitch  = 8'd0;
reg   [3:0] gfxbank = 4'd0;
reg         gfxbank4 = 1'b0;
reg   [2:0] bg_rgb = 3'd0;
reg   [3:0] watchdog = 4'd0;
wire        watchdog_reset = (watchdog == 4'd8) & ~bflags2[0];

wire        s26_req, s26_wr, s26_mio, s26_ene, s26_dc, s26_intack;
reg         s26_int = 1'b0;
reg  [14:0] s26_lastcode = 15'd0;
wire [14:0] s26_pc = s26_lastcode + 15'd1;
wire        s26_sc = bflags12[1];
reg  [14:0] s26_lastrd = 15'd0;
wire [14:0] s26_ipc = s26_lastrd - 15'd1;
wire        s26_df = bflags12[5];
wire        s26_rk = bflags13[0];
wire        s26_vb = s26_sc | s26_df | s26_rk;
wire [14:0] s26_ad;
wire  [7:0] s26_dw, s26_dr;
wire  [1:0] s26_ph;
reg   [1:0] s26_div = 2'd0;
reg         s26_new = 1'b0, s26_new2 = 1'b0, s26_req_t = 1'b0, s26_mio_t = 1'b1, s26_ene_t = 1'b0, s26_dc_t = 1'b0;
reg         s26_act = 1'b0, s26_io = 1'b0, s26_ene_r = 1'b0, s26_dc_r = 1'b0, s26_w = 1'b0;
reg  [14:0] s26_a = 15'd0;
reg   [7:0] s26_d = 8'd0;
reg   [7:0] sbk_latch = 8'd0;
reg         rk_tb_we = 1'b0, rk_sn_we = 1'b0;

reg  [4:0] s26_pcnt = 5'd0;
wire [4:0] s26_per  = bflags12[3:2] == 2'd1 ? 5'd5 : bflags12[3:2] == 2'd2 ? 5'd23 : 5'd11;
wire s26_ack = s26 & ce6 & ~pause & (bflags12[3:2] == 2'd0 ? hcnt[1:0] == 2'b00 & s26_div == 2'd0 : s26_pcnt == 5'd0);

always @(posedge clk) begin
    if (ce6 && hcnt[1:0] == 2'b00) s26_div <= (s26_div == 2'd2) ? 2'd0 : s26_div + 2'd1;
    if (ce6) s26_pcnt <= s26_pcnt >= s26_per ? 5'd0 : s26_pcnt + 5'd1;
    if (s26_new && s26_req_t && s26_mio_t && s26_ph == 2'b00) s26_lastcode <= s26_ad;
    s26_new  <= s26_ack;
    s26_new2 <= s26_new;
    if (s26_ack) {s26_req_t, s26_mio_t, s26_ene_t, s26_dc_t} <= {s26_req, s26_mio, s26_ene, s26_dc};
    if (reset | watchdog_reset | ~s26) begin
        s26_act <= 1'b1;
        s26_io  <= 1'b0;
        s26_a   <= 15'd0;
        s26_w   <= 1'b0;
    end
    else if (s26_new) begin
        s26_act   <= s26_req_t;
        s26_io    <= ~s26_mio_t;
        s26_ene_r <= s26_ene_t;
        s26_dc_r  <= s26_dc_t;
        s26_a     <= s26_ad;
        s26_w     <= s26_wr;
        s26_d     <= s26_dw;
    end
    if (s26_new2 && s26_act && !s26_io && !s26_w) s26_lastrd <= s26_a;
    rk_tb_we <= s26_new2 && s26_act && s26_io && s26_w && s26_ene_r && s26_a[7:5] == 3'b001 && s26_rk;
    rk_sn_we <= s26_new2 && s26_act && s26_io && s26_w &&
                ((bflags13[1] && s26_ene_r && s26_a[7:0] == 8'h1D) || (bflags13[2] && !s26_ene_r && s26_dc_r));
    if (reset) sbk_latch <= 8'd0;
    else if (s26_new2 && s26_act && s26_io && s26_w && !s26_ene_r && s26_dc_r && bflags7[7]) sbk_latch <= {s26_d[3:0], 4'd0};
end

wire [15:0] s26_saddr = s26_a[11:10] == 2'b11           ? {6'b010000, s26_a[9:0]} :
                        s26_a[11:10] == 2'b10           ? {6'b010010, s26_a[9:0]} :
                        s26_a[11:8] == 4'h4             ? {8'h50, s26_a[7:0]} :
                        s26_a[11:8] == 4'h5             ? {14'h2040, s26_a[1:0]} :
                        s26_a[11:4] == 8'h21            ? {14'h2080, s26_a[1:0]} :
                        s26_a[11:7] == 5'b01100         ? {13'h0D00, s26_a[2:0]} :
                        s26_a[11:7] == 5'b01101 || s26_a[11:7] == 5'b01111 ? 16'h7000 : 16'hFFFF;
wire [15:0] s26_zaddr = ~s26_a[12]               ? {2'b00, s26_a[14:13], s26_a[11:0]} :
                        s26_sc                   ? s26_saddr :
                        s26_rk && s26_a[11:8] == 4'h4 ? {8'h58, s26_a[7:0]} :
                        s26_df && s26_a[11:7] == 5'b01100 ? (s26_w ? 16'h7800 : 16'h7000) :
                        s26_df && s26_a[11:7] == 5'b01110 ? (s26_a[2] ? {14'h1801, s26_a[1:0]} : 16'hFFFF) :
                        s26_df && s26_a[11:7] == 5'b01101 ? 16'hFFFF :
                        s26_a[11:10] == 2'b11     ? {6'b010000, s26_a[9:0]} :
                        s26_a[11:10] == 2'b10     ? {6'b010100, s26_a[9:0]} :
                        s26_a[10:7] == 4'b1001    ? {8'h58, ~s26_a[7], s26_a[6:0]} :
                        s26_a[10:7] == 4'b1010    ? {13'h0C00, s26_a[2:0]} :
                        s26_a[10:7] == 4'b1011    ? {13'h0D00, s26_a[2:0]} :
                        s26_a[10:8] == 3'b110 && !s26_a[7] ? {13'h0E00, s26_a[2:0]} :
                        s26_a[10:8] == 3'b111 && !s26_a[7] ? {13'h0E00, s26_a[2:0]} :
                        s26_a[10:7] == 4'b1101    ? {13'h0F00, s26_a[2:0]} : 16'hFFFF;
wire        s26_mem  = s26_act & ~s26_io;

wire        m65 = bflags11[7];
reg   [4:0] m65_div = 5'd0;
reg         m65_en_d = 1'b0;
wire        m65_en = m65 & m65_div == 5'd0 & ~pause;
always @(posedge clk) begin
    m65_div  <= m65_div + 5'd1;
    m65_en_d <= m65_en;
end
wire [15:0] m65_a;
wire  [7:0] m65_do;
wire        m65_rw;

wire [15:0] m65_zaddr = m65_a[15:14] == 2'b00 ? {2'b01, m65_a[13:0]} :
                        m65_a[15:14] == 2'b11 ? {2'b00, m65_a[13:1], ~m65_a[0]} : m65_a[15:0];
wire s26_dp1 = (bflags13[3] && s26_pc == 15'h0031) || (bflags13[4] && (s26_pc == 15'h009B || s26_pc == 15'h6B58));
assign s26_dr = s26_io && !s26_ene_r && s26_dc_r ? {7'd0, s26_dp1} :
                s26_io ? (s26_ene_r && (s26_a[7:0] == 8'h00 || bflags12[6]) ? (bflags12[4] ? {7'd0, s26_ipc == 15'h0029 || s26_ipc == 15'h0A25} :
                                                               bflags12[6] ? {7'd0, s26_ipc == 15'h002C || s26_ipc == 15'h0295} :
                                                                             sbk_latch) : 8'h00) :
                s26_df && s26_a[12] && s26_a[11:7] == 5'b01110 && !s26_a[2] ? in3 : cpu_din;

assign cpu_m1_n   = s26 | m65 | z80_m1_n;
assign cpu_mreq_n = s26 ? ~s26_mem : ~m65 & z80_mreq_n;
assign cpu_iorq_n = s26 | m65 | z80_iorq_n;
assign cpu_rd_n   = s26 ? ~(s26_mem & ~s26_w) : m65 ? ~m65_rw : z80_rd_n;
assign cpu_wr_n   = s26 ? ~(s26_mem & s26_w) : m65 ? m65_rw : z80_wr_n;
assign cpu_rfsh_n = s26 | m65 | z80_rfsh_n;
assign cpu_addr   = s26 ? s26_zaddr : m65 ? m65_zaddr : z80_addr;
assign cpu_dout   = s26 ? s26_d : m65 ? m65_do : z80_dout;

wire        mem = ~cpu_mreq_n & cpu_rfsh_n;
wire [11:0] ram_idx;
wire        rom_cs, ram_cs, vid_cs, obj_cs, io_cs;
assign      {rom_cs, ram_cs, vid_cs, obj_cs, io_cs, ram_idx} = decode(cpu_addr);
wire  [1:0] io_sel = variant[4:0] == 5'd22 ? cpu_addr[11:10] : cpu_addr[12:11];
wire        jb     = variant[4:0] == 5'd4;
wire        ay_cs  = jb && cpu_addr[15:9] == 7'b0101100;
wire        prot_cs = jb && cpu_addr[15:12] == 4'hB;
wire        fg      = variant[4:0] == 5'd5;
wire        sc      = variant[4:0] == 5'd6;
wire        sb      = variant[4:0] == 5'd7;
wire        tu      = variant[4:0] == 5'd8;
wire        ff      = variant[4:0] == 5'd9;
wire        fa      = variant[4:0] == 5'd10;
wire        ts      = variant[4:0] == 5'd11;
wire        st2     = variant[4:0] == 5'd12;
wire        hb      = variant[4:0] == 5'd13;
wire        hb6     = variant[4:0] == 5'd14;
wire        mr      = variant[4:0] == 5'd15;
wire        mr_lat  = mr && cpu_addr[15:4] == 12'h680;
wire        mmk_rom = ext_mode[3:0] == 4'd9 && cpu_addr[15:14] == 2'b11;
wire        hsk     = variant[4:0] == 5'd16;
wire        sdm     = hsk && bflags12[7];    // Sidam explorer board: Hot Shocker map, 6800 latches, mirrored I/O, wd read
wire        tp      = variant[4:0] == 5'd17;
wire        gs      = variant[4:0] == 5'd18;
wire        sb2     = variant[4:0] == 5'd19;
wire        tzb     = variant[4:0] == 5'd20;
wire        ck2     = variant[4:0] == 5'd23;
wire        ami     = variant[4:0] == 5'd24;
wire        fmc     = bflags10[6];
wire        msh     = bflags11[3];
wire        kb      = bflags11[5];
wire        scp     = bflags11[6];
wire        sbh     = bflags12[0];
wire        stn     = variant[4:0] == 5'd27;
wire        aeu     = variant[4:0] == 5'd25;
wire        aeg     = variant[4:0] == 5'd26;
wire        mdk     = variant[4:0] == 5'd21;
wire        hm      = variant[4:0] == 5'd28;
wire        db      = variant[4:0] == 5'd29;
wire        rc      = variant[4:0] == 5'd30;
wire        fin     = bflags13[6];
wire        ad      = hsk && bflags13[7];
wire        hb_lat  = (hb || hb6) && cpu_addr[15:4] == 12'hA80;
wire        st2_lat = st2 && cpu_addr[15:4] == 12'hB00;
wire        tnv     = sc && bflags5[7];
wire        tnv_rom = tnv && cpu_addr[15:12] == 4'hC;
wire        fg_lat  = fg && cpu_addr[15:11] == 5'b10111;
wire        tu_lat  = (tu && cpu_addr[15] && cpu_addr[13:11] == 3'b100) ||
                      (ami && cpu_addr[15:11] == 5'b10100);
wire        ff_lat  = ff && cpu_addr[15:11] == 5'b10101;
wire        x_lat   = (fa && cpu_addr[15:4] == 12'hB80) ||
                      (ts && cpu_addr[15:4] == 12'hA80);
wire        k_lat   = (sc && !tnv && cpu_addr[15:11] == 5'b01101) ||
                      ((tp || sb2) && cpu_addr[15:11] == 5'b01101) ||
                      (sb && !mmk_rom && cpu_addr[15] && cpu_addr[13:11] == 3'b101) ||
                      (mdk && cpu_addr[15:11] == 5'b10100) ||
                      (ck2 && cpu_addr[15:4] == 12'hA80) ||
                      (aeu && cpu_addr[15:9] == 7'b0001000) || (aeg && cpu_addr[15:9] == 7'b0010011) ||
                      (sdm && cpu_addr[15:11] == 5'b01101);
wire        fg_wd   = (fg && cpu_addr[15:11] == 5'b10001) ||
                      (sc && (cpu_addr[15:11] == 5'b01110 || (bflags5[4] && cpu_addr[15:11] == 5'b01111))) ||
                      (sb && !mmk_rom && cpu_addr[15] && cpu_addr[13:11] == 3'b110) ||
                      (tu && cpu_addr[15] && cpu_addr[13:11] == 3'b101) ||
                      (ff && cpu_addr[15:11] == 5'b10111) ||
                      (fa && cpu_addr == 16'h8800) || (ts && cpu_addr == 16'hB800) ||
                      (st2 && cpu_addr == 16'h9800) || (hb && cpu_addr == 16'hB000) || ((mr || tp) && cpu_addr == 16'h7000) ||
                      (sb2 && cpu_addr[15:3] == 13'h0E00) || (tzb && cpu_addr == 16'h9800) ||
                      (mdk && cpu_addr == 16'hA800) || (ck2 && cpu_addr == 16'hB000) || (ami && cpu_addr == 16'hA800) || (sc && bflags9[6] && cpu_addr[15:11] == 5'b01101) ||
                      (aeu && cpu_addr[15:10] == 6'b000101) || (aeg && cpu_addr[15:9] == 7'b1111010) ||
                      (hm && cpu_addr == 16'h5800) || (ad && cpu_addr == 16'h7000) || (sdm && cpu_addr[15:11] == 5'b01110);
wire        fg_ppi  = (fg && cpu_addr[15:14] == 2'b11) || (sc && cpu_addr[15] && !tnv_rom && !mmk_rom) ||
                      (ff && cpu_addr[15:14] == 2'b11) || (fa && cpu_addr[15:10] == 6'b010000) ||
                      (ts && (cpu_addr[15:2] == 14'h2800 || cpu_addr[15:2] == 14'h3000)) ||
                      (st2 && (cpu_addr[15:4] == 12'hA00 || cpu_addr[15:4] == 12'hA80)) ||
                      (hb && cpu_addr[15:10] == 6'b110000) ||
                      (mr && (cpu_addr[15:4] == 12'h810 || cpu_addr[15:4] == 12'h820)) ||
                      (tp && cpu_addr[15:8] == 8'h81) ||
                      (mdk && cpu_addr[15:12] == 4'hB) || (ck2 && cpu_addr[15:12] == 4'h7) ||
                      (mr && bflags7[4] && (cpu_addr[15:4] == 12'hC10 || cpu_addr[15:4] == 12'hC20)) ||
                      (sb && !mmk_rom && cpu_addr[15] && (cpu_addr[13:11] == 3'b011 || cpu_addr[13:11] == 3'b100)) ||
                      (tu && cpu_addr[15] && cpu_addr[13:12] == 2'b11) || (aeu && cpu_addr[15:14] == 2'b11) ||
                      (aeg && (cpu_addr[15:9] == 7'b0010010 || cpu_addr[15:9] == 7'b1111011)) ||
                      (hm && (cpu_addr[15:8] == 8'h61 || cpu_addr[15:8] == 8'h62));

reg  wr_d = 1'b1;
always @(posedge clk) wr_d <= cpu_wr_n;
wire wr = s26 ? s26_new2 & s26_mem & s26_w : m65 ? m65_en_d & ~m65_rw : mem & ~cpu_wr_n & wr_d;

always @(posedge clk) begin
    if (ce6) wait_n <= ~(mem & vid_cs & ~vblank & ~(hcnt >= 9'h083 && hcnt < 9'h0F7));
end

always @(posedge clk) begin
    if (reset) begin
        ctl_9n  <= 8'd0;
        snd_9l  <= 8'd0;
        lfo_9m  <= 4'hF;
        pitch   <= 8'd0;
        gfxbank <= 4'd0;
        gfxbank4 <= 1'b0;
        bg_rgb   <= 3'd0;
    end
    else if (wr && k_lat) ctl_9n[cpu_addr[2:0]] <= cpu_dout[0];
    else if (wr && ff_lat) begin
        case (cpu_addr[3:1])
            3'd1: ctl_9n[6] <= cpu_dout[0];
            3'd2: ctl_9n[1] <= cpu_dout[0];
            3'd3: ctl_9n[7] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && x_lat) ctl_9n[cpu_addr[2:0]] <= cpu_dout[0];
    else if (wr && hb_lat) begin
        case (cpu_addr[2:0])
            3'd1: ctl_9n[1] <= cpu_dout[0];
            3'd2: if (hb6) ctl_9n[6] <= cpu_dout[0];
            3'd6: ctl_9n[7] <= cpu_dout[0];
            3'd7: if (hb) ctl_9n[6] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && sbh && cpu_addr[15:11] == 5'b10100) begin
        case (cpu_addr[2:0])
            3'd2: gfxbank[0] <= cpu_dout[0];
            3'd3: gfxbank[1] <= cpu_dout[0];
            3'd4: gfxbank[2] <= cpu_dout[0];
            3'd5: gfxbank[3] <= cpu_dout[0];
            3'd6: gfxbank4   <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && msh && cpu_addr[15:11] == 5'b10100) begin
        case (cpu_addr[2:0])
            3'd0: ctl_9n[1] <= cpu_dout[0];
            3'd1: ctl_9n[4] <= cpu_dout[0];
            3'd2: begin ctl_9n[6] <= cpu_dout[0]; ctl_9n[7] <= cpu_dout[0]; end
            default: ;
        endcase
    end
    else if (wr && hm && cpu_addr[15:3] == 13'h0B00) begin
        case (cpu_addr[2:0])
            3'd0: ctl_9n[1] <= cpu_dout[0];
            3'd5: gfxbank[1:0] <= {1'b0, cpu_dout[0]};
            3'd6: ctl_9n[6] <= cpu_dout[0];
            3'd7: ctl_9n[7] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && fin && cpu_addr == 16'h8000) gfxbank[1:0] <= cpu_dout[1:0];
    else if (wr && sb2 && cpu_addr == 16'h7800) pitch <= cpu_dout;
    else if (wr && hsk && !sdm && cpu_addr == 16'h6004) begin ctl_9n[6] <= cpu_dout[0]; ctl_9n[7] <= cpu_dout[0]; end
    else if (wr && hsk && !sdm && cpu_addr == 16'h6006) gfxbank[1:0] <= cpu_dout[1:0];
    else if (wr && hsk && cpu_addr == 16'h6801) ctl_9n[1] <= cpu_dout[0];
    else if (wr && ad && cpu_addr == 16'h6803) bg_rgb[0] <= cpu_dout[0];
    else if (wr && ad && cpu_addr == 16'h6806) bg_rgb[2] <= cpu_dout[0];
    else if (wr && ad && cpu_addr == 16'h6807) bg_rgb[1] <= cpu_dout[0];
    else if (wr && mr_lat) begin
        case (cpu_addr[3:0])
            4'h1: if (bflags8[1]) ctl_9n[1] <= cpu_dout[0]; else ctl_9n[4] <= cpu_dout[0];
            4'h2: if (!bflags8[1]) ctl_9n[1] <= cpu_dout[0];
            4'h9: ctl_9n[6] <= cpu_dout[0];
            4'hB: ctl_9n[7] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && st2_lat && bflags6[0]) begin
        case (cpu_addr[3:0])
            4'h0: ctl_9n[4] <= cpu_dout[0];
            4'h1: ctl_9n[1] <= cpu_dout[0];
            4'h2: if (bflags6[4]) ctl_9n[3] <= cpu_dout[0];
            4'hC: ctl_9n[7] <= cpu_dout[0];
            4'hE: ctl_9n[6] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && st2_lat) begin
        case (cpu_addr[3:1])
            3'd0: if (bflags6[3]) bg_rgb[1] <= cpu_dout[0]; else ctl_9n[4] <= cpu_dout[0];
            3'd1: if (bflags6[3]) bg_rgb[0] <= cpu_dout[0]; else if (bflags6[4]) ctl_9n[3] <= cpu_dout[0];
            3'd2: ctl_9n[1] <= cpu_dout[0];
            3'd5: if (bflags6[3]) bg_rgb[2] <= cpu_dout[0];
            3'd6: ctl_9n[7] <= cpu_dout[0];
            3'd7: ctl_9n[6] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && tnv && cpu_addr[15:11] == 5'b01101) begin
        case (cpu_addr[2:0])
            3'd1: ctl_9n[1] <= cpu_dout[0];
            3'd3: bg_rgb[0] <= cpu_dout[0];
            3'd4: bg_rgb[1] <= cpu_dout[0];
            3'd5: bg_rgb[2] <= cpu_dout[0];
            3'd6: ctl_9n[6] <= cpu_dout[0];
            3'd7: ctl_9n[7] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && tu_lat) begin
        case (cpu_addr[5:3])
            3'd0: bg_rgb[2] <= cpu_dout[0];
            3'd1: ctl_9n[1] <= cpu_dout[0];
            3'd2: ctl_9n[7] <= cpu_dout[0];
            3'd3: ctl_9n[6] <= cpu_dout[0];
            3'd4: bg_rgb[1] <= cpu_dout[0];
            3'd5: bg_rgb[0] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && fg_lat) begin
        case (cpu_addr[4:2])
            3'd2: ctl_9n[1] <= cpu_dout[0];
            3'd3: ctl_9n[7] <= cpu_dout[0];
            3'd4: ctl_9n[6] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && io_cs) begin
        case (io_sel)
            2'd0: if (jb) case (cpu_addr[2:0])
                      3'd2: gfxbank[1:0] <= {1'b0, cpu_dout[0]};
                      3'd3: gfxbank[2] <= cpu_dout[0];
                      3'd4: gfxbank[3] <= cpu_dout[0];
                      3'd6: gfxbank4 <= cpu_dout[0];
                      default: ;
                  endcase
                  else if (cpu_addr[2]) lfo_9m[cpu_addr[1:0]] <= cpu_dout[0];
                  else if (fin) ;
                  else if (cpu_addr[1:0] == 2'd0 || (cpu_addr[1:0] == 2'd2 && bflags[5])) gfxbank[1:0] <= cpu_dout[1:0];
                  else if (cpu_addr[1:0] != 2'd3) gfxbank[cpu_addr[1:0] + 2'd1] <= cpu_dout[0];
            2'd1: snd_9l[cpu_addr[2:0]] <= cpu_dout[0];
            2'd2: ctl_9n[cpu_addr[2:0]] <= cpu_dout[0];
            2'd3: pitch <= cpu_dout;
        endcase
    end
end

wire nmi_en = (bflags[0] ? ctl_9n[0] : ctl_9n[1]) & ~bflags7[4];
wire wdr    = (mem & ~cpu_rd_n & ((io_cs & io_sel == 2'd3) | fg_wd)) | (wr & hsk & (sdm ? cpu_addr[15:11] == 5'b01110 : cpu_addr == 16'h7000));

always @(posedge clk) begin
    if (!nmi_en)                  cpu_nmi_n <= 1'b1;
    else if (ce6 & rising_vblank) cpu_nmi_n <= 1'b0;

    if (reset | ~bflags7[4] | (~cpu_iorq_n & ~cpu_m1_n)) cpu_int_n <= 1'b1;
    else if (ce6 & rising_vblank)                       cpu_int_n <= 1'b0;

    if (reset | ~s26 | s26_intack | (~nmi_en & ~s26_vb)) s26_int <= 1'b0;
    else if (ce6 & rising_vblank)                        s26_int <= 1'b1;

    if (reset | wdr | pause)      watchdog <= 4'd0;
    else if (ce6 & rising_vblank) watchdog <= watchdog_reset ? 4'd0 : watchdog + 4'd1;
end

wire [7:0] ram_q, vram_q, obj_q;

wire [16:0] hs_dec = decode(hs_address);
wire [11:0] hs_idx = hs_dec[11:0];
wire        hs_vid = hs_dec[14];
wire  [7:0] hs_ram_q;
assign      hs_data_out = hs_vid ? vram_q : hs_ram_q;

function [2:0] fa_lut(input [4:0] fi);
    case (fi)
        5'd0:  fa_lut = 3'd0; 5'd1:  fa_lut = 3'd2; 5'd2:  fa_lut = 3'd4; 5'd3:  fa_lut = 3'd6;
        5'd4:  fa_lut = 3'd7; 5'd5:  fa_lut = 3'd3; 5'd6:  fa_lut = 3'd5; 5'd7:  fa_lut = 3'd1;
        5'd8:  fa_lut = 3'd6; 5'd9:  fa_lut = 3'd0; 5'd10: fa_lut = 3'd2; 5'd11: fa_lut = 3'd4;
        5'd12: fa_lut = 3'd1; 5'd13: fa_lut = 3'd5; 5'd14: fa_lut = 3'd3; 5'd15: fa_lut = 3'd0;
        5'd16: fa_lut = 3'd2; 5'd17: fa_lut = 3'd4; 5'd18: fa_lut = 3'd6; 5'd19: fa_lut = 3'd3;
        5'd20: fa_lut = 3'd5; 5'd21: fa_lut = 3'd6; 5'd22: fa_lut = 3'd0; 5'd23: fa_lut = 3'd2;
        5'd24: fa_lut = 3'd4; 5'd25: fa_lut = 3'd1; 5'd26: fa_lut = 3'd1; 5'd27: fa_lut = 3'd5;
        5'd28: fa_lut = 3'd3; 5'd29: fa_lut = 3'd7; 5'd30: fa_lut = 3'd7; default: fa_lut = 3'd7;
    endcase
endfunction

reg  cav_bank = 1'b1;
reg  cav_acc_d = 1'b0;
wire cav_acc = bflags8[5] & mem & cpu_addr[15] & ~(cpu_rd_n & cpu_wr_n);
always @(posedge clk) begin
    cav_acc_d <= cav_acc;
    if (reset) cav_bank <= 1'b1;
    else if (cav_acc & ~cav_acc_d) cav_bank <= ~cav_bank;
end

function [15:0] db_usr(input [13:0] ui);
    db_usr = {2'b10, ui[13:12], ui[4], ui[10:5], ui[3], ui[11], ui[2:0]};
endfunction
wire [15:0] db_a = cpu_addr[14:12] == 3'h1 ? {4'h5, cpu_addr[11:0]} :
                   cpu_addr[14:12] == 3'h5 ? {4'h6, cpu_addr[11:0]} :
                   cpu_addr[14:12] == 3'h6 ? db_usr({2'b01, cpu_addr[11:0]}) :
                   !cpu_addr[14]           ? db_usr(cpu_addr[13:0]) : {1'b0, cpu_addr[14:0]};
wire       db_dsw = cpu_addr[14:12] == 3'h1 || cpu_addr[14:12] == 3'h4 || cpu_addr[14:12] == 3'h5;

wire        gts3_hi = bflags11[1] & cpu_addr[15:11] == 5'b10000;
wire [15:0] fin_a = gfxbank[1:0] != 2'd3 ? {gfxbank[1:0], cpu_addr[13:0]} :
                    cpu_addr[13:12] == 2'd0 ? {4'hB, cpu_addr[11:0]} : 16'hD000 + {2'b00, cpu_addr[13:0]};
assign rom_a = db ? db_a :
                    fin && cpu_addr[15:14] == 2'b00 ? fin_a :
                    tnv_rom ? {4'h4, cpu_addr[11:0]} :
                    bflags8[0] ? {cpu_addr[15:4], cpu_addr[2], cpu_addr[0], cpu_addr[3], cpu_addr[1]} :
                    bflags9[3] ? {cpu_addr[15:5], cpu_addr[1], cpu_addr[0], cpu_addr[3], cpu_addr[4], cpu_addr[2]} :
                    bflags9[5] ? {cpu_addr[15] & ~gts3_hi, cpu_addr[14] | gts3_hi | (bflags10[5] & ~cpu_m1_n & cpu_addr[15:12] == 4'h0),
                                  cpu_addr[13:8], ~cpu_addr[7:0]} :
                    bflags11[0] && cpu_addr[15:11] == 5'b00100 ? {1'b0, gfxbank[0], ~gfxbank[0], 2'b00, cpu_addr[10:0]} :
                    bflags10[4] && cpu_addr < 16'h5800 ? {1'b0, ckx_blk(cpu_addr[14:8]), cpu_addr[7:0]} :
                    bflags8[5] && cav_bank && cpu_addr[15:13] == 3'b000 ? {3'b010, cpu_addr[12:0]} :
                    bflags6[2] && !cpu_addr[12] && cpu_addr[15:13] < 3'd3 ? {cpu_addr[15:10], ~cpu_addr[9:0]} :
                    bflags4[2] && !cpu_addr[15] ? {1'b0, fa_lut(cpu_addr[14:10]), cpu_addr[11:10], cpu_addr[9:0]} :
                    bflags4[1] && cpu_addr[15:13] == 3'b001 ? {cpu_addr[15:13], cpu_addr[12] ^ ctl_9n[2], cpu_addr[11:0]} :
                    cpu_addr;

reg  [8:0] rc_h = 9'd0;
reg  [7:0] rc_v = 8'd0;
wire [7:0] rc_q;
wire       rc_vr = rc && cpu_addr[15:11] == 5'b01000;
always @(posedge clk) begin
    if (wr && rc && cpu_addr[15:2] == 14'h1200) begin
        if (cpu_addr[1:0] == 2'd0) rc_h[7:0] <= cpu_dout;
        if (cpu_addr[1:0] == 2'd1) rc_h[8]   <= cpu_dout[0];
        if (cpu_addr[1:0] == 2'd2) rc_v      <= cpu_dout;
    end
end

reg  [7:0] db_bg = 8'd0, db_split = 8'd0;
always @(posedge clk) begin
    if (reset) begin db_bg <= 8'd0; db_split <= 8'd0; end
    else if (wr && db && cpu_addr == 16'h8000) db_bg    <= cpu_dout;
    else if (wr && db && cpu_addr == 16'h8001) db_split <= cpu_dout;
end

reg  [3:0] hm_mode = 4'd0;
reg  [2:0] hm_cnt  = 3'd0;
reg  [1:0] hm_bank = 2'd0;
reg        hm_bit  = 1'b0, hm_clk = 1'b0;
reg  [7:0] hm_cb   = 8'd0;
always @(posedge clk) begin
    if (reset) begin
        hm_mode <= 4'd0;
        hm_cnt  <= 3'd0;
        hm_bank <= 2'd0;
        hm_bit  <= 1'b0;
        hm_clk  <= 1'b0;
        hm_cb   <= 8'd0;
    end
    else if (wr && hm) begin
        if (cpu_addr == 16'h5000) hm_cb  <= cpu_dout;
        if (cpu_addr == 16'h5802) hm_bit <= cpu_dout[0];
        if (cpu_addr == 16'h5803) begin hm_mode <= 4'd0; hm_cnt <= 3'd0; end
        if (cpu_addr == 16'h5801) begin : hm_shift
            reg [3:0] m;
            reg [2:0] c;
            m = hm_mode;
            c = hm_cnt;
            if (cpu_dout[0] && !hm_clk) begin m = {hm_bit, hm_mode[3:1]}; c = c + 3'd1; end
            hm_clk <= cpu_dout[0];
            if (c == 3'd4) begin
                hm_bank <= m == 4'h9 ? 2'd1 : m == 4'hA ? 2'd2 : 2'd0;
                m = 4'd0;
                c = 3'd0;
            end
            hm_mode <= m;
            hm_cnt  <= c;
        end
    end
end

function [7:0] hm_decrypt(input [7:0] hx, input [1:0] bank, input op);
    case ({bank, op})
        3'b001:  hm_decrypt = {hx[7], hx[0], hx[5], hx[2], hx[3], hx[4], hx[1], hx[6]};
        3'b000:  hm_decrypt = {hx[7], hx[6], hx[5], hx[0], hx[3], hx[4], hx[1], hx[2]};
        3'b011:  hm_decrypt = {hx[7], hx[0], hx[5], hx[6], hx[3], hx[2], hx[1], hx[4]};
        3'b010:  hm_decrypt = {hx[7], hx[4], hx[5], hx[0], hx[3], hx[6], hx[1], hx[2]};
        3'b101:  hm_decrypt = {hx[7], hx[2], hx[5], hx[6], hx[3], hx[0], hx[1], hx[4]};
        default: hm_decrypt = {hx[7], hx[2], hx[5], hx[4], hx[3], hx[0], hx[1], hx[6]};
    endcase
endfunction

function [6:0] ckx_blk(input [6:0] b);
    begin
        if (b == 7'h00)                   ckx_blk = 7'h50;
        else if (b < 7'h04)               ckx_blk = {3'b000, b[3:0] + 4'hC};
        else if (b == 7'h04)              ckx_blk = 7'h0C;
        else if (b < 7'h10)               ckx_blk = {3'b000, b[3:0] - 4'h4};
        else if (b < 7'h50)               ckx_blk = {b[6:4], b[3:0] + 4'h4};
        else                              ckx_blk = b[1:0] == 2'b00 ? 7'h00 : {5'b10100, b[1:0]};
    end
endfunction

assign pr_i[0].a_addr = {4'd0, ram_idx};
assign pr_i[0].a_d    = cpu_dout;
assign pr_i[0].a_we   = wr & ram_cs;
assign pr_i[0].b_addr = {4'd0, hs_idx};
assign pr_i[0].b_d    = hs_data_in;
assign pr_i[0].b_we   = hs_write & ~hs_vid;
assign ram_q    = pr_o[0].a_q;
assign hs_ram_q = pr_o[0].b_q;
assign pr_i[8:7] = '0;

function [7:0] msh_tab(input [7:0] k);
    case (k)
        8'h00: msh_tab = 8'h40; 8'h01: msh_tab = 8'h41; 8'h02: msh_tab = 8'h44; 8'h03: msh_tab = 8'h15; 8'h04: msh_tab = 8'h05; 8'h05: msh_tab = 8'h51;
        8'h06: msh_tab = 8'h54; 8'h07: msh_tab = 8'h55; 8'h08: msh_tab = 8'h50; 8'h09: msh_tab = 8'h00; 8'h0A: msh_tab = 8'h01; 8'h0B: msh_tab = 8'h04;
        8'h0C: msh_tab = 8'hFF; 8'h0D: msh_tab = 8'h10; 8'h0E: msh_tab = 8'h11; 8'h0F: msh_tab = 8'h14; 8'h10: msh_tab = 8'h45; 8'h11: msh_tab = 8'h51;
        8'h12: msh_tab = 8'h55; 8'h13: msh_tab = 8'h44; 8'h14: msh_tab = 8'h40; 8'h15: msh_tab = 8'h11; 8'h16: msh_tab = 8'h05; 8'h17: msh_tab = 8'h41;
        8'h18: msh_tab = 8'h10; 8'h19: msh_tab = 8'h14; 8'h1A: msh_tab = 8'h54; 8'h1B: msh_tab = 8'h50; 8'h1C: msh_tab = 8'h15; 8'h1D: msh_tab = 8'h04;
        8'h1E: msh_tab = 8'h00; 8'h1F: msh_tab = 8'h01; 8'h20: msh_tab = 8'h11; 8'h21: msh_tab = 8'h14; 8'h22: msh_tab = 8'h10; 8'h23: msh_tab = 8'h00;
        8'h24: msh_tab = 8'h44; 8'h25: msh_tab = 8'h05; 8'h26: msh_tab = 8'hFF; 8'h27: msh_tab = 8'h04; 8'h28: msh_tab = 8'h45; 8'h29: msh_tab = 8'h15;
        8'h2A: msh_tab = 8'h55; 8'h2B: msh_tab = 8'h50; 8'h2C: msh_tab = 8'hFF; 8'h2D: msh_tab = 8'h01; 8'h2E: msh_tab = 8'h54; 8'h2F: msh_tab = 8'h51;
        8'h30: msh_tab = 8'h14; 8'h31: msh_tab = 8'h01; 8'h32: msh_tab = 8'h11; 8'h33: msh_tab = 8'h10; 8'h34: msh_tab = 8'h50; 8'h35: msh_tab = 8'h15;
        8'h36: msh_tab = 8'h00; 8'h37: msh_tab = 8'h40; 8'h38: msh_tab = 8'h04; 8'h39: msh_tab = 8'h51; 8'h3A: msh_tab = 8'h45; 8'h3B: msh_tab = 8'h05;
        8'h3C: msh_tab = 8'h55; 8'h3D: msh_tab = 8'h54; 8'h3E: msh_tab = 8'hFF; 8'h3F: msh_tab = 8'h44; 8'h40: msh_tab = 8'h04; 8'h41: msh_tab = 8'h10;
        8'h42: msh_tab = 8'hFF; 8'h43: msh_tab = 8'h40; 8'h44: msh_tab = 8'h15; 8'h45: msh_tab = 8'h41; 8'h46: msh_tab = 8'h50; 8'h47: msh_tab = 8'h50;
        8'h48: msh_tab = 8'h11; 8'h49: msh_tab = 8'hFF; 8'h4A: msh_tab = 8'h14; 8'h4B: msh_tab = 8'h00; 8'h4C: msh_tab = 8'h51; 8'h4D: msh_tab = 8'h45;
        8'h4E: msh_tab = 8'h55; 8'h4F: msh_tab = 8'h01; 8'h50: msh_tab = 8'h44; 8'h51: msh_tab = 8'h45; 8'h52: msh_tab = 8'h00; 8'h53: msh_tab = 8'h51;
        8'h54: msh_tab = 8'hFF; 8'h55: msh_tab = 8'hFF; 8'h56: msh_tab = 8'h15; 8'h57: msh_tab = 8'h11; 8'h58: msh_tab = 8'h01; 8'h59: msh_tab = 8'h10;
        8'h5A: msh_tab = 8'h04; 8'h5B: msh_tab = 8'h55; 8'h5C: msh_tab = 8'h05; 8'h5D: msh_tab = 8'h40; 8'h5E: msh_tab = 8'h50; 8'h5F: msh_tab = 8'h41;
        8'h60: msh_tab = 8'h51; 8'h61: msh_tab = 8'h00; 8'h62: msh_tab = 8'h01; 8'h63: msh_tab = 8'h05; 8'h64: msh_tab = 8'h04; 8'h65: msh_tab = 8'h55;
        8'h66: msh_tab = 8'h54; 8'h67: msh_tab = 8'h50; 8'h68: msh_tab = 8'h41; 8'h69: msh_tab = 8'hFF; 8'h6A: msh_tab = 8'h11; 8'h6B: msh_tab = 8'h15;
        8'h6C: msh_tab = 8'h14; 8'h6D: msh_tab = 8'h10; 8'h6E: msh_tab = 8'h44; 8'h6F: msh_tab = 8'h40; 8'h70: msh_tab = 8'h05; 8'h71: msh_tab = 8'h04;
        8'h72: msh_tab = 8'h51; 8'h73: msh_tab = 8'h01; 8'h74: msh_tab = 8'hFF; 8'h75: msh_tab = 8'hFF; 8'h76: msh_tab = 8'h55; 8'h77: msh_tab = 8'hFF;
        8'h78: msh_tab = 8'h00; 8'h79: msh_tab = 8'h50; 8'h7A: msh_tab = 8'h15; 8'h7B: msh_tab = 8'h14; 8'h7C: msh_tab = 8'h44; 8'h7D: msh_tab = 8'h41;
        8'h7E: msh_tab = 8'h40; 8'h7F: msh_tab = 8'h54; 8'h80: msh_tab = 8'h41; 8'h81: msh_tab = 8'h54; 8'h82: msh_tab = 8'h51; 8'h83: msh_tab = 8'h14;
        8'h84: msh_tab = 8'h05; 8'h85: msh_tab = 8'h10; 8'h86: msh_tab = 8'h01; 8'h87: msh_tab = 8'h55; 8'h88: msh_tab = 8'h44; 8'h89: msh_tab = 8'h11;
        8'h8A: msh_tab = 8'h00; 8'h8B: msh_tab = 8'h50; 8'h8C: msh_tab = 8'h15; 8'h8D: msh_tab = 8'h40; 8'h8E: msh_tab = 8'h04; 8'h8F: msh_tab = 8'h45;
        8'h90: msh_tab = 8'h50; 8'h91: msh_tab = 8'h11; 8'h92: msh_tab = 8'h40; 8'h93: msh_tab = 8'h55; 8'h94: msh_tab = 8'h51; 8'h95: msh_tab = 8'h14;
        8'h96: msh_tab = 8'h45; 8'h97: msh_tab = 8'h04; 8'h98: msh_tab = 8'h54; 8'h99: msh_tab = 8'h15; 8'h9A: msh_tab = 8'h10; 8'h9B: msh_tab = 8'h05;
        8'h9C: msh_tab = 8'h44; 8'h9D: msh_tab = 8'h01; 8'h9E: msh_tab = 8'h00; 8'h9F: msh_tab = 8'h41; 8'hA0: msh_tab = 8'h44; 8'hA1: msh_tab = 8'h11;
        8'hA2: msh_tab = 8'h00; 8'hA3: msh_tab = 8'h50; 8'hA4: msh_tab = 8'h41; 8'hA5: msh_tab = 8'h54; 8'hA6: msh_tab = 8'h04; 8'hA7: msh_tab = 8'h14;
        8'hA8: msh_tab = 8'h15; 8'hA9: msh_tab = 8'h40; 8'hAA: msh_tab = 8'h51; 8'hAB: msh_tab = 8'h55; 8'hAC: msh_tab = 8'h05; 8'hAD: msh_tab = 8'h10;
        8'hAE: msh_tab = 8'h01; 8'hAF: msh_tab = 8'h45; 8'hB0: msh_tab = 8'h10; 8'hB1: msh_tab = 8'h50; 8'hB2: msh_tab = 8'h54; 8'hB3: msh_tab = 8'h55;
        8'hB4: msh_tab = 8'h01; 8'hB5: msh_tab = 8'h44; 8'hB6: msh_tab = 8'h40; 8'hB7: msh_tab = 8'h04; 8'hB8: msh_tab = 8'h14; 8'hB9: msh_tab = 8'h11;
        8'hBA: msh_tab = 8'h00; 8'hBB: msh_tab = 8'h41; 8'hBC: msh_tab = 8'h45; 8'hBD: msh_tab = 8'h15; 8'hBE: msh_tab = 8'h51; 8'hBF: msh_tab = 8'h05;
        8'hC0: msh_tab = 8'h14; 8'hC1: msh_tab = 8'h41; 8'hC2: msh_tab = 8'h01; 8'hC3: msh_tab = 8'h44; 8'hC4: msh_tab = 8'h04; 8'hC5: msh_tab = 8'h50;
        8'hC6: msh_tab = 8'h51; 8'hC7: msh_tab = 8'h45; 8'hC8: msh_tab = 8'h11; 8'hC9: msh_tab = 8'h40; 8'hCA: msh_tab = 8'h54; 8'hCB: msh_tab = 8'h15;
        8'hCC: msh_tab = 8'h10; 8'hCD: msh_tab = 8'h00; 8'hCE: msh_tab = 8'h55; 8'hCF: msh_tab = 8'h05; 8'hD0: msh_tab = 8'h01; 8'hD1: msh_tab = 8'h05;
        8'hD2: msh_tab = 8'h41; 8'hD3: msh_tab = 8'h45; 8'hD4: msh_tab = 8'h54; 8'hD5: msh_tab = 8'h50; 8'hD6: msh_tab = 8'h55; 8'hD7: msh_tab = 8'h10;
        8'hD8: msh_tab = 8'h11; 8'hD9: msh_tab = 8'h15; 8'hDA: msh_tab = 8'h51; 8'hDB: msh_tab = 8'h14; 8'hDC: msh_tab = 8'h44; 8'hDD: msh_tab = 8'h40;
        8'hDE: msh_tab = 8'h04; 8'hDF: msh_tab = 8'h00; 8'hE0: msh_tab = 8'h05; 8'hE1: msh_tab = 8'h55; 8'hE2: msh_tab = 8'h00; 8'hE3: msh_tab = 8'h50;
        8'hE4: msh_tab = 8'h11; 8'hE5: msh_tab = 8'h40; 8'hE6: msh_tab = 8'h54; 8'hE7: msh_tab = 8'h14; 8'hE8: msh_tab = 8'h45; 8'hE9: msh_tab = 8'h51;
        8'hEA: msh_tab = 8'h10; 8'hEB: msh_tab = 8'h04; 8'hEC: msh_tab = 8'h44; 8'hED: msh_tab = 8'h01; 8'hEE: msh_tab = 8'h41; 8'hEF: msh_tab = 8'h15;
        8'hF0: msh_tab = 8'h55; 8'hF1: msh_tab = 8'h50; 8'hF2: msh_tab = 8'h15; 8'hF3: msh_tab = 8'h10; 8'hF4: msh_tab = 8'h01; 8'hF5: msh_tab = 8'h04;
        8'hF6: msh_tab = 8'h41; 8'hF7: msh_tab = 8'h44; 8'hF8: msh_tab = 8'h45; 8'hF9: msh_tab = 8'h40; 8'hFA: msh_tab = 8'h05; 8'hFB: msh_tab = 8'h00;
        8'hFC: msh_tab = 8'h11; 8'hFD: msh_tab = 8'h14; 8'hFE: msh_tab = 8'h51; 8'hFF: msh_tab = 8'h54;
        default: msh_tab = 8'h00;
    endcase
endfunction
function [7:0] mc_decrypt(input [7:0] d, input a0);
    reg [7:0] r;
    begin
        r = d ^ {1'b0, d[1], 3'b000, d[5], 2'b00};
        mc_decrypt = a0 ? r : {r[7], r[2], r[5:3], r[6], r[1:0]};
    end
endfunction

reg [7:0] mmk_x;
wire       decrypt = cpu_addr[15:14] == 2'b00 && (bflags[3] || (bflags[4] && !cpu_m1_n));
wire       hus_rom = cpu_addr[15:14] == 2'b00;
wire [7:0] ad_x    = rom_q ^ 8'h35;
wire [7:0] rom_d   = db && db_dsw ? {rom_q[7:5], rom_q[1], rom_q[3], rom_q[2], rom_q[4], rom_q[0]} :
                     ad ? {ad_x[6], ad_x[2], ad_x[5], ad_x[1], ad_x[7], ad_x[3], ad_x[4], ad_x[0]} :
                     fin ? rom_q ^ cpu_addr[7:0] :
                     hm && cpu_addr[15:13] == 3'b100 ? hm_decrypt(rom_q, hm_bank, ~cpu_m1_n) :
                     msh && !cpu_m1_n && !cpu_addr[15] ? (rom_q & 8'hAA) | msh_tab({bflags11[4], rom_q[7], rom_q[1], cpu_addr[0],
                                                                    rom_q[6], rom_q[4], rom_q[2], rom_q[0]}) :
                     bflags8[4] && cpu_addr == 16'h2EF9 ? 8'hC9 : decrypt ? mc_decrypt(rom_q, cpu_addr[0]) : bflags3[3] ? cm_decrypt(rom_q, cpu_addr[2:0]) :
                     bflags6[5] && hus_rom ? hus_decrypt(rom_q, cpu_addr[7:0]) :
                     bflags6[6] && hus_rom ? bil_decrypt(rom_q, cpu_addr[7:0]) :
                     bflags9[0] && cpu_addr < 16'h6000 ? sce_decrypt(rom_q, cpu_addr[7:0]) :
                     bflags10[0] ? vic_decrypt(rom_q, cpu_addr[7:0]) :
                     bflags10[3] && cpu_addr < 16'h4000 ? rom_q ^ mmk_x :
                     bflags10[2] && cpu_addr < 16'h4000 ? crz_decrypt(rom_q, cpu_addr[0]) :
                     bflags9[1] && cpu_addr < 16'h1000 ? rom_q ^ (cpu_addr[9] ? (cpu_addr[7] ? 8'h10 : 8'h12) :
                                                                               (cpu_addr[7] ? 8'h82 : 8'h92)) : rom_q;

always @(*) begin
    case ({cpu_addr[2:0], rom_q[7], rom_q[2:0]})
        7'h00: mmk_x = 8'h03;
        7'h01: mmk_x = 8'h03;
        7'h02: mmk_x = 8'h05;
        7'h03: mmk_x = 8'h07;
        7'h04: mmk_x = 8'h85;
        7'h06: mmk_x = 8'h85;
        7'h07: mmk_x = 8'h85;
        7'h08: mmk_x = 8'h80;
        7'h09: mmk_x = 8'h80;
        7'h0A: mmk_x = 8'h06;
        7'h0B: mmk_x = 8'h03;
        7'h0C: mmk_x = 8'h03;
        7'h0F: mmk_x = 8'h81;
        7'h10: mmk_x = 8'h83;
        7'h11: mmk_x = 8'h87;
        7'h12: mmk_x = 8'h03;
        7'h13: mmk_x = 8'h87;
        7'h14: mmk_x = 8'h06;
        7'h16: mmk_x = 8'h06;
        7'h17: mmk_x = 8'h04;
        7'h18: mmk_x = 8'h02;
        7'h1A: mmk_x = 8'h84;
        7'h1B: mmk_x = 8'h84;
        7'h1C: mmk_x = 8'h04;
        7'h1E: mmk_x = 8'h01;
        7'h1F: mmk_x = 8'h83;
        7'h20: mmk_x = 8'h82;
        7'h21: mmk_x = 8'h82;
        7'h22: mmk_x = 8'h84;
        7'h23: mmk_x = 8'h02;
        7'h24: mmk_x = 8'h04;
        7'h27: mmk_x = 8'h03;
        7'h28: mmk_x = 8'h82;
        7'h2A: mmk_x = 8'h06;
        7'h2B: mmk_x = 8'h80;
        7'h2C: mmk_x = 8'h03;
        7'h2E: mmk_x = 8'h81;
        7'h2F: mmk_x = 8'h07;
        7'h30: mmk_x = 8'h06;
        7'h31: mmk_x = 8'h06;
        7'h32: mmk_x = 8'h82;
        7'h33: mmk_x = 8'h81;
        7'h34: mmk_x = 8'h85;
        7'h36: mmk_x = 8'h04;
        7'h37: mmk_x = 8'h07;
        7'h38: mmk_x = 8'h81;
        7'h39: mmk_x = 8'h05;
        7'h3A: mmk_x = 8'h04;
        7'h3C: mmk_x = 8'h03;
        7'h3E: mmk_x = 8'h82;
        7'h3F: mmk_x = 8'h84;
        7'h40: mmk_x = 8'h07;
        7'h41: mmk_x = 8'h07;
        7'h42: mmk_x = 8'h80;
        7'h43: mmk_x = 8'h07;
        7'h44: mmk_x = 8'h07;
        7'h46: mmk_x = 8'h85;
        7'h47: mmk_x = 8'h86;
        7'h49: mmk_x = 8'h07;
        7'h4A: mmk_x = 8'h06;
        7'h4B: mmk_x = 8'h04;
        7'h4C: mmk_x = 8'h85;
        7'h4E: mmk_x = 8'h86;
        7'h4F: mmk_x = 8'h85;
        7'h50: mmk_x = 8'h81;
        7'h51: mmk_x = 8'h83;
        7'h52: mmk_x = 8'h02;
        7'h53: mmk_x = 8'h02;
        7'h54: mmk_x = 8'h87;
        7'h56: mmk_x = 8'h86;
        7'h57: mmk_x = 8'h03;
        7'h58: mmk_x = 8'h04;
        7'h59: mmk_x = 8'h06;
        7'h5A: mmk_x = 8'h80;
        7'h5B: mmk_x = 8'h05;
        7'h5C: mmk_x = 8'h87;
        7'h5E: mmk_x = 8'h81;
        7'h5F: mmk_x = 8'h81;
        7'h60: mmk_x = 8'h01;
        7'h61: mmk_x = 8'h01;
        7'h63: mmk_x = 8'h07;
        7'h64: mmk_x = 8'h07;
        7'h66: mmk_x = 8'h01;
        7'h67: mmk_x = 8'h01;
        7'h68: mmk_x = 8'h07;
        7'h69: mmk_x = 8'h07;
        7'h6A: mmk_x = 8'h06;
        7'h6C: mmk_x = 8'h06;
        7'h6E: mmk_x = 8'h07;
        7'h6F: mmk_x = 8'h07;
        7'h70: mmk_x = 8'h80;
        7'h71: mmk_x = 8'h87;
        7'h72: mmk_x = 8'h81;
        7'h73: mmk_x = 8'h87;
        7'h74: mmk_x = 8'h83;
        7'h76: mmk_x = 8'h84;
        7'h77: mmk_x = 8'h01;
        7'h78: mmk_x = 8'h01;
        7'h79: mmk_x = 8'h86;
        7'h7A: mmk_x = 8'h86;
        7'h7B: mmk_x = 8'h80;
        7'h7C: mmk_x = 8'h86;
        7'h7E: mmk_x = 8'h86;
        7'h7F: mmk_x = 8'h86;
        default: mmk_x = 8'h00;
    endcase
end

function [7:0] vic_decrypt(input [7:0] d, input [7:0] a);
    reg [7:0] x;
    begin
        x = d ^ {a[7], a[2], 3'b000, a[5], 2'b00} ^ {4'b0000, a[0], 3'b000};
        vic_decrypt = {x[6], x[3], x[5], x[4], x[2], x[7], x[1], x[0]};
    end
endfunction

function [7:0] crz_decrypt(input [7:0] d, input a0);
    reg [7:0] m;
    begin
        case (d[5:3])
            3'd3, 3'd6: m = 8'h18;
            default:    m = 8'h30;
        endcase
        if (!a0) case (d[5:3])
            3'd0, 3'd5, 3'd7: m = 8'h20;
            3'd1, 3'd3:       m = 8'h08;
            3'd2:             m = 8'h28;
            3'd4:             m = 8'h10;
            default:          m = 8'h18;
        endcase
        crz_decrypt = d ^ m;
    end
endfunction

function [7:0] sce_decrypt(input [7:0] d, input [7:0] a);
    reg [6:0] i;
    reg [7:0] x;
    begin
        i = a[6:0] ^ {7{a[7]}};
        x = d;
        if (i[0]) x = x ^ 8'h49;
        if (i[1]) x = x ^ 8'h21;
        if (i[2]) x = x ^ 8'h18;
        if (i[3]) x = x ^ 8'h12;
        if (i[4]) x = x ^ 8'h84;
        if (i[5]) x = x ^ 8'h24;
        if (i[6]) x = x ^ 8'h40;
        sce_decrypt = ~x;
    end
endfunction

reg [7:0] fin_dip;
always @(*) begin
    case (gfxbank[1:0])
        2'd0: fin_dip = {in3[3:2], 4'd0, in3[1:0]};
        2'd1: fin_dip = {dip4[7:6], dip4[5:3], 3'd0};
        2'd2: fin_dip = {in3[7:6], 4'd0, in3[5:4]};
        2'd3: fin_dip = {dip4[2:1], 5'd0, dip4[0]};
    endcase
end

reg [7:0] prot_q;
always @(*) begin
    case (cpu_addr[11:0])
        12'h114: prot_q = 8'h4F;
        12'h118: prot_q = 8'hD3;
        12'h214: prot_q = 8'hCF;
        12'h235: prot_q = 8'h02;
        default: prot_q = 8'hFF;
    endcase
end

reg [15:0] m1_pc = 16'd0;
always @(posedge clk) if (~cpu_m1_n & ~cpu_mreq_n) m1_pc <= cpu_addr;
wire [15:0] op_end = m1_pc + 16'd3;

wire       cm_prot = bflags3[4] && cpu_addr == 16'h3800;
wire       dg_prot = bflags3[5] && (cpu_addr == 16'h3000 || cpu_addr == 16'h3035);
reg  [7:0] cm_prot_q;
always @(*) begin
    case (op_end)
        16'h0F15: cm_prot_q = 8'hF5;
        16'h0F8F: cm_prot_q = 8'h7C;
        16'h10B3: cm_prot_q = 8'h7C;
        16'h10E0: cm_prot_q = 8'h00;
        16'h10F1: cm_prot_q = 8'hAA;
        16'h1402: cm_prot_q = 8'hAA;
        default:  cm_prot_q = 8'h00;
    endcase
end

function [7:0] cm_decrypt(input [7:0] d, input [2:0] a);
    reg [7:0] x;
    begin
        x = 8'd0;
        case (a)
            3'd0: x[0] = d[6];
            3'd1: x[1] = d[5];
            3'd2: begin x[2] = d[4]; x[1] = d[6]; end
            3'd3: begin x[4] = d[2]; x[0] = d[5]; end
            3'd4: begin x[6] = d[4]; x[5] = d[1]; end
            3'd5: begin x[6] = d[0]; x[5] = d[2]; end
            3'd6: x[2] = d[0];
            3'd7: x[4] = d[1];
        endcase
        cm_decrypt = d ^ x;
    end
endfunction

reg  [15:0] last_rd = 16'd0, prev_rd = 16'd0;
reg         mrd_d   = 1'b0;
wire        mrd     = mem & ~cpu_rd_n;
always @(posedge clk) begin
    mrd_d <= mrd;
    if (mrd & ~mrd_d) begin prev_rd <= last_rd; last_rd <= cpu_addr; end
end
wire [15:0] tp_pc  = last_rd + 16'd1;
wire [15:0] mr_pc  = prev_rd + 16'd1;

wire  [7:0] sbp1 = mr_pc == 16'h01DA ? 8'h80 : 8'h00;
wire  [7:0] sbp2 = mr_pc == 16'h01CA ? 8'h90 : 8'h00;

wire  [7:0] tp_pip = tp_pc == 16'h015A ? 8'hFF : tp_pc == 16'h0886 ? 8'h05 : 8'h00;
wire  [7:0] tp_pap = tp_pc == 16'h015D ? 8'h04 : 8'h00;

wire [7:0] ppi0_pc;
wire       mw_sel = ~ppi0_pc[4];
reg  [3:0] mw_cnt[2];
reg  [1:0] mw_dir = 2'b00;
logic [1:0][7:0] mw_last = '0, mw_d, mw_mag;
assign mw_d[0]   = dial1 - mw_last[0];
assign mw_d[1]   = dial2 - mw_last[1];
assign mw_mag[0] = mw_d[0][7] ? 8'd0 - mw_d[0] : mw_d[0];
assign mw_mag[1] = mw_d[1][7] ? 8'd0 - mw_d[1] : mw_d[1];
always @(posedge clk) begin
    mw_last <= {dial2, dial1};
    for (int p = 0; p < 2; p++)
        if (reset) begin mw_cnt[p] <= 4'd0; mw_dir[p] <= 1'b0; end
        else if (mw_d[p] != 8'd0) begin mw_cnt[p] <= mw_cnt[p] + mw_mag[p][3:0]; mw_dir[p] <= ~mw_d[p][7]; end
end

wire [7:0] ppi0_q, ppi1_q, ppi1_pa, ppi1_pb;
wire       ppi0_sel = fg_ppi & (fg ? cpu_addr[13] : ff ? cpu_addr[12] : sc | fa | hb | mr | tp | hm ? cpu_addr[8] : tu ? ~cpu_addr[11] :
                                ts ? cpu_addr[15:13] == 3'b101 : st2 | mdk | ck2 ? ~cpu_addr[11] : aeu ? cpu_addr[8] : aeg ? cpu_addr[15] :
                                cpu_addr[13:11] == 3'b011);
wire       ppi1_sel = fg_ppi & (fg ? cpu_addr[12] : ff ? cpu_addr[13] : sc | fa | hb | mr | tp | hm ? cpu_addr[9] : tu ?  cpu_addr[11] :
                                ts ? cpu_addr[15:13] == 3'b110 : st2 | mdk | ck2 ?  cpu_addr[11] : aeu ? ~cpu_addr[8] : aeg ? ~cpu_addr[15] :
                                cpu_addr[13:11] == 3'b100);
wire [1:0] ppi_a    = fg ? cpu_addr[2:1] : ff ? cpu_addr[4:3] : tu ? cpu_addr[5:4] : mr ? {cpu_addr[3], cpu_addr[1]} :
                      st2 && !bflags6[0] ? cpu_addr[3:2] : cpu_addr[1:0];
// Frogger (AM): the PPI data bus is wired bit-reversed (both directions)
wire [7:0] ppi_q0   = (ppi0_sel ? ppi0_q : 8'hFF) & (ppi1_sel ? ppi1_q : 8'hFF);
wire [7:0] ppi_q    = fa ? {ppi_q0[0], ppi_q0[1], ppi_q0[2], ppi_q0[3], ppi_q0[4], ppi_q0[5], ppi_q0[6], ppi_q0[7]} : ppi_q0;
wire [7:0] ppi_din  = fa ? {cpu_dout[0], cpu_dout[1], cpu_dout[2], cpu_dout[3], cpu_dout[4], cpu_dout[5], cpu_dout[6], cpu_dout[7]} : cpu_dout;

wire       prot     = bflags5[3];
wire [7:0] ppi1_pc;
reg        pc_we_d  = 1'b0;
reg [11:0] prot_st  = 12'd0;
reg  [7:0] prot_res = 8'd0;
always @(posedge clk) begin
    pc_we_d <= ppi1_pc_we;
    if (reset) begin
        prot_st  <= 12'd0;
        prot_res <= 8'd0;
    end
    else if (pc_we_d && prot) begin : prot_step
        reg [11:0] st;
        reg  [3:0] n1, n2;
        st = {prot_st[7:0], ppi1_pc[3:0]};
        n1 = st[11:8];
        n2 = st[7:4];
        prot_st <= st;
        case (st[3:0])
            4'h6: prot_res <= prot_res ^ 8'h80;
            4'h9: prot_res <= {n1 == 4'hF ? 4'hF : n1 + 4'd1, 4'h0};
            4'hA: prot_res <= 8'h00;
            4'hB: prot_res <= {n2 > n1 ? n2 - n1 : 4'h0, 4'h0};
            4'hF: prot_res <= {n1 > n2 ? n1 - n2 : 4'h0, 4'h0};
            default: ;
        endcase
    end
end
wire [7:0] in2_k = prot ? {~prot_res[7], in2[6], ~prot_res[7], in2[4:0]} : in2;

function [3:0] scp_cnt(input [15:0] st);
    reg [15:0] m;
    begin
        m = st & 16'hCE29;
        scp_cnt = {3'd0, m[0]} + {3'd0, m[3]} + {3'd0, m[5]} + {3'd0, m[9]} + {3'd0, m[10]} + {3'd0, m[11]} +
                  {3'd0, m[14]} + {3'd0, m[15]};
    end
endfunction
reg  [15:0] scp_st = 16'd0;
wire  [3:0] scp_n  = scp_cnt(scp_st);
wire [15:0] scp_r  = ppi1_pc[5] ? scp_st : 16'd0;
wire  [3:0] scp_nr = scp_cnt(scp_r);
always @(posedge clk) begin
    if (reset) scp_st <= 16'd0;
    else if (pc_we_d && scp) scp_st <= ppi1_pc[4] ? scp_r : {scp_r[14:0], ~scp_nr[0]};
end

assign i8255_0_i.reset   = reset;
assign i8255_0_i.cs      = 1'b1;
assign i8255_0_i.rd      = mrd & ppi0_sel;
assign i8255_0_i.wr      = wr & ppi0_sel;
assign i8255_0_i.a       = ppi_a;
assign i8255_0_i.din     = ppi_din;
assign i8255_0_i.pa_in   = bflags11[2] ? {in0[7:5], mw_dir[mw_sel], mw_cnt[mw_sel]} : in0;
assign i8255_0_i.pb_in   = in1;
assign i8255_0_i.pc_in   = in2_k;
assign i8255_0_i.stb_a_n = 1'b1;
assign i8255_0_i.ack_a_n = 1'b1;
assign i8255_0_i.pc2_n   = 1'b1;
assign ppi0_q  = i8255_0_o.dout;
assign ppi0_pc = i8255_0_o.pc_out;

assign i8255_1_i.reset   = reset;
assign i8255_1_i.cs      = 1'b1;
assign i8255_1_i.rd      = mrd & ppi1_sel;
assign i8255_1_i.wr      = wr & ppi1_sel;
assign i8255_1_i.a       = ppi_a;
assign i8255_1_i.din     = ppi_din;
assign i8255_1_i.pa_in   = 8'hFF;
assign i8255_1_i.pb_in   = 8'hFF;
assign i8255_1_i.pc_in   = scp ? {4'd0, scp_n} : prot ? prot_res : bflags6[1] ? 8'hFC : bflags8[2] ? 8'h00 : in3;
assign i8255_1_i.stb_a_n = 1'b1;
assign i8255_1_i.ack_a_n = 1'b1;
assign i8255_1_i.pc2_n   = 1'b1;
assign ppi1_q  = i8255_1_o.dout;
assign ppi1_pa = i8255_1_o.pa_out;
assign ppi1_pb = i8255_1_o.pb_out;
assign ppi1_pc = i8255_1_o.pc_out;

wire [7:0] ay_dout, ay2_dout;

reg  [7:0] hb6_ctl = 8'd0;
always @(posedge clk) if (reset) hb6_ctl <= 8'd0; else if (wr && (hb6 || ami) && cpu_addr == 16'h5000) hb6_ctl <= cpu_dout;
wire       snd_cmd_we = fmc ? wr && cpu_addr[15:11] == 5'b10101 : hb6 ? wr && cpu_addr == 16'h4800 : ami ? wr && cpu_addr == 16'h4000 :
                        hsk ? wr && (sdm ? cpu_addr[15:12] == 4'h8 : cpu_addr == 16'h8000) : wr & ppi1_sel & ppi_a == 2'd0;
wire [7:0] snd_ctl    = hsk || fmc ? 8'h00 : (hb6 || ami ? hb6_ctl : ppi1_pb) & ~{3'b000, bflags8[3], 4'b0000};
wire       snd_irq    = (wr & hsk & (sdm ? cpu_addr[15:12] == 4'h9 : cpu_addr == 16'h9000)) | (wr & fmc & cpu_addr[15:11] == 5'b10110 & cpu_addr[2:0] == 3'd1);

function [7:0] hus_decrypt(input [7:0] d, input [7:0] a);
    reg [7:0] m;
    begin
        m = 8'hFF;
        if (a[0] ^ a[1]) m = m ^ 8'h01;
        if (a[3] ^ a[6]) m = m ^ 8'h02;
        if (a[4] ^ a[5]) m = m ^ 8'h04;
        if (a[0] ^ a[2]) m = m ^ 8'h08;
        if (a[2] ^ a[3]) m = m ^ 8'h10;
        if (a[1] ^ a[5]) m = m ^ 8'h20;
        if (a[0] ^ a[7]) m = m ^ 8'h40;
        if (a[4] ^ a[6]) m = m ^ 8'h80;
        hus_decrypt = d ^ m;
    end
endfunction

function [7:0] bil_decrypt(input [7:0] d, input [7:0] a);
    reg [7:0] m, v;
    begin
        m = 8'h55;
        if (a[2] ^ (a[3] & a[6]))   m = m ^ 8'h01;
        if (a[4] ^ (a[5] & a[7]))   m = m ^ 8'h02;
        if (a[0] ^ (a[7] & ~a[3]))  m = m ^ 8'h04;
        if (a[3] ^ (~a[0] & a[2]))  m = m ^ 8'h08;
        if (a[5] ^ (~a[4] & a[1]))  m = m ^ 8'h10;
        if (a[6] ^ (~a[2] & ~a[5])) m = m ^ 8'h20;
        if (a[1] ^ (~a[6] & ~a[4])) m = m ^ 8'h40;
        if (a[7] ^ (~a[1] & a[0]))  m = m ^ 8'h80;
        v = d ^ m;
        bil_decrypt = {v[6], v[1], v[2], v[5], v[4], v[3], v[0], v[7]};
    end
endfunction
reg        msh_trig = 1'b0, msh_cs = 1'b0;
reg  [7:0] msh_rate = 8'd0;
reg  [4:0] msh_vol  = 5'd0;
always @(posedge clk) begin
    if (reset) begin
        msh_trig <= 1'b0;
        msh_cs   <= 1'b0;
        msh_rate <= 8'd0;
        msh_vol  <= 5'd0;
    end
    else if (wr && msh) begin
        if (cpu_addr == 16'hA004) msh_trig <= cpu_dout != 8'd0;
        if (cpu_addr == 16'hA007) msh_cs   <= cpu_dout[0];
        if (cpu_addr == 16'hA800) msh_rate <= cpu_dout;
        if (cpu_addr == 16'hB000) msh_vol  <= cpu_dout[4:0];
    end
end

reg  [7:0] kb_latch = 8'hF0;
reg [16:0] kb_noise = 17'h1FFFF;
always @(posedge clk) begin
    if (reset) kb_latch <= 8'hF0;
    else if (wr && kb && cpu_addr[15:11] == 5'b10110 && cpu_addr[2:0] == 3'd2) kb_latch <= {6'b111100, cpu_dout[0], ctl_9n[0]};
    if (ce6) kb_noise <= {kb_noise[15:0], kb_noise[16] ^ kb_noise[13]};
end

wire       io_rd = ~cpu_iorq_n & cpu_m1_n & ~cpu_rd_n;

wire       fa_cs = bflags4[3] && mem && cpu_addr[15:4] == 12'h880;

always @(*) begin
    cpu_din = 8'hFF;
    if (io_rd) cpu_din = msh ? (cpu_addr[3:0] == 4'hC && !msh_cs ? ay_dout : 8'hFF) :
                         bflags2[2] && cpu_addr[7:0] == 8'h02 ? ay_dout :
                         bflags8[6] && cpu_addr[7:0] == 8'h01 ? ay_dout :
                         bflags8[7] && cpu_addr[7:0] == 8'h02 ? tp_pip :
                         bflags8[7] && cpu_addr[7:0] == 8'h03 ? tp_pap : 8'hFF;
    else if (fg_ppi) cpu_din = ppi_q;
    else if (gs && cpu_addr == 16'h8102) cpu_din = sbp1;
    else if (gs && cpu_addr == 16'h8202) cpu_din = sbp2;
    else if (sb2 && cpu_addr[15:11] == 5'b01011) cpu_din = 8'h25;
    else if (sb2 && cpu_addr[15:3] == 13'h0C00) cpu_din = {7'd0, in0[cpu_addr[2:0]]};
    else if (sb2 && cpu_addr[15:3] == 13'h0D00) cpu_din = {7'd0, in1[cpu_addr[2:0]]};
    else if (sb2 && cpu_addr[15:3] == 13'h0F00) cpu_din = {7'd0, in2[cpu_addr[2:0]]};
    else if (tzb && cpu_addr == 16'h7000) cpu_din = in2;
    else if (bflags7[3] && cpu_addr == 16'h9008) cpu_din = 8'h03;
    else if (bflags7[3] && cpu_addr == 16'hB401) cpu_din = 8'h07;
    else if (ami && cpu_addr[15:2] == 14'h1000)
        cpu_din = cpu_addr[1:0] == 2'd0 ? in0 : cpu_addr[1:0] == 2'd1 ? in1 : cpu_addr[1:0] == 2'd2 ? in2 : in3;
    else if (hsk && (sdm ? cpu_addr[15:12] == 4'h8 : cpu_addr[15:2] == 14'h2000))
        cpu_din = cpu_addr[1:0] == 2'd0 ? in0 : cpu_addr[1:0] == 2'd1 ? in1 : cpu_addr[1:0] == 2'd2 ? in2 : in3;
    else if (hb6 && cpu_addr[15:2] == 14'h1200)
        cpu_din = cpu_addr[1:0] == 2'd0 ? in0 : cpu_addr[1:0] == 2'd1 ? in1 : cpu_addr[1:0] == 2'd3 ? in2 : 8'hFF;
    else if (sbh && cpu_addr[15:11] == 5'b10001) cpu_din = sb_p1;
    else if (tnv_rom) cpu_din = rom_d;
    else if (hm && cpu_addr == 16'h5000) cpu_din = hm_cb;
    else if (fa_cs) cpu_din = cpu_addr[3:0] == 4'h7 ? ay_dout : cpu_addr[3:0] == 4'hD ? ay2_dout : 8'hFF;
    else if (prot_cs) cpu_din = prot_q;
    else if (cm_prot) cpu_din = cm_prot_q;
    else if (dg_prot) cpu_din = cpu_addr[0] ? 8'h8C : 8'hAA;
    else if (rc_vr) cpu_din = rc_q;
    else if (rc && cpu_addr == 16'h5800) cpu_din = in3;
    else if (rc && cpu_addr == 16'h8800) cpu_din = dip4;
    else if (rom_cs) cpu_din = rom_d;
    else if (ram_cs) cpu_din = ram_q;
    else if (vid_cs) cpu_din = vram_q;
    else if (obj_cs) cpu_din = obj_q;
    else if (io_cs) case (io_sel)
        2'd0: cpu_din = kb ? {in0[7], ctl_9n[3] ? in0[6] : in3[0], in0[5:0]} : in0;
        2'd1: cpu_din = kb ? {in1[7:6], kb_noise[16], in1[4:0]} : fin ? {fin_dip[7:6], in1[5:0]} : in1;
        2'd2: cpu_din = bflags2[3] ? in3 : fin ? {in2[7:6], fin_dip[5:3], in2[2], fin_dip[1:0]} : in2;
        2'd3: cpu_din = 8'hFF;
    endcase
end

wire [9:0] obj_idx = {variant[4:0] == 5'd3 || variant[4:0] == 5'd22 || ck2 || bflags4[0] ? cpu_addr[9:8] : 2'b00, cpu_addr[7] ^ bflags6[7], cpu_addr[6:0]};
wire n3a;
wire mmk = ext_mode[3:0] == 4'd9;

galaxian_video video
(
    .clk(clk),
    .pause(pause),
    .ph(ph),
    .hcnt(hcnt),
    .vcnt(vcnt),

    .flip_x((bflags7[5] ? ctl_9n[7] : ctl_9n[6]) ^ crt_flip),
    .flip_y((bflags7[5] ? ctl_9n[6] : ctl_9n[7]) ^ crt_flip),
    .crt_flip(crt_flip),
    .stars_on(ctl_9n[4] & ~bflags[2] & ~mmk),
    .bullet_mode(vflags[0]),
    .rgb_gbr(vflags[1]),
    .gfx_packed(vflags[2]),
    .spr_hi(vflags[3]),
    .spr_ad(vflags[4]),
    .ext_mode(ext_mode[3:0]),
    .vflags2(vflags2[3:0]),
    .vflags3(vflags3[7:0]),
    .vflags4(vflags4),
    .vflags5(vflags5[6:0]),
    .bg_en(mmk ? ctl_9n[4] : ctl_9n[3]),
    .bg_rgb(bg_rgb),
    .gfxbank(mmk ? {ctl_9n[2], 2'b00, ctl_9n[0]} : ext_mode[3:0] == 4'd10 ? {3'b000, ctl_9n[2]} : gfxbank),
    .gfxbank4(gfxbank4),
    .stars_232(bflags2[5]),

    .cpu_addr(pause ? {hs_address[9] ^ stn, hs_address[8:0]} : obj_cs ? obj_idx : {cpu_addr[9] ^ stn, cpu_addr[8:0]}),
    .cpu_dout(pause ? hs_data_in : cpu_dout),
    .vram_we(pause ? hs_write & hs_vid : wr & vid_cs),
    .obj_we(wr & obj_cs),
    .vram_q(vram_q),
    .obj_q(obj_q),

    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .gfx0_we(gfx0_we),
    .gfx1_we(gfx1_we),
    .gfx2_we(gfx2_we),
    .gfxh_we(gfxh_we),
    .tb_we(rk_tb_we),
    .tb_addr(s26_a[4:0]),
    .tb_d(s26_d[2:0]),
    .col_bank(hm_cb),
    .db(db),
    .db_bg(db_bg),
    .db_split(db_split),
    .bd_patch(bflags13[5]),
    .pal_we(pal_we),
    .bgp_we(bgp_we),
    .rcl(rc),
    .rc_h(rc_h),
    .rc_v(rc_v),
    .rc_addr(cpu_addr[10:0]),
    .rc_we(wr & rc_vr),
    .rc_q(rc_q),
    .rcg_we(rcg_we),

    .vr_i(pr_i[6:1]),
    .vr_o(pr_o[6:1]),
    .gr_i(gr_i),
    .gr_o(gr_o),

    .n3a(n3a),

    .r(video_r),
    .g(video_g),
    .b(video_b)
);

reg  [1:0] sb_noise = 2'b00;
always @(posedge clk) if (reset) sb_noise <= 2'b00; else if (wr && sbh && cpu_addr[15:11] == 5'b10100 && cpu_addr[2:1] == 2'b00) sb_noise[cpu_addr[0]] <= cpu_dout[0];

reg [4:0] ay_div = 5'd0;
reg [6:0] oz_div = 7'd0;
always @(posedge clk) begin
    ay_div <= ay_div + 5'd1;
    oz_div <= oz_div == 7'd95 ? 7'd0 : oz_div + 7'd1;
end

wire snd_board = bflags3[0];
wire ay_cen    = ~pause & (bflags4[5] ? ay_div[3:0] == 4'd0 : bflags10[7] ? oz_div == 7'd0 : ay_div == 5'd0);

wire io_wr   = ~cpu_iorq_n & cpu_m1_n & ~cpu_wr_n;
wire bongo   = bflags2[2];
wire jb_ay   = mem & ~cpu_wr_n & ay_cs;
reg  [7:0] zz_latch = 8'd0;
wire zz_cs = bflags4[4] && cpu_addr[15:11] == 5'b01001;
always @(posedge clk) if (wr && zz_cs && cpu_addr[9:8] == 2'b01) zz_latch <= cpu_addr[7:0];
wire zz_w  = mem & ~cpu_wr_n & zz_cs & cpu_addr[9:8] == 2'b00 & cpu_addr[0];

wire fa_w    = fa_cs & ~cpu_wr_n;
wire fa_r    = fa_cs & ~cpu_rd_n;
wire tp_ay   = bflags8[6];
wire m_bdir  = (msh & ~msh_cs & io_wr & cpu_addr[3:1] == 3'b100) | jb_ay | (bongo & io_wr & cpu_addr[7:1] == 7'd0) | (tp_ay & io_wr & cpu_addr[7:1] == 7'd0) | zz_w |
               (fa_w & (cpu_addr[3:0] == 4'h3 || cpu_addr[3:0] == 4'hB));
wire m_bc1   = (jb_ay & cpu_addr[8]) | (bongo & io_wr & cpu_addr[7:0] == 8'h00) | (bongo & io_rd & cpu_addr[7:0] == 8'h02) |
               (zz_w & cpu_addr[1]) | (fa_w & cpu_addr[3:0] == 4'h3) | (fa_r & cpu_addr[3:0] == 4'h7) |
               (tp_ay & (io_wr | io_rd) & cpu_addr[7:0] == 8'h01) |
               (msh & ~msh_cs & ((io_wr & cpu_addr[3:0] == 4'h8) | (io_rd & cpu_addr[3:0] == 4'hC)));
wire ay2_bdir = fa_w & (cpu_addr[3:0] == 4'hC || cpu_addr[3:0] == 4'hE);
wire ay2_bc1  = (fa_w & cpu_addr[3:0] == 4'hC) | (fa_r & cpu_addr[3:0] == 4'hD);

wire cmd_wr = snd_board & (bflags3[2] ? io_wr & wr_d : wr & io_cs & io_sel == 2'd3);

assign z80sed_0_i.reset_n = ~(reset | watchdog_reset | s26 | m65);
assign z80sed_0_i.ce      = ce6 & hcnt[0] & ~pause;
assign z80sed_0_i.wait_n  = wait_n;
assign z80sed_0_i.int_n   = bflags9[4] ? cpu_nmi_n : cpu_int_n;
assign z80sed_0_i.nmi_n   = cpu_nmi_n | bflags9[4];
assign z80sed_0_i.di      = cpu_din;
assign z80_addr = z80sed_0_o.a;        assign z80_dout = z80sed_0_o.dout;
assign z80_m1_n = z80sed_0_o.m1_n;     assign z80_mreq_n = z80sed_0_o.mreq_n; assign z80_iorq_n = z80sed_0_o.iorq_n;
assign z80_rd_n = z80sed_0_o.rd_n;     assign z80_wr_n = z80sed_0_o.wr_n;     assign z80_rfsh_n = z80sed_0_o.rfsh_n;

assign s2650_0_i.reset = reset | watchdog_reset | ~s26;
assign s2650_0_i.ack   = s26_ack;
assign s2650_0_i.dr    = s26_dr;
assign s2650_0_i.irq   = s26_int;
assign s2650_0_i.sense = s26_vb ? vblank ^ (s26_rk | s26_df) : ~cpu_nmi_n;
assign s26_req = s2650_0_o.req;      assign s26_ad = s2650_0_o.ad;        assign s26_wr = s2650_0_o.wr;
assign s26_dw = s2650_0_o.dw;        assign s26_mio = s2650_0_o.mio;      assign s26_ene = s2650_0_o.ene;
assign s26_dc = s2650_0_o.dc;        assign s26_ph = s2650_0_o.ph;        assign s26_intack = s2650_0_o.intack;

assign t65_0_i.res_n  = ~(reset | watchdog_reset | ~m65);
assign t65_0_i.enable = m65_en;
assign t65_0_i.rdy    = 1'b1;
assign t65_0_i.irq_n  = cpu_nmi_n;
assign t65_0_i.nmi_n  = 1'b1;
assign t65_0_i.di     = cpu_din;
assign m65_a = t65_0_o.a;          assign m65_do = t65_0_o.dout;    assign m65_rw = t65_0_o.rw;

// BMX Stunts writes the SN76489 with the data bits reversed
reg  [3:0] sn_div = 4'd0;
always @(posedge clk) sn_div <= sn_div + 4'd1;
assign sn76489_0_i.rst  = reset | ~(m65 | bflags13[1] | bflags13[2]);
assign sn76489_0_i.ce   = sn_div == 4'd0 && !pause;
assign sn76489_0_i.wr_n = ~((wr && m65 && cpu_addr == 16'h8000) || rk_sn_we);
assign sn76489_0_i.cs_n = 1'b0;
assign sn76489_0_i.din  = m65 ? {cpu_dout[0], cpu_dout[1], cpu_dout[2], cpu_dout[3], cpu_dout[4], cpu_dout[5], cpu_dout[6], cpu_dout[7]} : s26_d;

assign ay_0_i.rst_n  = ~reset;
assign ay_0_i.ce     = ay_cen;
assign ay_0_i.bdir   = m_bdir;
assign ay_0_i.bc1    = m_bc1;
assign ay_0_i.din    = bflags4[4] ? zz_latch : cpu_dout;
assign ay_0_i.ioa_in = in3;
assign ay_0_i.iob_in = 8'hFF;
assign ay_dout = ay_0_o.dout;

assign ay_1_i.rst_n  = ~reset;
assign ay_1_i.ce     = ay_cen;
assign ay_1_i.bdir   = ay2_bdir;
assign ay_1_i.bc1    = ay2_bc1;
assign ay_1_i.din    = cpu_dout;
assign ay_1_i.ioa_in = 8'hFF;
assign ay_1_i.iob_in = 8'hFF;
assign ay2_dout = ay_1_o.dout;

assign hcnt_o       = hcnt;
assign vcnt_o       = vcnt;
assign n3a_o        = n3a;
assign lfo_o        = lfo_9m;
assign snd_o        = snd_9l;
assign pitch_o      = pitch;
assign sb_noise_o   = sb_noise;
assign vbl_irq_o    = ce6 & rising_vblank;
assign line8_irq_o  = ce6 & vcnt_step & vcnt[2:0] == 3'd7;
assign cmd_wr_o     = cmd_wr;
assign cpu_dout_o   = cpu_dout;
assign kb_latch_o   = kb_latch;
assign msh_trig_o   = msh_trig;
assign msh_rate_o   = msh_rate;
assign msh_vol_o    = msh_vol;
assign snd_irq_o    = snd_irq;
assign snd_cmd_we_o = snd_cmd_we;
assign ppi_din_o    = ppi_din;
assign snd_ctl_o    = snd_ctl;
assign sb_cmd_we_o  = wr && sbh && cpu_addr[15:11] == 5'b10001;

endmodule
