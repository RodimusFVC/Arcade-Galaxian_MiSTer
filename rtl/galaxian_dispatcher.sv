//  Copyright (C) 2026 Rodimus

module galaxian_dispatcher
(
    input               clk,
    input               reset,
    input         [2:0] ph,
    input               pause,

    input         [7:0] variant,
    input         [7:0] vflags,
    input         [7:0] bflags,
    input         [7:0] bflags2,
    input         [7:0] bflags3,
    input         [7:0] vflags2,
    input         [7:0] bflags4,
    input         [7:0] vflags3,
    input         [7:0] bflags5,
    input         [7:0] vflags4,
    input         [7:0] bflags6,
    input         [7:0] bflags7,
    input         [7:0] bflags8,
    input         [7:0] bflags9,
    input         [7:0] vflags5,
    input         [7:0] bflags10,
    input         [7:0] bflags12,
    input         [7:0] bflags13,
    input         [7:0] bflags11,
    input         [7:0] rom_top,
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
    input               ioctl_wr0,
    input               ds_wr,              // MRA index 5 byte: dsnd_engine program
    input               ds_on,              // a program arrived with this game

    input               crt_flip,
    input  signed [3:0] h_adj,
    input  signed [3:0] v_adj,

    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output              video_hs,
    output              video_vs,
    output              video_hblank,
    output              video_vblank,

    output signed [15:0] audio,

    input        [15:0] hs_address,
    input         [7:0] hs_data_in,
    output        [7:0] hs_data_out,
    input               hs_write
);

wire prog_cs, gfx0_cs, gfx1_cs, gfx2_cs, pal_cs, snd_cs, bgp_cs, samp_cs, sbp_cs, sbd_cs, dk_cs, gfxh_cs, tms_cs, tmsp_cs, rcg_cs,
     progh_cs, gfxw_cs;

selector rom_selector
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(prog_cs),
    .snd_cs(snd_cs),
    .bgp_cs(bgp_cs),
    .gfx0_cs(gfx0_cs),
    .gfx1_cs(gfx1_cs),
    .gfx2_cs(gfx2_cs),
    .pal_cs(pal_cs),
    .samp_cs(samp_cs),
    .sbp_cs(sbp_cs),
    .sbd_cs(sbd_cs),
    .dk_cs(dk_cs),
    .gfxh_cs(gfxh_cs),
    .tms_cs(tms_cs),
    .tmsp_cs(tmsp_cs),
    .rcg_cs(rcg_cs),
    .progh_cs(progh_cs),
    .gfxw_cs(gfxw_cs)
);

wire snd_board = bflags3[0];
wire vt        = bflags3[6];          // Nuova Videotron sound board
wire ko        = bflags5[0];
wire kb        = bflags11[5];
wire msh       = bflags11[3];
wire scp       = bflags11[6];
wire sbh       = bflags12[0];
wire fmc       = bflags10[6];
wire hsk       = variant[4:0] == 5'd16;
wire hm        = variant[4:0] == 5'd28;
wire ad        = hsk && bflags13[7];

wire [8:0] gal_hcnt, gal_vcnt;
wire       gal_n3a, gal_vbl_irq, gal_line8_irq, gal_cmd_wr, gal_msh_trig, gal_snd_irq, gal_snd_cmd_we, gal_sb_cmd_we;
wire [3:0] gal_lfo;
wire [7:0] gal_snd, gal_pitch, gal_cpu_dout, gal_kb_latch, gal_msh_rate, gal_ppi_din, gal_snd_ctl, sb_p1;
wire [1:0] gal_sb_noise;
wire [4:0] gal_msh_vol;

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

chip_pool_pkg::z80sed_i_t     z80sed_0_i;
chip_pool_pkg::z80sed_o_t     z80sed_0_o;
chip_pool_pkg::z80sed_i_t     sc_z80sed_1_i, kb_z80sed_1_i, ko_z80sed_1_i, vt_z80sed_1_i, z80sed_1_idle, z80sed_1_i;
chip_pool_pkg::z80sed_o_t     z80sed_1_o;
chip_pool_pkg::s2650_i_t      s2650_0_i;
chip_pool_pkg::s2650_o_t      s2650_0_o;
chip_pool_pkg::t65_i_t        t65_0_i;
chip_pool_pkg::t65_o_t        t65_0_o;
chip_pool_pkg::mcs48bus_i_t   mcs48bus_0_i;
chip_pool_pkg::mcs48bus_o_t   mcs48bus_0_o;
chip_pool_pkg::sn76489_i_t    sn76489_0_i;
chip_pool_pkg::sn76489_o_t    sn76489_0_o;
chip_pool_pkg::ayr_i_t        gal_ay_0_i, sc_ay_0_i, vt_ay_0_i, ay_0_i;
chip_pool_pkg::ayio_o_t       ay_0_o;
chip_pool_pkg::ayr_i_t        ay_1_i, ay_2_i, ay_3_i, ay_4_i;
chip_pool_pkg::ay_o_t         ay_1_o, ay_2_o, ay_3_o, ay_4_o;
chip_pool_pkg::i8255_i_t      i8255_0_i, i8255_1_i;
chip_pool_pkg::i8255_o_t      i8255_0_o, i8255_1_o;
chip_pool_pkg::sp0250_i_t     sp0250_0_i;
chip_pool_pkg::sp0250_o_t     sp0250_0_o;
chip_pool_pkg::tmsprom_i_t    tmsprom_0_i;
chip_pool_pkg::tmsprom_o_t    tmsprom_0_o;
chip_pool_pkg::tms5110_i_t    tms5110_0_i;
chip_pool_pkg::tms5110_o_t    tms5110_0_o;
chip_pool_pkg::digitalker_i_t digitalker_0_i;
chip_pool_pkg::digitalker_o_t digitalker_0_o;

wire [12:0] tms_rom_a;
wire  [7:0] tms_rom_q;
wire [13:0] dk_rom_a;
wire  [7:0] dk_rom_q;

// z80sed_0: main CPU (Galaxian board)
wire [15:0] z80sed_0_a;
wire  [7:0] z80sed_0_do;
wire        z80sed_0_m1_n, z80sed_0_mreq_n, z80sed_0_iorq_n, z80sed_0_rd_n, z80sed_0_wr_n, z80sed_0_rfsh_n;

t80sv_T80sed z80sed_0
(
    .RESET_n(z80sed_0_i.reset_n), .CLK_n(clk), .CLKEN(z80sed_0_i.ce), .WAIT_n(z80sed_0_i.wait_n), .INT_n(z80sed_0_i.int_n),
    .NMI_n(z80sed_0_i.nmi_n), .BUSRQ_n(1'b1), .M1_n(z80sed_0_m1_n), .MREQ_n(z80sed_0_mreq_n), .IORQ_n(z80sed_0_iorq_n),
    .RD_n(z80sed_0_rd_n), .WR_n(z80sed_0_wr_n), .RFSH_n(z80sed_0_rfsh_n), .HALT_n(), .BUSAK_n(), .A(z80sed_0_a),
    .DI(z80sed_0_i.di), .DO(z80sed_0_do)
);

assign z80sed_0_o.a = z80sed_0_a;           assign z80sed_0_o.dout = z80sed_0_do;
assign z80sed_0_o.m1_n = z80sed_0_m1_n;     assign z80sed_0_o.mreq_n = z80sed_0_mreq_n; assign z80sed_0_o.iorq_n = z80sed_0_iorq_n;
assign z80sed_0_o.rd_n = z80sed_0_rd_n;     assign z80sed_0_o.wr_n = z80sed_0_wr_n;     assign z80sed_0_o.rfsh_n = z80sed_0_rfsh_n;

// z80sed_1: sound CPU - Konami, King & Balloon, Check Man / Dingo, Nuova Videotron sound boards; held in reset on sets with none
assign z80sed_1_idle.reset_n = 1'b0;  assign z80sed_1_idle.ce = 1'b0;     assign z80sed_1_idle.wait_n = 1'b1;
assign z80sed_1_idle.int_n = 1'b1;    assign z80sed_1_idle.nmi_n = 1'b1;  assign z80sed_1_idle.di = 8'hFF;
assign z80sed_1_i = ko ? ko_z80sed_1_i : kb ? kb_z80sed_1_i : snd_board ? sc_z80sed_1_i : vt ? vt_z80sed_1_i : z80sed_1_idle;

wire [15:0] z80sed_1_a;
wire  [7:0] z80sed_1_do;
wire        z80sed_1_m1_n, z80sed_1_mreq_n, z80sed_1_iorq_n, z80sed_1_rd_n, z80sed_1_wr_n, z80sed_1_rfsh_n;

t80sv_T80sed z80sed_1
(
    .RESET_n(z80sed_1_i.reset_n), .CLK_n(clk), .CLKEN(z80sed_1_i.ce), .WAIT_n(z80sed_1_i.wait_n), .INT_n(z80sed_1_i.int_n),
    .NMI_n(z80sed_1_i.nmi_n), .BUSRQ_n(1'b1), .M1_n(z80sed_1_m1_n), .MREQ_n(z80sed_1_mreq_n), .IORQ_n(z80sed_1_iorq_n),
    .RD_n(z80sed_1_rd_n), .WR_n(z80sed_1_wr_n), .RFSH_n(z80sed_1_rfsh_n), .HALT_n(), .BUSAK_n(), .A(z80sed_1_a),
    .DI(z80sed_1_i.di), .DO(z80sed_1_do)
);

assign z80sed_1_o.a = z80sed_1_a;           assign z80sed_1_o.dout = z80sed_1_do;
assign z80sed_1_o.m1_n = z80sed_1_m1_n;     assign z80sed_1_o.mreq_n = z80sed_1_mreq_n; assign z80sed_1_o.iorq_n = z80sed_1_iorq_n;
assign z80sed_1_o.rd_n = z80sed_1_rd_n;     assign z80sed_1_o.wr_n = z80sed_1_wr_n;     assign z80sed_1_o.rfsh_n = z80sed_1_rfsh_n;

// s2650_0: S2650 sets of the Galaxian board
wire        s2650_0_req, s2650_0_wr, s2650_0_mio, s2650_0_ene, s2650_0_dc, s2650_0_intack;
wire [14:0] s2650_0_ad;
wire  [7:0] s2650_0_dw;
wire  [1:0] s2650_0_ph;

s2650sv_s2650_cpu s2650_0
(
    .clk(clk), .reset(s2650_0_i.reset), .req(s2650_0_req), .ack(s2650_0_i.ack), .ad(s2650_0_ad), .wr(s2650_0_wr),
    .dw(s2650_0_dw), .dr(s2650_0_i.dr), .mio(s2650_0_mio), .ene(s2650_0_ene), .dc(s2650_0_dc), .ph(s2650_0_ph),
    .irq(s2650_0_i.irq), .intack(s2650_0_intack), .ivec(8'h03), .sense(s2650_0_i.sense), .flag()
);

assign s2650_0_o.req = s2650_0_req;  assign s2650_0_o.ad = s2650_0_ad;    assign s2650_0_o.wr = s2650_0_wr;
assign s2650_0_o.dw = s2650_0_dw;    assign s2650_0_o.mio = s2650_0_mio;  assign s2650_0_o.ene = s2650_0_ene;
assign s2650_0_o.dc = s2650_0_dc;    assign s2650_0_o.ph = s2650_0_ph;    assign s2650_0_o.intack = s2650_0_intack;

// t65_0: BMX Stunts 6502 (Galaxian board)
wire [23:0] t65_0_a;
wire  [7:0] t65_0_do;
wire        t65_0_rw, t65_0_sync;

t65sv_T65 t65_0
(
    .Mode(2'b00), .Res_n(t65_0_i.res_n), .Enable(t65_0_i.enable), .Clk(clk), .Rdy(t65_0_i.rdy), .Abort_n(1'b1),
    .IRQ_n(t65_0_i.irq_n), .NMI_n(t65_0_i.nmi_n), .SO_n(1'b1), .R_W_n(t65_0_rw), .Sync(t65_0_sync), .EF(), .MF(), .XF(), .ML_n(), .VP_n(),
    .VDA(), .VPA(), .A(t65_0_a), .DI(t65_0_i.di), .DO(t65_0_do), .Regs(), .NMI_ack()
);

assign t65_0_o.a = t65_0_a[15:0];  assign t65_0_o.dout = t65_0_do;  assign t65_0_o.rw = t65_0_rw;  assign t65_0_o.sync = t65_0_sync;

// mcs48bus_0: Space Battle speech board 8039
wire  [7:0] mcu_p1, mcu_p2, mcu_db;
wire [11:0] mcu_pa;
wire        mcu_ale, mcu_wr_n, mcu_rd_n;

t48sv_t8039_notri_extrom #(
    .gate_port_input_g (0),
    .ram_addr_width_g  (7)
) mcs48bus_0 (
    .xtal_i(clk), .xtal_en_i(mcs48bus_0_i.xtal_en), .reset_n_i(mcs48bus_0_i.reset_n),
    .t0_i(1'b0), .t0_o(), .t0_dir_o(), .int_n_i(mcs48bus_0_i.int_n), .ea_i(1'b0),
    .rd_n_o(mcu_rd_n), .psen_n_o(), .wr_n_o(mcu_wr_n), .ale_o(mcu_ale),
    .db_i(mcs48bus_0_i.db), .db_o(mcu_db), .db_dir_o(), .t1_i(mcs48bus_0_i.t1),
    .p2_i(8'hFF), .p2_o(mcu_p2), .p2l_low_imp_o(), .p2h_low_imp_o(),
    .p1_i(mcs48bus_0_i.p1), .p1_o(mcu_p1), .p1_low_imp_o(), .prog_n_o(),
    .pmem_addr_o(mcu_pa), .pmem_data_i(mcs48bus_0_i.pmem_d)
);

assign mcs48bus_0_o.p1 = mcu_p1;     assign mcs48bus_0_o.p2 = mcu_p2;      assign mcs48bus_0_o.db = mcu_db;
assign mcs48bus_0_o.ale = mcu_ale;   assign mcs48bus_0_o.wr_n = mcu_wr_n;  assign mcs48bus_0_o.rd_n = mcu_rd_n;
assign mcs48bus_0_o.pmem_a = mcu_pa;

// sn76489_0: BMX Stunts / Rack + Roll SN76489 (Galaxian board)
wire [10:0] sn76489_0_sound;
wire        sn76489_0_ready;

jt89 sn76489_0
(
    .rst(sn76489_0_i.rst), .clk(clk), .clk_en(sn76489_0_i.ce), .wr_n(sn76489_0_i.wr_n), .cs_n(sn76489_0_i.cs_n),
    .din(sn76489_0_i.din), .sound(sn76489_0_sound), .ready(sn76489_0_ready)
);

assign sn76489_0_o.sound = sn76489_0_sound;  assign sn76489_0_o.ready = sn76489_0_ready;

// ay_0: Galaxian board AY (Jump Bug, Bongo, Zig Zag, Fantastic, Moon Shuttle, Triple Punch), or the Check Man sound board's
assign ay_0_i = snd_board ? sc_ay_0_i : vt ? vt_ay_0_i : gal_ay_0_i;

wire [7:0] ay_0_dout, ay_0_a, ay_0_b, ay_0_c, ay_0_ioa, ay_0_iob;
wire [9:0] ay_0_snd;

jt49_bus #(.COMP(3'b010)) ay_0
(
    .rst_n(ay_0_i.rst_n), .clk(clk), .clk_en(ay_0_i.ce), .bdir(ay_0_i.bdir), .bc1(ay_0_i.bc1), .din(ay_0_i.din),
    .sel(1'b1), .dout(ay_0_dout), .sound(ay_0_snd), .A(ay_0_a), .B(ay_0_b), .C(ay_0_c), .sample(),
    .IOA_in(ay_0_i.ioa_in), .IOA_out(ay_0_ioa), .IOB_in(ay_0_i.iob_in), .IOB_out(ay_0_iob)
);

assign ay_0_o.dout = ay_0_dout;  assign ay_0_o.a = ay_0_a;  assign ay_0_o.b = ay_0_b;  assign ay_0_o.c = ay_0_c;
assign ay_0_o.ioa_out = ay_0_ioa;  assign ay_0_o.iob_out = ay_0_iob;  assign ay_0_o.sound = ay_0_snd;

// ay_1: Fantastic second AY (Galaxian board); ay_2 / ay_3 / ay_4: Konami sound board AY #1 / #2 / Scorpion's third
wire [7:0] ay_1_dout, ay_1_a, ay_1_b, ay_1_c, ay_1_iob;
wire [9:0] ay_1_snd;

jt49_bus #(.COMP(3'b010)) ay_1
(
    .rst_n(ay_1_i.rst_n), .clk(clk), .clk_en(ay_1_i.ce), .bdir(ay_1_i.bdir), .bc1(ay_1_i.bc1), .din(ay_1_i.din),
    .sel(1'b1), .dout(ay_1_dout), .sound(ay_1_snd), .A(ay_1_a), .B(ay_1_b), .C(ay_1_c), .sample(),
    .IOA_in(ay_1_i.ioa_in), .IOA_out(), .IOB_in(ay_1_i.iob_in), .IOB_out(ay_1_iob)
);

assign ay_1_o.dout = ay_1_dout;  assign ay_1_o.a = ay_1_a;  assign ay_1_o.b = ay_1_b;  assign ay_1_o.c = ay_1_c;
assign ay_1_o.iob_out = ay_1_iob;  assign ay_1_o.sound = ay_1_snd;

wire [7:0] ay_2_dout, ay_2_a, ay_2_b, ay_2_c, ay_2_iob;
wire [9:0] ay_2_snd;

jt49_bus #(.COMP(3'b100)) ay_2
(
    .rst_n(ay_2_i.rst_n), .clk(clk), .clk_en(ay_2_i.ce), .bdir(ay_2_i.bdir), .bc1(ay_2_i.bc1), .din(ay_2_i.din),
    .sel(1'b1), .dout(ay_2_dout), .sound(ay_2_snd), .A(ay_2_a), .B(ay_2_b), .C(ay_2_c), .sample(),
    .IOA_in(ay_2_i.ioa_in), .IOA_out(), .IOB_in(ay_2_i.iob_in), .IOB_out(ay_2_iob)
);

assign ay_2_o.dout = ay_2_dout;  assign ay_2_o.a = ay_2_a;  assign ay_2_o.b = ay_2_b;  assign ay_2_o.c = ay_2_c;
assign ay_2_o.iob_out = ay_2_iob;  assign ay_2_o.sound = ay_2_snd;

wire [7:0] ay_3_dout, ay_3_a, ay_3_b, ay_3_c, ay_3_iob;
wire [9:0] ay_3_snd;

jt49_bus #(.COMP(3'b100)) ay_3
(
    .rst_n(ay_3_i.rst_n), .clk(clk), .clk_en(ay_3_i.ce), .bdir(ay_3_i.bdir), .bc1(ay_3_i.bc1), .din(ay_3_i.din),
    .sel(1'b1), .dout(ay_3_dout), .sound(ay_3_snd), .A(ay_3_a), .B(ay_3_b), .C(ay_3_c), .sample(),
    .IOA_in(ay_3_i.ioa_in), .IOA_out(), .IOB_in(ay_3_i.iob_in), .IOB_out(ay_3_iob)
);

assign ay_3_o.dout = ay_3_dout;  assign ay_3_o.a = ay_3_a;  assign ay_3_o.b = ay_3_b;  assign ay_3_o.c = ay_3_c;
assign ay_3_o.iob_out = ay_3_iob;  assign ay_3_o.sound = ay_3_snd;

wire [7:0] ay_4_dout, ay_4_a, ay_4_b, ay_4_c, ay_4_iob;
wire [9:0] ay_4_snd;

jt49_bus #(.COMP(3'b100)) ay_4
(
    .rst_n(ay_4_i.rst_n), .clk(clk), .clk_en(ay_4_i.ce), .bdir(ay_4_i.bdir), .bc1(ay_4_i.bc1), .din(ay_4_i.din),
    .sel(1'b1), .dout(ay_4_dout), .sound(ay_4_snd), .A(ay_4_a), .B(ay_4_b), .C(ay_4_c), .sample(),
    .IOA_in(ay_4_i.ioa_in), .IOA_out(), .IOB_in(ay_4_i.iob_in), .IOB_out(ay_4_iob)
);

assign ay_4_o.dout = ay_4_dout;  assign ay_4_o.a = ay_4_a;  assign ay_4_o.b = ay_4_b;  assign ay_4_o.c = ay_4_c;
assign ay_4_o.iob_out = ay_4_iob;  assign ay_4_o.sound = ay_4_snd;

// i8255_0 / i8255_1: Konami-style PPIs of the Galaxian board (0 = inputs, 1 = sound command / control / DSW)
wire [7:0] i8255_0_dout, i8255_0_pa, i8255_0_pb, i8255_0_pc, i8255_1_dout, i8255_1_pa, i8255_1_pb, i8255_1_pc;
wire       ppi1_pc_we = i8255_1_i.wr && (i8255_1_i.a == 2'd2 || (i8255_1_i.a == 2'd3 && !i8255_1_i.din[7]));

i8255 i8255_0
(
    .clk(clk), .reset(i8255_0_i.reset), .cs(i8255_0_i.cs), .rd(i8255_0_i.rd), .wr(i8255_0_i.wr), .a(i8255_0_i.a),
    .din(i8255_0_i.din), .dout(i8255_0_dout), .pa_in(i8255_0_i.pa_in), .pb_in(i8255_0_i.pb_in), .pc_in(i8255_0_i.pc_in),
    .stb_a_n(i8255_0_i.stb_a_n), .ack_a_n(i8255_0_i.ack_a_n), .pc2_n(i8255_0_i.pc2_n),
    .pa_out(i8255_0_pa), .pb_out(i8255_0_pb), .pc_out(i8255_0_pc)
);

i8255 i8255_1
(
    .clk(clk), .reset(i8255_1_i.reset), .cs(i8255_1_i.cs), .rd(i8255_1_i.rd), .wr(i8255_1_i.wr), .a(i8255_1_i.a),
    .din(i8255_1_i.din), .dout(i8255_1_dout), .pa_in(i8255_1_i.pa_in), .pb_in(i8255_1_i.pb_in), .pc_in(i8255_1_i.pc_in),
    .stb_a_n(i8255_1_i.stb_a_n), .ack_a_n(i8255_1_i.ack_a_n), .pc2_n(i8255_1_i.pc2_n),
    .pa_out(i8255_1_pa), .pb_out(i8255_1_pb), .pc_out(i8255_1_pc)
);

assign i8255_0_o.dout = i8255_0_dout;  assign i8255_0_o.pa_out = i8255_0_pa;  assign i8255_0_o.pb_out = i8255_0_pb;  assign i8255_0_o.pc_out = i8255_0_pc;
assign i8255_1_o.dout = i8255_1_dout;  assign i8255_1_o.pa_out = i8255_1_pa;  assign i8255_1_o.pb_out = i8255_1_pb;  assign i8255_1_o.pc_out = i8255_1_pc;

// sp0250_0: Space Battle speech board
wire        sp0250_0_drq, sp0250_0_valid;
wire [13:0] sp0250_0_audio;

sp0250 sp0250_0
(
    .clk(clk), .reset_n(sp0250_0_i.reset_n), .ce_3_12m(sp0250_0_i.ce_3_12m), .ce_rom_1_56m(sp0250_0_i.ce_rom_1_56m),
    .data_in(sp0250_0_i.data_in), .wr(sp0250_0_i.wr), .drq(sp0250_0_drq), .audio_out(sp0250_0_audio), .audio_valid(sp0250_0_valid)
);

assign sp0250_0_o.drq = sp0250_0_drq;  assign sp0250_0_o.audio = sp0250_0_audio;  assign sp0250_0_o.audio_valid = sp0250_0_valid;

// tmsprom_0 + tms5110_0: A.D. 2083 speech (Konami sound board); the sequencer reads the tms ROM block
wire       tmsprom_0_data, tmsprom_0_pdc, tms5110_0_m0, tms5110_0_busy, tms5110_0_talk;
wire [3:0] tmsprom_0_ctl;
wire signed [15:0] tms5110_0_sample;

tmsprom tmsprom_0
(
    .clk(clk), .reset(tmsprom_0_i.reset), .ce_romclk(tmsprom_0_i.ce_romclk), .chip_busy(tmsprom_0_i.chip_busy),
    .enable(tmsprom_0_i.enable), .bit_sel(tmsprom_0_i.bit_sel), .csq0(tmsprom_0_i.csq0), .csq1(tmsprom_0_i.csq1),
    .prom_wr(tmsprom_0_i.prom_wr), .prom_waddr(tmsprom_0_i.prom_waddr), .prom_wdata(tmsprom_0_i.prom_wdata),
    .rom_addr(tms_rom_a), .rom_q(tms_rom_q), .m0(tmsprom_0_i.m0), .data_bit(tmsprom_0_data), .ctl(tmsprom_0_ctl),
    .pdc(tmsprom_0_pdc)
);

assign tmsprom_0_o.data_bit = tmsprom_0_data;  assign tmsprom_0_o.ctl = tmsprom_0_ctl;  assign tmsprom_0_o.pdc = tmsprom_0_pdc;

tms5110 tms5110_0
(
    .clk(clk), .reset(tms5110_0_i.reset), .ce_sample(tms5110_0_i.ce_sample), .ctl(tms5110_0_i.ctl), .pdc(tms5110_0_i.pdc),
    .m0(tms5110_0_m0), .data_bit(tms5110_0_i.data_bit), .busy(tms5110_0_busy), .talk_status(tms5110_0_talk),
    .sample(tms5110_0_sample)
);

assign tms5110_0_o.m0 = tms5110_0_m0;  assign tms5110_0_o.busy = tms5110_0_busy;  assign tms5110_0_o.talk_status = tms5110_0_talk;
assign tms5110_0_o.sample = tms5110_0_sample;

// digitalker_0: Scorpion / Harem speech (Konami sound board); 1 MHz stream tick = 49.152 MHz x 125 / 6144, dk ROM block
reg [12:0] dk_frac = 13'd0;
reg        dk_tick = 1'b0;
always @(posedge clk) begin
    if (dk_frac >= 13'd6019) begin dk_frac <= dk_frac - 13'd6019; dk_tick <= ~pause; end
    else                     begin dk_frac <= dk_frac + 13'd125;  dk_tick <= 1'b0;   end
end

wire               digitalker_0_intr;
wire signed [15:0] digitalker_0_sample;

digitalker digitalker_0
(
    .clk(clk), .reset(digitalker_0_i.reset), .ce(dk_tick), .data(digitalker_0_i.data), .cs(digitalker_0_i.cs),
    .cms(digitalker_0_i.cms), .wr(digitalker_0_i.wr), .intr(digitalker_0_intr), .rom_a(dk_rom_a), .rom_d(dk_rom_q),
    .out(digitalker_0_sample)
);

assign digitalker_0_o.intr = digitalker_0_intr;  assign digitalker_0_o.sample = digitalker_0_sample;

// dsnd_0: discrete sound (program = MRA index 5: Galaxian / Moon Cresta), TICK 1024 = 48 kHz; out muted unless ds_on
chip_pool_pkg::dsnd_i_t dsnd_0_i;
chip_pool_pkg::dsnd_o_t dsnd_0_o, dsnd_0_q;

dsnd_engine #(.TICK(1024)) dsnd_0
(
    .clk(clk), .reset(reset), .pause(pause),
    .prog_wr(ds_wr), .prog_addr(ioctl_addr[12:0]), .prog_data(ioctl_dout),
    .src(dsnd_0_i.src),
    .out(dsnd_0_q.out), .out_r(dsnd_0_q.out_r), .sample(dsnd_0_q.sample)
);

always_comb begin
    dsnd_0_o        = dsnd_0_q;
    dsnd_0_o.out    = ds_on ? dsnd_0_q.out   : 16'd0;
    dsnd_0_o.out_r  = ds_on ? dsnd_0_q.out_r : 16'd0;
end

/////////////////////////////  Shared ROM blocks  /////////////////////////////

wire [16:0] gal_rom_a;
wire [13:0] sc_r0a, kb_r0a, ko_r0a, vt_r0a;
wire [12:0] msh_rom_a;
wire [10:0] sb_prog_a;
wire [11:0] sb_data_a;
wire  [7:0] prog_q, rom0_d, samp_q, sb_prog_q, sb_data_q;

// prog_rom: 128K main CPU ROM, ioctl 0x00000-0x0FFFF + 0x30000-0x3FFFF (upper 64K: Video Eight's 8 banks)
dpram_dc #(.widthad_a(17)) prog_rom
(
    .clock_a(clk), .address_a({progh_cs, ioctl_addr[15:0]}), .data_a(ioctl_dout), .wren_a(ioctl_wr0 & (prog_cs | progh_cs)), .q_a(),
    .clock_b(clk), .address_b(gal_rom_a), .data_b(8'd0), .wren_b(1'b0), .q_b(prog_q)
);

// rom0: sound CPU ROM, ioctl 0x18000-0x1BFFF (Check Man 4K, King & Balloon 8K, Konami 16K; each reads it from 0)
dpram_dc #(.widthad_a(14)) rom0
(
    .clock_a(clk), .address_a(ioctl_addr[13:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr0 & snd_cs), .q_a(),
    .clock_b(clk), .address_b(ko ? ko_r0a : kb ? kb_r0a : vt ? vt_r0a : sc_r0a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom0_d)
);

dpram_dc #(.widthad_a(13)) samp_rom
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr0 & samp_cs), .q_a(),
    .clock_b(clk), .address_b(msh_rom_a), .data_b(8'd0), .wren_b(1'b0), .q_b(samp_q)
);

dpram_dc #(.widthad_a(11)) sbp_rom
(
    .clock_a(clk), .address_a(ioctl_addr[10:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr0 & sbp_cs), .q_a(),
    .clock_b(clk), .address_b(sb_prog_a), .data_b(8'd0), .wren_b(1'b0), .q_b(sb_prog_q)
);

dpram_dc #(.widthad_a(12)) sbd_rom
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr0 & sbd_cs), .q_a(),
    .clock_b(clk), .address_b(sb_data_a), .data_b(8'd0), .wren_b(1'b0), .q_b(sb_data_q)
);

dpram_dc #(.widthad_a(13)) tms_rom
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr0 & tms_cs), .q_a(),
    .clock_b(clk), .address_b(tms_rom_a), .data_b(8'd0), .wren_b(1'b0), .q_b(tms_rom_q)
);

dpram_dc #(.widthad_a(14)) dk_rom
(
    .clock_a(clk), .address_a(ioctl_addr[13:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr0 & dk_cs), .q_a(),
    .clock_b(clk), .address_b(dk_rom_a), .data_b(8'd0), .wren_b(1'b0), .q_b(dk_rom_q)
);

//   block 0 (32K) gfx plane 0 (ioctl 0x10000 + upper 8K at 0x24000; 32K planes at 0x40000)
//   block 1 (32K) gfx plane 1 (ioctl 0x12000 + upper 8K at 0x26000; 32K planes at 0x48000)
//   block 2 (4K)  gfx plane 2 (ioctl 0x16000)
//   block 3 (8K)  Rock Climber background gfx (ioctl 0x2C000)
localparam int GFX_BLOCKS = 4;

ram_pool_pkg::pram_i_t [GFX_BLOCKS-1:0] gr_i;
ram_pool_pkg::pram_o_t [GFX_BLOCKS-1:0] gr_o;

function automatic int gfx_aw(input int n);
    gfx_aw = n < 2 ? 15 : n == 2 ? 12 : 13;
endfunction

genvar gn;
generate
    for (gn = 0; gn < GFX_BLOCKS; gn = gn + 1) begin : gpool
        localparam int AW = gfx_aw(gn);
        dpram_dc #(.widthad_a(AW)) rom
        (
            .clock_a(clk), .address_a(gr_i[gn].a_addr[AW-1:0]), .data_a(gr_i[gn].a_d), .wren_a(gr_i[gn].a_we),
            .q_a(gr_o[gn].a_q),
            .clock_b(clk), .address_b(gr_i[gn].b_addr[AW-1:0]), .data_b(gr_i[gn].b_d), .wren_b(gr_i[gn].b_we),
            .q_b(gr_o[gn].b_q)
        );
    end
endgenerate

/////////////////////////////  Shared RAM pool  /////////////////////////////

//   block 0 (4K)   Galaxian board work RAM: port B = hiscore
//   block 1 (1K)   Galaxian video RAM
//   block 2 (1K)   object RAM, tile copy
//   block 3 (1K)   object RAM, sprite copy
//   block 4 (256)  sprite line buffer
//   block 5 (256)  second sprite line buffer
//   block 6 (2K)   Rock Climber background RAM
//   block 7 (4K)   Konami sound board work RAM
//   block 8 (1K)   Check Man sound board work RAM
localparam int RAM_BLOCKS = 9;

ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] gal_pr_i, ko_pr_i, sc_pr_i, vt_pr_i, pool_i;
ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pool_o;

assign pool_i[6:0] = gal_pr_i[6:0];
assign pool_i[7]   = ko_pr_i[7];
assign pool_i[8]   = vt ? vt_pr_i[8] : sc_pr_i[8];

function automatic int ram_aw(input int n);
    ram_aw = n == 0 || n == 7 ? 12 : n == 4 || n == 5 ? 8 : n == 6 ? 11 : 10;
endfunction

genvar pn;
generate
    for (pn = 0; pn < RAM_BLOCKS; pn = pn + 1) begin : rpool
        localparam int AW = ram_aw(pn);
        dpram_dc #(.widthad_a(AW)) ram
        (
            .clock_a(clk), .address_a(pool_i[pn].a_addr[AW-1:0]), .data_a(pool_i[pn].a_d), .wren_a(pool_i[pn].a_we),
            .q_a(pool_o[pn].a_q),
            .clock_b(clk), .address_b(pool_i[pn].b_addr[AW-1:0]), .data_b(pool_i[pn].b_d), .wren_b(pool_i[pn].b_we),
            .q_b(pool_o[pn].b_q)
        );
    end
endgenerate

/////////////////////////////  Boards  /////////////////////////////

wire signed [15:0] gal_audio, sbs_audio, disc_audio, ay_audio, konami_audio, sb_audio;
wire        [63:0] gal_src, sb_src;                        // dsnd_0 sources: Galaxian / Moon Cresta or Space Battle board
assign dsnd_0_i.src = sbh ? sb_src : gal_src;
wire         [7:0] samp_out;
wire         [3:0] kb_dac;

galaxian_board galaxian
(
    .clk(clk),
    .reset(reset),
    .ph(ph),
    .pause(pause),
    .variant(variant),
    .vflags(vflags),
    .bflags(bflags),
    .bflags2(bflags2),
    .bflags3(bflags3),
    .vflags2(vflags2),
    .bflags4(bflags4),
    .vflags3(vflags3),
    .bflags5(bflags5),
    .vflags4(vflags4),
    .bflags6(bflags6),
    .bflags7(bflags7),
    .bflags8(bflags8),
    .bflags9(bflags9),
    .vflags5(vflags5),
    .bflags10(bflags10),
    .bflags11(bflags11),
    .bflags12(bflags12),
    .bflags13(bflags13),
    .rom_top(rom_top),
    .ext_mode(ext_mode),
    .vt_gb0_we(vt_gb0_we),
    .vt_gb1_we(vt_gb1_we),
    .vt_gb_d(vt_gb_d),
    .in0(in0),
    .dial1(dial1),
    .dial2(dial2),
    .in1(in1),
    .in2(in2),
    .in3(in3),
    .dip4(dip4),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .gfx0_we(ioctl_wr0 & gfx0_cs),
    .gfx1_we(ioctl_wr0 & gfx1_cs),
    .gfx2_we(ioctl_wr0 & gfx2_cs),
    .gfxh_we(ioctl_wr0 & gfxh_cs),
    .gfxw_we(ioctl_wr0 & gfxw_cs),
    .pal_we(ioctl_wr0 & pal_cs),
    .bgp_we(ioctl_wr0 & bgp_cs),
    .rcg_we(ioctl_wr0 & rcg_cs),
    .crt_flip(crt_flip),
    .h_adj(h_adj),
    .v_adj(v_adj),
    .video_r(video_r),
    .video_g(video_g),
    .video_b(video_b),
    .video_hs(video_hs),
    .video_vs(video_vs),
    .video_hblank(video_hblank),
    .video_vblank(video_vblank),
    .hcnt_o(gal_hcnt),
    .vcnt_o(gal_vcnt),
    .n3a_o(gal_n3a),
    .lfo_o(gal_lfo),
    .snd_o(gal_snd),
    .pitch_o(gal_pitch),
    .sb_noise_o(gal_sb_noise),
    .vbl_irq_o(gal_vbl_irq),
    .line8_irq_o(gal_line8_irq),
    .cmd_wr_o(gal_cmd_wr),
    .cpu_dout_o(gal_cpu_dout),
    .kb_latch_o(gal_kb_latch),
    .msh_trig_o(gal_msh_trig),
    .msh_rate_o(gal_msh_rate),
    .msh_vol_o(gal_msh_vol),
    .snd_irq_o(gal_snd_irq),
    .snd_cmd_we_o(gal_snd_cmd_we),
    .ppi_din_o(gal_ppi_din),
    .snd_ctl_o(gal_snd_ctl),
    .sb_cmd_we_o(gal_sb_cmd_we),
    .sb_p1(sb_p1),
    .hs_address(hs_address),
    .hs_data_in(hs_data_in),
    .hs_data_out(hs_data_out),
    .hs_write(hs_write),
    .z80sed_0_i(z80sed_0_i),
    .z80sed_0_o(z80sed_0_o),
    .s2650_0_i(s2650_0_i),
    .s2650_0_o(s2650_0_o),
    .t65_0_i(t65_0_i),
    .t65_0_o(t65_0_o),
    .sn76489_0_i(sn76489_0_i),
    .sn76489_0_o(sn76489_0_o),
    .ay_0_i(gal_ay_0_i),
    .ay_0_o(ay_0_o),
    .ay_1_i(ay_1_i),
    .ay_1_o(ay_1_o),
    .i8255_0_i(i8255_0_i),
    .i8255_0_o(i8255_0_o),
    .i8255_1_i(i8255_1_i),
    .i8255_1_o(i8255_1_o),
    .ppi1_pc_we(ppi1_pc_we),
    .rom_a(gal_rom_a),
    .rom_q(prog_q),
    .gr_i(gr_i),
    .gr_o(gr_o),
    .pr_i(gal_pr_i),
    .pr_o(pool_o)
);

galaxian_sound galaxian_snd
(
    .clk(clk),
    .reset(reset),
    .pdiv8(bflags2[4]),
    .pause(pause),
    .sample(dsnd_0_o.sample),
    .v2(gal_vcnt[1]),
    .n3a(gal_n3a),
    .lfo(gal_lfo),
    .fs(gal_snd[2:0]),
    .hit(gal_snd[3]),
    .fire(gal_snd[5]),
    .vol(gal_snd[7:6]),
    .pitch(gal_pitch),
    .src(gal_src)
);
assign gal_audio = dsnd_0_o.out;

galaxian_sbsound sbhoei_snd
(
    .clk(clk),
    .reset(reset | ~sbh),
    .pause(pause),
    .v2(gal_vcnt[1]),
    .v4(gal_vcnt[2]),
    .h64(gal_hcnt[6]),
    .n3a(gal_n3a),
    .noise_en({gal_snd[3], gal_sb_noise}),
    .fire(gal_snd[5]),
    .vol(gal_snd[7:6]),
    .pitch(gal_pitch),
    .sample(dsnd_0_o.sample),
    .src(sb_src)
);
assign sbs_audio = dsnd_0_o.out;

galaxian_sbspeech sbhoei_spch
(
    .clk(clk),
    .reset(reset | ~sbh),
    .pause(pause),
    .cmd_we(gal_sb_cmd_we),
    .cmd(gal_cpu_dout),
    .p1_out(sb_p1),
    .prog_a(sb_prog_a),
    .prog_q(sb_prog_q),
    .data_a(sb_data_a),
    .data_q(sb_data_q),
    .mcs48bus_0_i(mcs48bus_0_i),
    .mcs48bus_0_o(mcs48bus_0_o),
    .sp0250_0_i(sp0250_0_i),
    .sp0250_0_o(sp0250_0_o),
    .audio(sb_audio)
);

galaxian_sndcpu checkman_snd
(
    .clk(clk),
    .reset(reset | ~snd_board),
    .mode(bflags3[1]),
    .pause(pause),
    .cmd_wr(gal_cmd_wr),
    .cmd(gal_cpu_dout),
    .vblank_irq(gal_vbl_irq),
    .line8_irq(gal_line8_irq),
    .z80sed_1_i(sc_z80sed_1_i),
    .z80sed_1_o(z80sed_1_o),
    .ay_0_i(sc_ay_0_i),
    .ay_0_o(ay_0_o),
    .rom0_a(sc_r0a),
    .rom0_d(rom0_d),
    .pr_i(sc_pr_i),
    .pr_o(pool_o)
);

wire       vt_gb0_we, vt_gb1_we;
wire [7:0] vt_gb_d;

galaxian_vtsnd videotron_snd
(
    .clk(clk),
    .reset(reset | ~vt),
    .pause(pause),
    .cmd_wr(gal_cmd_wr),
    .cmd(gal_cpu_dout),
    .vblank_irq(gal_vbl_irq),
    .gb1_we(vt_gb1_we),
    .gb0_we(vt_gb0_we),
    .gb_d(vt_gb_d),
    .z80sed_1_i(vt_z80sed_1_i),
    .z80sed_1_o(z80sed_1_o),
    .ay_0_i(vt_ay_0_i),
    .ay_0_o(ay_0_o),
    .rom0_a(vt_r0a),
    .rom0_d(rom0_d),
    .pr_i(vt_pr_i),
    .pr_o(pool_o)
);

galaxian_cclimb_snd mshuttle_snd
(
    .clk(clk),
    .reset(reset | ~msh),
    .pause(pause),
    .trigger(gal_msh_trig),
    .rate(gal_msh_rate),
    .volume(gal_msh_vol),
    .start_addr(ay_0_ioa),
    .loop_addr(ay_0_iob),
    .rom_a(msh_rom_a),
    .rom_q(samp_q),
    .out(samp_out)
);

galaxian_kbsnd kingball_snd
(
    .clk(clk),
    .reset(reset | ~kb),
    .pause(pause),
    .latch(gal_kb_latch),
    .z80sed_1_i(kb_z80sed_1_i),
    .z80sed_1_o(z80sed_1_o),
    .rom0_a(kb_r0a),
    .rom0_d(rom0_d),
    .dac(kb_dac)
);

galaxian_konami_snd konami_snd
(
    .clk(clk),
    .reset(reset | ~ko),
    .two_ay(bflags5[1]),
    .fr_timer(bflags5[5]),
    .timer_9000(bflags5[6]),
    .no_filter(bflags7[0]),
    .hb_map(bflags7[1]),
    .rom12k(bflags7[2]),
    .hs_map(hsk & ~bflags12[7]),
    .sdm(hsk & bflags12[7]),
    .irq_set(gal_snd_irq),
    .pause(pause),
    .latch_we(gal_snd_cmd_we),
    .latch_d(gal_ppi_din),
    .control(gal_snd_ctl),
    .z80sed_1_i(ko_z80sed_1_i),
    .z80sed_1_o(z80sed_1_o),
    .ay_2_i(ay_2_i),
    .ay_2_o(ay_2_o),
    .ay_3_i(ay_3_i),
    .ay_3_o(ay_3_o),
    .ay_4_i(ay_4_i),
    .ay_4_o(ay_4_o),
    .tmsprom_0_i(tmsprom_0_i),
    .tmsprom_0_o(tmsprom_0_o),
    .tms5110_0_i(tms5110_0_i),
    .tms5110_0_o(tms5110_0_o),
    .digitalker_0_i(digitalker_0_i),
    .digitalker_0_o(digitalker_0_o),
    .rom0_a(ko_r0a),
    .rom0_d(rom0_d),
    .pr_i(ko_pr_i),
    .pr_o(pool_o),
    .rom_addr(ioctl_addr[13:0]),
    .rom_data(ioctl_dout),
    .rom_swap01(bflags5[2]),
    .swap4k(fmc),
    .scorpion(scp | hm),
    .harem(hm),
    .ad2083(ad),
    .tms_prom_we(ioctl_wr0 & tmsp_cs),
    .out(konami_audio)
);

/////////////////////////////  Sound mix  /////////////////////////////

assign disc_audio = sbh ? sbs_audio : gal_audio;

wire [9:0]  ay_sum  = {2'b00, ay_0_a} + {2'b00, ay_0_b} + {2'b00, ay_0_c} + {2'b00, samp_out} + {2'b00, kb_dac, kb_dac};
wire [10:0] ay_sum2 = {1'b0, ay_sum} + {3'b000, ay_1_o.a} + {3'b000, ay_1_o.b} + {3'b000, ay_1_o.c};
reg  [9:0] dc_div = 10'd0;
always @(posedge clk) dc_div <= dc_div + 10'd1;

jt49_dcrm2 #(.sw(16)) ay_dcrm
(
    .clk(clk),
    .cen(dc_div == 10'd0),
    .rst(reset),
    .din(bflags4[3] ? {1'b0, ay_sum2, 4'd0} : {1'b0, ay_sum, 5'd0}),
    .dout(ay_audio)
);

wire signed [10:0] sn_out = sn76489_0_o.sound;

wire signed [17:0] mix = (bflags2[1] ? 18'sd0 : {{2{disc_audio[15]}}, disc_audio}) + {{2{ay_audio[15]}}, ay_audio} +
                         {{2{konami_audio[15]}}, konami_audio} + {{3{sn_out[10]}}, sn_out, 4'd0} +
                         {{2{sb_audio[15]}}, sb_audio};
assign audio = mix > 18'sd32767 ? 16'sd32767 : mix < -18'sd32767 ? -16'sd32767 : mix[15:0];

endmodule
