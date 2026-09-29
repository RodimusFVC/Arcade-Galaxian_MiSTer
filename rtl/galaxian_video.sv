//============================================================================
//
//  Galaxian video: tilemap, sprites, shells/missile, stars
//
//  Line buffer / tile merge logic from "FPGA GALAXIAN" by Katsumi Degawa
//  (c) 2004; timing per the MAME galaxian_v.cpp hardware notes (Aaron Giles).
//
//============================================================================

module galaxian_video
(
    input               clk,            // 49.152 MHz
    input         [2:0] ph,             // 8 clocks per pixel, counters step when ph == 0
    input         [8:0] hcnt,           // 080-1FF, active area 100-1FF
    input         [8:0] vcnt,           // 0F8-1FF, visible 110-1EF

    input               flip_x,
    input               flip_y,
    input               crt_flip,       // mirrors shells/missile, which the flip latches do not move in X
    input               stars_on,
    input               bullet_mode,    // 0 Galaxian (4 px, white shells + yellow missile), 1 Scramble (2 px, yellow)
    input               rgb_gbr,        // wiring harness RGB -> GBR (Eagle)
    input         [3:0] ext_mode,       // code extension: 0 none, 1 Moon Cresta, 2 Moon Quasar, 3 Pisces,
                                        // 4 upper sprites (Kong), 5 Batman Part 2, 6 Moon Shuttle sprites, 7 Jump Bug,
                                        // 8 sprites from the upper half of the planes (separate sprite ROM, Zig Zag)
    input         [3:0] vflags2,        // [0] second sprite generator (objram 60-7F), [1] shells at objram C0,
                                        // [2] no shells, [3] sprite RAM page per 64 lines (Time Fighter)
    input         [3:0] vflags3,        // Frogger: [0] scroll and sprite Y nibbles swapped, [1] colour rotated right,
                                        // [2] blue (47) background on one half, [3] second gfx plane D0 / D1 swapped
                                        // (undone on reads: the config arrives after the ROM download)
    input         [3:0] gfxbank,        // bank 0 (D1-D0), bank 1, bank 2
    input               gfxbank4,       // Jump Bug bank 4
    input               stars_232,      // no stars from H = 232 on (Jump Bug status area)

    // CPU side
    input         [9:0] cpu_addr,
    input         [7:0] cpu_dout,
    input               vram_we,
    input               obj_we,
    output        [7:0] vram_q,
    output        [7:0] obj_q,

    // ROM load (ioctl index 0)
    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               gfx0_we,        // gfx region first half
    input               gfx1_we,        // gfx region second half
    input               pal_we,

    output              n3a,            // star LFSR N3A: the sound noise source (7474 at 2D)

    output reg    [7:0] r = 8'd0,
    output reg    [7:0] g = 8'd0,
    output reg    [7:0] b = 8'd0
);

// MAME resistor weights (1K/470/220 with 470 pull-down, RGB_MAXIMUM 224); stars at 150/100 ohm
localparam [63:0] RG_LUT = {8'd224, 8'd195, 8'd162, 8'd133, 8'd91, 8'd62, 8'd29, 8'd0};
localparam [31:0] B_LUT  = {8'd217, 8'd148, 8'd69, 8'd0};
localparam [31:0] ST_LUT = {8'd255, 8'd214, 8'd194, 8'd0};

wire [7:0] x = hcnt[7:0];
wire [7:0] y = vcnt[7:0];
wire active  = hcnt[8];

//----------------------------------------------------------- Memories ---------------------------------------------------------//

reg  [9:0] vr_addr;
wire [7:0] vr_q;

dpram_dc #(.widthad_a(10)) vram
(
    .clock_a(clk), .address_a(cpu_addr), .data_a(cpu_dout), .wren_a(vram_we), .q_a(vram_q),
    .clock_b(clk), .address_b(vr_addr), .q_b(vr_q)
);

// object RAM twice: one copy for the tile scroll/colour fetch, one for sprite and shell setup; 1K on the CPU side
// (Crazy Kong, Fantastic), Time Fighter pages its sprites through all of it
reg  [7:0] ot_addr;
reg  [9:0] os_addr;
wire [7:0] ot_q, os_q;

dpram_dc #(.widthad_a(10)) objram_t
(
    .clock_a(clk), .address_a(cpu_addr), .data_a(cpu_dout), .wren_a(obj_we), .q_a(obj_q),
    .clock_b(clk), .address_b({2'b00, ot_addr}), .q_b(ot_q)
);

dpram_dc #(.widthad_a(10)) objram_s
(
    .clock_a(clk), .address_a(cpu_addr), .data_a(cpu_dout), .wren_a(obj_we),
    .clock_b(clk), .address_b(os_addr), .q_b(os_q)
);

// gfx planes: port A = ROM load / sprite fetch, port B = tile fetch
reg  [12:0] gs_addr, gt_addr;
wire  [7:0] g0s_q, g1s_q, g0t_q, g1t_q;
wire  [7:0] g1s_raw, g1t_raw;
wire [12:0] ga = gfx0_we | gfx1_we ? ioctl_addr[12:0] : gs_addr;

dpram_dc #(.widthad_a(13)) gfx0
(
    .clock_a(clk), .address_a(ga), .data_a(ioctl_dout), .wren_a(gfx0_we), .q_a(g0s_q),
    .clock_b(clk), .address_b(gt_addr), .q_b(g0t_q)
);

dpram_dc #(.widthad_a(13)) gfx1
(
    .clock_a(clk), .address_a(ga), .data_a(ioctl_dout), .wren_a(gfx1_we), .q_a(g1s_raw),
    .clock_b(clk), .address_b(gt_addr), .q_b(g1t_raw)
);

assign g1s_q = vflags3[3] ? {g1s_raw[7:2], g1s_raw[0], g1s_raw[1]} : g1s_raw;
assign g1t_q = vflags3[3] ? {g1t_raw[7:2], g1t_raw[0], g1t_raw[1]} : g1t_raw;

reg [7:0] pal[32];
always @(posedge clk) if (pal_we) pal[ioctl_addr[4:0]] <= ioctl_dout;

// sprite line buffer: {pen[1:0], colour[2:0]}
// 8 bits wide: dpram_dc's byteena is width_a/8 bits, so narrower widths fail to elaborate in Quartus
reg  [7:0] lb_addr;
reg  [4:0] lb_data;
reg        lb_we = 1'b0;
wire [4:0] lb_q;
wire [7:0] lb_q8;
assign     lb_q = lb_q8[4:0];

dpram_dc #(.widthad_a(8)) linebuf
(
    .clock_a(clk), .address_a(lb_addr), .data_a({3'b000, lb_data}), .wren_a(lb_we), .q_a(lb_q8),
    .clock_b(clk)
);

// second sprite generator's line buffer (Zig Zag, Fantastic, Time Fighter)
reg  [7:0] lb2_addr;
reg  [4:0] lb2_data;
reg        lb2_we = 1'b0;
wire [7:0] lb2_q8;
wire [4:0] lb2_q = lb2_q8[4:0];

dpram_dc #(.widthad_a(8)) linebuf2
(
    .clock_a(clk), .address_a(lb2_addr), .data_a({3'b000, lb2_data}), .wren_a(lb2_we), .q_a(lb2_q8),
    .clock_b(clk)
);

//---------------------------------------------------------- Tilemap -----------------------------------------------------------//

// Fetched during the first pixel of each 8-pixel group for the next group: scroll (even objram byte) and colour
// (odd byte) of the column, then the tile code, then both planes of the tile row.

// tile code extensions (MAME *_extend_tile_info); attr = the column's colour byte
function [9:0] tile_code(input [7:0] code, input [7:0] attr);
    case (ext_mode)
        4'd1:    tile_code = gfxbank[3] && code[7:6] == 2'b10 ? {2'b01, gfxbank[2], gfxbank[0], code[5:0]} : {2'b00, code};
        4'd2:    tile_code = {1'b0, attr[5], code};
        4'd3:    tile_code = {gfxbank[1:0], code};
        4'd5:    tile_code = {1'b0, code[7] & gfxbank[0], code};
        4'd7:    tile_code = gfxbank[3] && code[7:6] == 2'b10 ?
                             {2'b00, code} + 10'd128 + {3'd0, gfxbank[0], 6'd0} + {2'd0, gfxbank[2], 7'd0} +
                             {1'b0, ~gfxbank4, 8'd0} : {2'b00, code};
        default: tile_code = {2'b00, code};
    endcase
endfunction

reg  [7:0] cur_p0 = 8'd0, cur_p1 = 8'd0, nxt_p0 = 8'd0, nxt_p1 = 8'd0;
reg  [2:0] cur_col = 3'd0, nxt_col = 3'd0;
reg  [2:0] t_line;
wire [7:0] xn    = {x[7:3] + 5'd1, 3'b000} ^ {8{flip_x}};
wire [7:0] vf    = y ^ {8{flip_y}};
// Frogger: the scroll byte's nibbles are swapped entering the adder; colours rotate right by one
wire [7:0] ot_sc = vflags3[0] ? {ot_q[3:0], ot_q[7:4]} : ot_q;
wire [7:0] t_sum = vf + ot_sc;
function [2:0] col_fix(input [2:0] c);
    col_fix = vflags3[1] ? {c[0], c[2:1]} : c;
endfunction

always @(posedge clk) begin
    if (x[2:0] == 3'd0) begin
        case (ph)
            3'd1: ot_addr <= {2'b00, xn[7:3], 1'b0};
            3'd2: ot_addr <= {2'b00, xn[7:3], 1'b1};
            3'd3: begin vr_addr <= {t_sum[7:3], xn[7:3]}; t_line <= t_sum[2:0]; end
            3'd4: nxt_col <= col_fix(ot_q[2:0]);
            3'd5: gt_addr <= {tile_code(vr_q, ot_q), t_line};
            3'd7: begin nxt_p0 <= g0t_q; nxt_p1 <= g1t_q; end
            default: ;
        endcase
    end
    if (ph == 3'd0 && x[2:0] == 3'd7) begin
        cur_p0  <= nxt_p0;
        cur_p1  <= nxt_p1;
        cur_col <= nxt_col;
    end
end

wire [2:0] t_bit = ~(x[2:0] ^ {3{flip_x}});
wire [1:0] t_pen = {cur_p0[t_bit], cur_p1[t_bit]};

//---------------------------------------------------------- Sprites -----------------------------------------------------------//

// HBLANK (H 080-0FF): sprite n is set up from H = 080 + 16n with the live V count (V steps at H = 0B0, so sprites
// 0-2 match the previous line) and rendered into the line buffer during H = 088 + 16n .. 097 + 16n. Sprite 7 runs
// 8 pixels into the active area: the write gate is 256H latched at /LD (Degawa). Shell/missile n shares the slot.
wire       blank_h = ~active;
wire [2:0] sn      = x[6:4];
wire [7:0] s_vf    = y ^ {8{flip_y}};

reg  [7:0] s_sum;
reg  [5:0] s_code;
reg        s_fx, s_fy, s_hit;
reg  [2:0] s_color;
reg  [7:0] s_attr;
reg  [7:0] s_x;
reg  [7:0] sp0h0, sp0h1, sp1h0, sp1h1;

reg        r_hit = 1'b0, r_fx;
reg  [2:0] r_color;
reg  [7:0] r_x;
reg  [7:0] rp0h0, rp0h1, rp1h0, rp1h1;

reg        shell_v = 1'b0, missile_v = 1'b0;
reg  [7:0] shell_x, missile_x, b_y;

wire [3:0] s_row = s_sum[3:0] ^ {4{s_fy}};

// sprite code extensions (MAME *_extend_sprite_info); attr = the sprite's colour byte
function [7:0] spr_ext(input [5:0] code, input [7:0] attr);
    case (ext_mode)
        4'd1:    spr_ext = gfxbank[3] && code[5:4] == 2'b10 ? {2'b01, gfxbank[2], gfxbank[0], code[3:0]} : {2'b00, code};
        4'd2:    spr_ext = {1'b0, attr[5], code};
        4'd3:    spr_ext = {gfxbank[1:0], code};
        4'd4,
        4'd5:    spr_ext = {2'b01, code};
        4'd6:    spr_ext = {attr[5:4], code};
        4'd7:    spr_ext = gfxbank[3] && code[5:4] == 2'b10 ?
                           {2'b00, code} + 8'd32 + {3'd0, gfxbank[0], 4'd0} + {2'd0, gfxbank[2], 5'd0} +
                           {1'b0, ~gfxbank4, 6'd0} : {2'b00, code};
        4'd8:    spr_ext = {2'b10, code};
        default: spr_ext = {2'b00, code};
    endcase
endfunction

wire [7:0] spr_code = spr_ext(s_code, s_attr);

// sprite RAM page (Time Fighter: MAME sprites_base = 40 | ((vpos + 16) << 2 & 300)) and the shell base
wire [7:0] y16   = y + 8'd16;
wire [1:0] spage = vflags2[3] ? y16[7:6] : 2'b00;
wire [2:0] shb   = vflags2[1] ? 3'b110 : 3'b011;

// second generator: objram 60-7F set up in slot 4, graphics in slot 5, same render timing
reg  [7:0] s2_sum;
reg  [5:0] s2_code;
reg        s2_fx, s2_fy, s2_hit;
reg  [2:0] s2_color;
reg  [7:0] s2_attr, s2_x;
reg  [7:0] s2p0h0, s2p0h1, s2p1h0, s2p1h1;
reg        r2_hit = 1'b0, r2_fx;
reg  [2:0] r2_color;
reg  [7:0] r2_x;
reg  [7:0] r2p0h0, r2p0h1, r2p1h0, r2p1h1;

wire [3:0] s2_row   = s2_sum[3:0] ^ {4{s2_fy}};
wire [7:0] spr2_code = spr_ext(s2_code, s2_attr);

always @(posedge clk) begin
    if (blank_h && x[7]) begin
        case (x[3:0])
            4'd0: case (ph)
                3'd1: os_addr <= {spage, 3'b010, sn, 2'd0};
                3'd2: os_addr <= {spage, 3'b010, sn, 2'd1};
                3'd3: begin os_addr <= {spage, 3'b010, sn, 2'd2}; s_sum <= s_vf + (vflags3[0] ? {os_q[3:0], os_q[7:4]} : os_q); end
                3'd4: begin os_addr <= {spage, 3'b010, sn, 2'd3}; s_code <= os_q[5:0]; s_fx <= os_q[6]; s_fy <= os_q[7]; end
                3'd5: begin s_color <= col_fix(os_q[2:0]); s_attr <= os_q; end
                3'd6: begin s_x <= os_q; s_hit <= s_sum[7:4] == 4'hF; end
                default: ;
            endcase
            4'd1: case (ph)
                3'd1: gs_addr <= {spr_code, s_row[3], 1'b0, s_row[2:0]};
                3'd2: gs_addr <= {spr_code, s_row[3], 1'b1, s_row[2:0]};
                3'd3: begin sp0h0 <= g0s_q; sp1h0 <= g1s_q; end
                3'd4: begin sp0h1 <= g0s_q; sp1h1 <= g1s_q; end
                default: ;
            endcase
            // shell/missile n: Y match on V + objram[61 + 4n], X from objram[63 + 4n]; the last matching shell wins
            4'd2: case (ph)
                3'd1: os_addr <= {2'b00, shb, sn, 2'd1};
                3'd2: os_addr <= {2'b00, shb, sn, 2'd3};
                3'd3: b_y <= s_vf + os_q;
                3'd4: if (b_y == 8'hFF && !vflags2[2]) begin
                          if (sn == 3'd7) begin missile_v <= 1'b1; missile_x <= os_q; end
                          else            begin shell_v   <= 1'b1; shell_x   <= os_q; end
                      end
                default: ;
            endcase
            4'd4: case (ph)
                3'd1: os_addr <= {spage, 3'b011, sn, 2'd0};
                3'd2: os_addr <= {spage, 3'b011, sn, 2'd1};
                3'd3: begin os_addr <= {spage, 3'b011, sn, 2'd2}; s2_sum <= s_vf + os_q; end
                3'd4: begin os_addr <= {spage, 3'b011, sn, 2'd3}; s2_code <= os_q[5:0]; s2_fx <= os_q[6]; s2_fy <= os_q[7]; end
                3'd5: begin s2_color <= os_q[2:0]; s2_attr <= os_q; end
                3'd6: begin s2_x <= os_q; s2_hit <= s2_sum[7:4] == 4'hF && vflags2[0]; end
                default: ;
            endcase
            4'd5: case (ph)
                3'd1: gs_addr <= {spr2_code, s2_row[3], 1'b0, s2_row[2:0]};
                3'd2: gs_addr <= {spr2_code, s2_row[3], 1'b1, s2_row[2:0]};
                3'd3: begin s2p0h0 <= g0s_q; s2p1h0 <= g1s_q; end
                3'd4: begin s2p0h1 <= g0s_q; s2p1h1 <= g1s_q; end
                default: ;
            endcase
            default: ;
        endcase
    end
    if (ph == 3'd1 && blank_h && x == 8'h80) begin shell_v <= 1'b0; missile_v <= 1'b0; end
    if (ph == 3'd0 && blank_h && x[7] && x[3:0] == 4'h7) begin
        r_hit <= s_hit; r_fx <= s_fx; r_color <= s_color; r_x <= s_x;
        rp0h0 <= sp0h0; rp0h1 <= sp0h1; rp1h0 <= sp1h0; rp1h1 <= sp1h1;
        r2_hit <= s2_hit; r2_fx <= s2_fx; r2_color <= s2_color; r2_x <= s2_x;
        r2p0h0 <= s2p0h0; r2p0h1 <= s2p0h1; r2p1h0 <= s2p1h0; r2p1h1 <= s2p1h1;
    end
end

// render: sprite (x - 088) >> 4, pixel i = x[3:0] ^ 8
wire       rend  = blank_h ? x >= 8'h88 : x < 8'h08;
wire [3:0] ri    = x[3:0] ^ 4'd8;
wire [3:0] rc    = ri ^ {4{r_fx}};
wire [2:0] rbit  = ~rc[2:0];
wire [1:0] r_pen = rc[3] ? {rp0h1[rbit], rp1h1[rbit]} : {rp0h0[rbit], rp1h0[rbit]};
wire [7:0] wa    = r_x + {4'd0, ri};
wire [3:0] rc2   = ri ^ {4{r2_fx}};
wire [2:0] rbit2 = ~rc2[2:0];
wire [1:0] r2_pen = rc2[3] ? {r2p0h1[rbit2], r2p1h1[rbit2]} : {r2p0h0[rbit2], r2p1h0[rbit2]};
wire [7:0] wa2   = r2_x + {4'd0, ri};

// Degawa: a pen only lands where the buffer pen is 0; a colour bit only sets while the other buffered colour bits are 0
function [4:0] lb_merge(input [4:0] buf_v, input [1:0] pen, input [2:0] col);
    reg [1:0] bp;
    reg [2:0] bc;
    reg       any;
    begin
        bp  = buf_v[4:3];
        bc  = buf_v[2:0];
        any = |pen;
        lb_merge[3]  = bp[0] | (pen[0] & ~bp[1]);
        lb_merge[4]  = bp[1] | (pen[1] & ~bp[0]);
        lb_merge[0]  = bc[0] | (any & col[0] & ~bc[1] & ~bc[2]);
        lb_merge[1]  = bc[1] | (any & col[1] & ~bc[2] & ~bc[0]);
        lb_merge[2]  = bc[2] | (any & col[2] & ~bc[0] & ~bc[1]);
    end
endfunction

// line buffer: the active area reads (x - 1, or 254 - x flipped) and clears in phases 1-3, sprites read-modify-write
// in phases 4-6
wire [7:0] ra = flip_x ? 8'd254 - x : x - 8'd1;
reg  [4:0] spr, spr2;

always @(posedge clk) begin
    case (ph)
        3'd1: begin lb_addr <= ra; lb2_addr <= ra; end
        3'd3: begin
            spr  <= lb_q;  lb_data  <= 5'd0; lb_we  <= active;
            spr2 <= lb2_q; lb2_data <= 5'd0; lb2_we <= active;
        end
        3'd4: begin lb_addr <= wa; lb_we <= 1'b0; lb2_addr <= wa2; lb2_we <= 1'b0; end
        3'd6: begin
            lb_data  <= lb_merge(lb_q, r_pen, r_color);     lb_we  <= rend & r_hit & |wa[7:4];
            lb2_data <= lb_merge(lb2_q, r2_pen, r2_color);  lb2_we <= rend & r2_hit & |wa2[7:4];
        end
        default: begin lb_we <= 1'b0; lb2_we <= 1'b0; end
    endcase
end

//----------------------------------------------------------- Stars ------------------------------------------------------------//

// 17-bit LFSR clocked twice per active pixel on every line but VSYNC; unflipped, 6B holds off the first two clocks
reg  [16:0] sr = 17'd0;
reg   [1:0] sr_hold = 2'd0;
wire [16:0] sr_n = {sr[12] ^ ~sr[0], sr[16:1]};
wire        vsync = ~vcnt[8];
assign      n3a   = ~sr[0];

function [6:0] star(input [16:0] s);      // {enable, colour}
    star = {(s & 17'h1FE01) == 17'h1FE00, ~s[8:3]};
endfunction

reg [6:0] star_a, star_b;

always @(posedge clk) begin
    if (!stars_on) sr <= 17'd0;
    else if (active && !vsync && (ph == 3'd2 || ph == 3'd5)) begin
        if (sr_hold != 2'd2 && !flip_x) sr_hold <= sr_hold + 2'd1;
        else sr <= sr_n;
    end
    if (vsync) sr_hold <= 2'd0;
    if (ph == 3'd1) begin star_a <= star(sr); star_b <= star(sr_n); end
end

//----------------------------------------------------------- Output -----------------------------------------------------------//

// tile / sprite merge through the same gates as the line buffer write (Degawa W_VID / W_COL)
// the second generator is drawn over the first and the tiles (MAME renders it last)
wire [4:0] mix = spr2[4:3] != 2'b00 ? spr2 : lb_merge(spr, t_pen, cur_col);
wire [1:0] pen = mix[4:3];
wire [7:0] pv  = pal[{mix[2:0], pen}];

wire [7:0] bx = crt_flip ? 8'd255 - x : x;
wire [8:0] shell_d   = {1'b0, bx} + {1'b0, shell_x}   - 9'd251;
wire [8:0] missile_d = {1'b0, bx} + {1'b0, missile_x} - 9'd251;
wire       shell_on   = shell_v   & (bullet_mode ? (shell_d == 9'h1FE || shell_d == 9'h1FF) : shell_d < 9'd4);
wire       missile_on = missile_v & (bullet_mode ? (missile_d == 9'h1FE || missile_d == 9'h1FF) : missile_d < 9'd4);

wire       st_en  = (y[0] ^ flip_y) ^ (x[3] ^ flip_x);
wire [6:0] st     = star_b[6] ? star_b : star_a;
wire       st_on  = stars_on & st_en & st[6] & ~(stars_232 & bx >= 8'd232);

// Frogger river: blue left of H = 128 (right of it when flipped), per MAME frogger_draw_background
wire bg_blue = vflags3[2] & (flip_x ? x >= 8'd128 : x < 8'd128);

reg [23:0] rgb;
always @(*) begin
    if (missile_on)                  rgb = 24'hFFFF00;
    else if (shell_on)               rgb = bullet_mode ? 24'hFFFF00 : 24'hFFFFFF;
    else if (pen != 2'd0)            rgb = {RG_LUT[pv[2:0]*8 +: 8], RG_LUT[pv[5:3]*8 +: 8], B_LUT[pv[7:6]*8 +: 8]};
    else if (st_on)                  rgb = {ST_LUT[{st[4], st[5]}*8 +: 8], ST_LUT[{st[2], st[3]}*8 +: 8], ST_LUT[{st[0], st[1]}*8 +: 8]};
    else if (bg_blue)                rgb = 24'h000047;
    else                             rgb = 24'd0;
end

// the Eagle harness sits on the monitor lines, so it swaps stars and shells as well (MAME swaps the palette only)
always @(posedge clk) begin
    if (ph == 3'd0) {r, g, b} <= rgb_gbr ? {rgb[15:0], rgb[23:16]} : rgb;
end

endmodule
