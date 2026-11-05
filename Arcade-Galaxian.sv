//============================================================================
//
//  Galaxian hardware for MiSTer
//  Copyright (C) 2026 Rodimus
//
//  Board model derived from "FPGA GALAXIAN" by Katsumi Degawa (c) 2004 and
//  the MiSTer Galaxian port by Sorgelig
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

wire        CLK_49M;
wire        locked;
wire [127:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [10:0] ps2_key;
wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_din;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire [15:0] joystick_0, joystick_1;
wire [15:0] joy_la0, joy_la1, joy_ra0, joy_ra1;
wire  [8:0] spinner_0;
wire [24:0] ps2_mouse;
wire [21:0] gamma_bus;
wire        direct_video;
wire        video_rotated;
wire        pause_cpu;
wire        hblank, vblank;

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire signed [15:0] audio;
wire signed [26:0] mv_a   = {{11{audio[15]}}, audio};
wire signed [26:0] mv_181 = (mv_a <<< 7) + (mv_a <<< 5) + (mv_a <<< 4) + (mv_a <<< 2) + mv_a;
reg  signed [26:0] mv_p;
always @(*) begin
	case (status[48:46])
		3'd1:    mv_p = mv_181;
		3'd2:    mv_p = mv_a <<< 7;
		3'd3:    mv_p = mv_a <<< 6;
		3'd4:    mv_p = mv_181 <<< 1;
		3'd5:    mv_p = mv_a <<< 9;
		default: mv_p = mv_a <<< 8;
	endcase
end
wire signed [26:0] mv_s   = mv_p >>> 8;
wire signed [15:0] audio_mv = mv_s > 27'sd32767 ? 16'sd32767 : mv_s < -27'sd32768 ? -16'sd32768 : mv_s[15:0];
assign AUDIO_L = pause_cpu ? 16'd0 : audio_mv;
assign AUDIO_R = pause_cpu ? 16'd0 : audio_mv;
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS = 0;

reg [7:0] game_var    = 8'd0;
reg [7:0] game_flags  = 8'h90;
reg [7:0] game_flags2 = 8'd0;

// dsnd_engine program (MRA index 5, after index 1): present -> the engine's output is heard
reg ds_on = 1'b0;
always @(posedge CLK_49M) if (ioctl_wr) begin
    if (ioctl_index == 8'd1 && ioctl_addr == 25'd0) ds_on <= 1'b0;
    if (ioctl_index == 8'd5) ds_on <= 1'b1;
end
reg [7:0] vid_flags  = 8'd0;
reg [7:0] brd_flags  = 8'd0;
reg [7:0] rom_top    = 8'd0;
reg [7:0] ext_mode   = 8'd0;
reg [7:0] brd_flags2 = 8'd0;
reg [7:0] brd_flags3 = 8'd0;
reg [7:0] vid_flags2 = 8'd0;
reg [7:0] brd_flags4 = 8'd0;
reg [7:0] vid_flags3 = 8'd0;
reg [7:0] brd_flags5 = 8'd0;
reg [7:0] vid_flags4 = 8'd0;
reg [7:0] brd_flags6 = 8'd0;
reg [7:0] brd_flags7 = 8'd0;
reg [7:0] brd_flags8 = 8'd0;
reg [7:0] brd_flags9 = 8'd0;
reg [7:0] vid_flags5 = 8'd0;
reg [7:0] brd_flags10 = 8'd0;
reg [7:0] brd_flags11 = 8'd0;
reg [7:0] brd_flags12 = 8'd0;
reg [7:0] brd_flags13 = 8'd0;
reg [5:0] in_map[32];
reg [7:0] port_idle[4] = '{8'hFF,8'hFF,8'hFF,8'hFF};
reg [7:0] port_dip[4]  = '{8'h80,8'h80,8'h80,8'h80};
wire [5:0] map_idx  = ioctl_addr[5:0] - 6'd16;
wire [3:0] dip_idx4 = ioctl_addr[3:0] - 4'd10;

always @(posedge CLK_49M) begin
    if (ioctl_wr && ioctl_index == 8'd1) begin
        if (ioctl_addr == 25'd0) game_var    <= ioctl_dout;
        if (ioctl_addr == 25'd1) game_flags  <= ioctl_dout;
        if (ioctl_addr == 25'd3) game_flags2 <= ioctl_dout;
        if (ioctl_addr >= 25'd4  && ioctl_addr < 25'd8)  port_idle[ioctl_addr[1:0]] <= ioctl_dout;
        if (ioctl_addr >= 25'd10 && ioctl_addr < 25'd14) port_dip[dip_idx4[1:0]] <= ioctl_dout;
        if (ioctl_addr >= 25'd16 && ioctl_addr < 25'd48) in_map[map_idx[4:0]] <= ioctl_dout[5:0];
        if (ioctl_addr == 25'd64) vid_flags   <= ioctl_dout;
        if (ioctl_addr == 25'd65) brd_flags   <= ioctl_dout;
        if (ioctl_addr == 25'd66) rom_top     <= ioctl_dout;
        if (ioctl_addr == 25'd67) ext_mode    <= ioctl_dout;
        if (ioctl_addr == 25'd68) brd_flags2  <= ioctl_dout;
        if (ioctl_addr == 25'd69) brd_flags3  <= ioctl_dout;
        if (ioctl_addr == 25'd70) vid_flags2  <= ioctl_dout;
        if (ioctl_addr == 25'd71) brd_flags4  <= ioctl_dout;
        if (ioctl_addr == 25'd72) vid_flags3  <= ioctl_dout;
        if (ioctl_addr == 25'd73) brd_flags5  <= ioctl_dout;
        if (ioctl_addr == 25'd74) vid_flags4  <= ioctl_dout;
        if (ioctl_addr == 25'd75) brd_flags6  <= ioctl_dout;
        if (ioctl_addr == 25'd76) brd_flags7  <= ioctl_dout;
        if (ioctl_addr == 25'd77) brd_flags8  <= ioctl_dout;
        if (ioctl_addr == 25'd78) brd_flags9  <= ioctl_dout;
        if (ioctl_addr == 25'd79) vid_flags5  <= ioctl_dout;
        if (ioctl_addr == 25'd80) brd_flags10 <= ioctl_dout;
        if (ioctl_addr == 25'd81) brd_flags11 <= ioctl_dout;
        if (ioctl_addr == 25'd82) brd_flags12 <= ioctl_dout;
        if (ioctl_addr == 25'd83) brd_flags13 <= ioctl_dout;
    end
end

wire game_vert = game_flags[4];
wire vert_view = game_vert & ~status[12];

wire [1:0] ar = status[9:8];

assign VIDEO_ARX = (!ar) ? (vert_view ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (vert_view ? 12'd4 : 12'd3) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"GALAXIAN;;",
	"P1,Video Options;",
	"P1O89,Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	"P1OC,Orientation,Vert,Horz;",
	"P1OM,Flip Screen,Off,On;",
	"P1O[40:37],H Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[44:41],V Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1OGI,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"H1-;",
	"H1P2,Game Options;",
	"P2O[45],Mouse/Trackball,Off,On;",
	"-;",
	"P5,Game Audio;",
	"P5O[48:46],Master Volume,Factory,-3dB,-6dB,-12dB,+3dB,+6dB;",
	"-;",
	"P3,Pause Options;",
	"P3OJ,Pause when OSD is open,On,Off;",
	"P3OK,Dim video after 10s,On,Off;",
	"-;",
	"P4,High Score Options;",
	"P4OL,Autosave Hiscores,Off,On;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Button 1,Button 2,Button 3,Button 4,Coin,Start 1P,Start 2P,Pause,Button 5,Button 6,Rack Test;",
	"jn,A,B,X,Y,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_49M),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({~game_flags2[0], direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_l_analog_0(joy_la0),
	.joystick_l_analog_1(joy_la1),
	.joystick_r_analog_0(joy_ra0),
	.joystick_r_analog_1(joy_ra1),
	.spinner_0(spinner_0),
	.ps2_mouse(ps2_mouse),
	.ps2_key(ps2_key)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_49M),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(0),
	.mgmt_address(0),
	.mgmt_writedata(0),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

reg [2:0] ce_div = 3'd0;
always @(posedge CLK_49M) ce_div <= ce_div + 3'd1;
wire ce6 = (ce_div == 3'd0);

wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked;

wire [12:0] kb;
/* verilator lint_off PINCONNECTEMPTY */
ctl_keyboard u_kb(.clk(CLK_49M), .ps2_key(ps2_key), .pause(pause_cpu), .kb(kb), .kbx());
/* verilator lint_on PINCONNECTEMPTY */

wire [3:0] al1, al2, ar1_s, ar2_s;
ctl_stick_dirs #(.MODE(0), .THRESH(7'd40)) u_al1(.stick(joy_la0), .dir(al1));
ctl_stick_dirs #(.MODE(0), .THRESH(7'd40)) u_al2(.stick(joy_la1), .dir(al2));
ctl_stick_dirs #(.MODE(0), .THRESH(7'd40)) u_ar1(.stick(joy_ra0), .dir(ar1_s));
ctl_stick_dirs #(.MODE(0), .THRESH(7'd40)) u_ar2(.stick(joy_ra1), .dir(ar2_s));

reg         mouse_seen = 1'b0;
reg  [17:0] mj_div = 18'd0;
reg  signed [7:0] mj_x = 8'sd0, mj_y = 8'sd0;
wire        mouse_on = game_flags2[0] & status[45];
wire signed [8:0] mouse_dx = {ps2_mouse[4], ps2_mouse[15:8]};
wire signed [8:0] mouse_dy = {ps2_mouse[5], ps2_mouse[23:16]};

function signed [7:0] mj_step(input signed [7:0] p, input signed [8:0] d, input ev, input tick);
    reg signed [10:0] n;
    begin
        n = {{3{p[7]}}, p} + (ev ? {{2{d[8]}}, d} : 11'sd0);
        if (tick && n != 0) n = n[10] ? n + 11'sd1 : n - 11'sd1;
        mj_step = n > 11'sd48 ? 8'sd48 : n < -11'sd48 ? -8'sd48 : n[7:0];
    end
endfunction

always @(posedge CLK_49M) begin
    mj_div     <= mj_div + 18'd1;
    mouse_seen <= ps2_mouse[24];
    if (reset | ~mouse_on) begin
        mj_x <= 8'sd0;
        mj_y <= 8'sd0;
    end
    else begin
        mj_x <= mj_step(mj_x, mouse_dx, mouse_seen != ps2_mouse[24], mj_div == 18'd0);
        mj_y <= mj_step(mj_y, mouse_dy, mouse_seen != ps2_mouse[24], mj_div == 18'd0);
    end
end
wire [3:0] mouse_dir = {mj_y > 8'sd0, mj_y < 8'sd0, mj_x < 8'sd0, mj_x > 8'sd0};

wire [3:0] dir1_raw = {joystick_0[3] | kb[0], joystick_0[2] | kb[1], joystick_0[1] | kb[2], joystick_0[0] | kb[3]} |
                      al1 | mouse_dir;
wire [3:0] dir2_raw = joystick_1[3:0] | al2;
wire [3:0] dir1, dir2;

ctl_joy4way u_j4w1(.clk(CLK_49M), .en(game_flags[0]), .in(dir1_raw), .out(dir1));
ctl_joy4way u_j4w2(.clk(CLK_49M), .en(game_flags[0]), .in(dir2_raw), .out(dir2));

wire m_pause = joystick_0[11] | kb[12];

wire coin1, coin2;
ctl_coin_impulse #(.FRAMES(4'd2), .PAUSE_MODE(1)) u_coin1(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
                                          .coin_raw(joystick_0[8] | kb[8]), .coin(coin1));
ctl_coin_impulse #(.FRAMES(4'd2), .PAUSE_MODE(1)) u_coin2(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
                                          .coin_raw(joystick_1[8] | kb[9]), .coin(coin2));

wire rack_btn = joystick_0[14] | joystick_1[14];
wire rack_tog;
ctl_toggle u_rack(.clk(CLK_49M), .clear(ioctl_download), .btn(rack_btn), .pause(pause_cpu), .q(rack_tog));

reg [7:0] dip_sw[8] = '{8'hFF,8'hFF,8'hFF,8'hFF,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_49M) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

/* verilator lint_off UNUSED */
wire [35:0] ids;
/* verilator lint_on UNUSED */
ctl_ids u_ids
(
	.joy0(joystick_0), .joy1(joystick_1), .kb(kb), .dir1(dir1), .dir2(dir2),
	.coin1(coin1), .coin2(coin2), .coin3(1'b0), .ctl(ids)
);
wire [63:0] ctl =
{
	dip_sw[3],
	6'd0,
	joystick_1[5]  | ar2_s[1],
	joystick_1[4]  | ar2_s[0],
	joystick_0[5]  | ar1_s[1],
	joystick_0[4]  | ar1_s[0],
	joystick_1[13] | ar2_s[3],
	joystick_1[12] | ar2_s[2],
	joystick_1[7]  | ar2_s[1],
	joystick_1[6]  | ar2_s[0],
	joystick_0[13] | ar1_s[3],
	joystick_0[12] | ar1_s[2],
	joystick_0[7]  | ar1_s[1],
	joystick_0[6]  | ar1_s[0],
	rack_tog,
	rack_btn,
	ids[35:32],
	dip_sw[4],
	ids[23:0]
};

wire [255:0] in_map_flat;
wire [31:0]  port_idle_flat, port_sel_flat;
wire [63:0]  dip_bytes_flat;
genvar mi;
generate
	for (mi = 0; mi < 32; mi = mi + 1) begin : g_map
		assign in_map_flat[mi*8 +: 8] = {2'b00, in_map[mi]};
	end
	for (mi = 0; mi < 4; mi = mi + 1) begin : g_idle
		assign port_idle_flat[mi*8 +: 8] = port_idle[mi];
		assign port_sel_flat[mi*8 +: 8]  = port_dip[mi];
	end
	for (mi = 0; mi < 8; mi = mi + 1) begin : g_dip
		assign dip_bytes_flat[mi*8 +: 8] = dip_sw[mi];
	end
endgenerate
wire [31:0] ports;
ctl_port_map #(.NP(4), .IDW(6), .BASE_MODE(1)) u_ports
(
	.clk(CLK_49M), .idle(port_idle_flat), .in_map(in_map_flat), .dips(32'd0), .port_sel(port_sel_flat),
	.dip_bytes(dip_bytes_flat), .dip_bit(96'd0), .ctl(ctl), .ovr_mask(32'd0), .ovr_val(32'd0), .ports(ports)
);
wire [7:0] in_port[4];
genvar pi;
generate
	for (pi = 0; pi < 4; pi = pi + 1) begin : g_port
		assign in_port[pi] = ports[pi*8 +: 8];
	end
endgenerate

// Moon War dials: player 1 reversed in cocktail (IN2 bit 3), player 2 always reversed
reg        dial_vbl = 1'b0;
always @(posedge CLK_49M) dial_vbl <= vblank;
wire [7:0] dial1, dial2;
ctl_dial_mame u_dial1
(
	.clk(CLK_49M), .reset(reset), .pause(pause_cpu), .frame(vblank & ~dial_vbl), .sens(8'd32), .keyd(8'd4),
	.reverse(in_port[2][3]), .osd_sens(3'd0), .wheel(1'b0), .spinner(spinner_0), .mouse_ev(mouse_seen != ps2_mouse[24]),
	.mouse_d(mouse_dx), .stick(8'd0), .paddle(8'd0), .use_paddle(1'b0), .dec(dir1_raw[1]), .inc(dir1_raw[0]),
	.pos(dial1)
);
ctl_dial_mame u_dial2
(
	.clk(CLK_49M), .reset(reset), .pause(pause_cpu), .frame(vblank & ~dial_vbl), .sens(8'd32), .keyd(8'd4),
	.reverse(1'b1), .osd_sens(3'd0), .wheel(1'b0), .spinner(9'd0), .mouse_ev(1'b0), .mouse_d(9'd0), .stick(8'd0),
	.paddle(8'd0), .use_paddle(1'b0), .dec(dir2_raw[1]), .inc(dir2_raw[0]), .pos(dial2)
);

wire [15:0] hs_address;
wire  [7:0] hs_data_in;
wire  [7:0] hs_data_out;
wire        hs_write_enable;
wire        hs_access_read;
wire        hs_access_write;
wire        hs_pause;
wire        hs_configured;

wire [23:0] rgb_out;
pause #(8,8,8,49) pause
(
	.*,
	.clk_sys(CLK_49M),
	.user_button(m_pause),
	.pause_request(hs_pause & hs_configured),   // an MRA without hiscore config must never pause (and mute) the core
	.options(~status[20:19])
);

wire hs, vs;
wire [7:0] r, g, b;
wire ce_pix = ce6;

wire rotate_ccw = ~game_flags[7];
wire no_rotate  = ~game_vert | status[12] | direct_video;
wire flip       = 1'b0;
screen_rotate screen_rotate(.*);

arcade_video #(256,24) arcade_video
(
	.*,

	.clk_video(CLK_49M),

	.RGB_in(rgb_out),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[18:16])
);

galaxian_dispatcher dispatcher
(
	.clk(CLK_49M),
	.reset(reset),
	.ph(ce_div),
	.pause(pause_cpu),
	.variant(game_var),
	.vflags(vid_flags),
	.bflags(brd_flags),
	.bflags2(brd_flags2),
	.bflags3(brd_flags3),
	.vflags2(vid_flags2),
	.bflags4(brd_flags4),
	.vflags3(vid_flags3),
	.bflags5(brd_flags5),
	.vflags4(vid_flags4),
	.bflags6(brd_flags6),
	.bflags7(brd_flags7),
	.bflags8(brd_flags8),
	.bflags9(brd_flags9),
	.vflags5(vid_flags5),
	.bflags10(brd_flags10),
	.bflags11(brd_flags11),
	.bflags12(brd_flags12),
	.bflags13(brd_flags13),
	.rom_top(rom_top),
	.ext_mode(ext_mode),

	.in0(in_port[0]),
	.dial1(dial1),
	.dial2(dial2),
	.in1(in_port[1]),
	.in2(in_port[2]),
	.in3(in_port[3]),
	.dip4(dip_sw[4]),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr0(ioctl_wr & (ioctl_index == 8'd0)),
	.ds_wr(ioctl_wr & (ioctl_index == 8'd5)),
	.ds_on(ds_on),

	.crt_flip(status[22] ^ game_flags2[1]),
	.h_adj(status[40:37]),
	.v_adj(status[44:41]),

	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_hs(hs),
	.video_vs(vs),
	.video_hblank(hblank),
	.video_vblank(vblank),

	.audio(audio),

	.hs_address(hs_address),
	.hs_data_in(hs_data_in),
	.hs_data_out(hs_data_out),
	.hs_write(hs_write_enable & hs_configured)
);

hiscore #(
	.HS_ADDRESSWIDTH(16),
	.CFG_ADDRESSWIDTH(4),
	.CFG_LENGTHWIDTH(2)
) hi (
	.*,
	.clk(CLK_49M),
	.paused(pause_cpu),
	.autosave(status[21]),
	.ram_address(hs_address),
	.data_from_ram(hs_data_out),
	.data_to_ram(hs_data_in),
	.data_from_hps(ioctl_dout),
	.data_to_hps(ioctl_din),
	.ram_write(hs_write_enable),
	.ram_intent_read(hs_access_read),
	.ram_intent_write(hs_access_write),
	.pause_cpu(hs_pause),
	.configured(hs_configured)
);

endmodule
