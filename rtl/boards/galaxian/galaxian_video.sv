//  Line buffer / tile merge logic from "FPGA GALAXIAN" by Katsumi Degawa (c) 2004
//  Based on MAME galaxian_v.cpp (Aaron Giles, Couriersud, Robbbert, BSD-3-Clause)

module galaxian_video
(
    input               clk,
    input         [2:0] ph,
    input         [8:0] hcnt,
    input         [8:0] vcnt,

    input               flip_x,
    input               flip_y,
    input               crt_flip,       // mirrors shells / missile, which the flip latches do not move in X
    input               stars_on,
    input               pause,
    input               bullet_mode,
    input               rgb_gbr,
    input               gfx_packed,
    input               spr_hi,
    input               spr_ad,
    input         [3:0] ext_mode,
    input         [3:0] vflags2,        // [0] second sprite generator (objram 60-7F), [1] shells at objram C0,
    input         [7:0] vflags3,        // Frogger: [0] scroll and sprite Y nibbles swapped, [1] colour rotated right,
    input         [7:0] vflags4,
    input         [6:0] vflags5,
    input               bgp_we,
    input               bg_en,
    input         [2:0] bg_rgb,
    input         [3:0] gfxbank,
    input               gfxbank4,
    input               stars_232,

    input         [9:0] cpu_addr,
    input         [7:0] cpu_dout,
    input               vram_we,
    input               obj_we,
    output        [7:0] vram_q,
    output        [7:0] obj_q,

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               gfx0_we,
    input               gfx1_we,
    input               gfx2_we,
    input               gfxh_we,
    input               tb_we,
    input         [4:0] tb_addr,
    input         [2:0] tb_d,
    input         [7:0] col_bank,
    input               db,
    input         [7:0] db_bg,
    input         [7:0] db_split,
    input               bd_patch,
    input               pal_we,
    input               rcl,
    input         [8:0] rc_h,
    input         [7:0] rc_v,
    input        [10:0] rc_addr,
    input               rc_we,
    output        [7:0] rc_q,
    input               rcg_we,

    output ram_pool_pkg::pram_i_t [5:0] vr_i,
    input  ram_pool_pkg::pram_o_t [5:0] vr_o,
    output ram_pool_pkg::pram_i_t [3:0] gr_i,
    input  ram_pool_pkg::pram_o_t [3:0] gr_o,

    output              n3a,

    output reg    [7:0] r = 8'd0,
    output reg    [7:0] g = 8'd0,
    output reg    [7:0] b = 8'd0
);

localparam [63:0] RG_LUT = {8'd224, 8'd195, 8'd162, 8'd133, 8'd91, 8'd62, 8'd29, 8'd0};
localparam [31:0] B_LUT  = {8'd217, 8'd148, 8'd69, 8'd0};
localparam [31:0] ST_LUT = {8'd255, 8'd214, 8'd194, 8'd0};

wire [7:0] x = hcnt[7:0];
wire [7:0] y = vcnt[7:0];
wire active  = hcnt[8];

reg  [9:0] vr_addr;
wire [7:0] vr_q;

assign vr_i[0].a_addr = {6'd0, cpu_addr};
assign vr_i[0].a_d    = cpu_dout;
assign vr_i[0].a_we   = vram_we;
assign vr_i[0].b_addr = {6'd0, vr_addr};
assign vr_i[0].b_d    = 8'd0;
assign vr_i[0].b_we   = 1'b0;
assign vram_q = vr_o[0].a_q;
assign vr_q = vr_o[0].b_q;

reg  [7:0] ot_addr;
reg  [9:0] os_addr;
wire [7:0] ot_q, os_q;

assign vr_i[1].a_addr = {6'd0, cpu_addr};
assign vr_i[1].a_d    = cpu_dout;
assign vr_i[1].a_we   = obj_we;
assign vr_i[1].b_addr = {8'd0, ot_addr};
assign vr_i[1].b_d    = 8'd0;
assign vr_i[1].b_we   = 1'b0;
assign obj_q = vr_o[1].a_q;
assign ot_q = vr_o[1].b_q;

assign vr_i[2].a_addr = {6'd0, cpu_addr};
assign vr_i[2].a_d    = cpu_dout;
assign vr_i[2].a_we   = obj_we;
assign vr_i[2].b_addr = {6'd0, os_addr};
assign vr_i[2].b_d    = 8'd0;
assign vr_i[2].b_we   = 1'b0;
assign os_q = vr_o[2].b_q;

reg  [13:0] gs_addr, gt_addr;
wire  [7:0] g0s_q, g1s_q, g0t_q, g1t_q;
wire  [7:0] g1s_raw, g1t_raw;
function [12:0] gfx_remap(input [12:0] i);
    reg [12:0] j;
    begin
        j = i;
        if (db) j = {i[12:4], i[2:0], i[3]};
        else if (vflags4[4]) begin
            j = i & 13'h1A7F;
            j[7]  = i[3] ^ i[10];
            j[8]  = i[1] ^ i[7];
            j[10] = i[0] ^ i[8];
        end
        else if (vflags5[0]) begin
            j = i & 13'h1A7F;
            j[7]  = (i[1] & i[8]) | (~i[1] & i[10]);
            j[8]  = i[7] ^ (i[1] & (i[7] ^ i[10]));
            j[10] = (i[1] & i[7]) | (~i[1] & i[8]);
        end
        else if (vflags5[1]) begin
            j = i & 13'h19BF;
            j[6]  = i[4] ^ i[9] ^ (i[2] & i[10]);
            j[9]  = i[2] ^ i[10];
            j[10] = ~(i[0] ^ i[6]);
        end
        else if (vflags4[5]) begin
            j = i & 13'h1D5F;
            j[5] = i[3] ^ i[7];
            j[7] = i[2] ^ i[9] ^ (i[0] & i[5]) ^ (i[3] & i[7] & (i[0] ^ i[5]));
            j[9] = i[0] ^ i[5] ^ (i[3] & i[7]);
        end
        gfx_remap = j;
    end
endfunction

function [12:0] pk_addr(input [12:0] a, input hi);
    pk_addr = gfx_packed ? {1'b0, a[10:3], hi, a[2:0]} : a;
endfunction

wire [13:0] gs_rd = {gs_addr[13], gfx_remap(gs_addr[12:0])};
wire [13:0] gt_rd = {gt_addr[13], gfx_remap(gt_addr[12:0])};
wire        ld0 = gfx0_we | (gfxh_we & ~ioctl_addr[13]);
wire        ld1 = gfx1_we | (gfxh_we & ioctl_addr[13]);
wire [13:0] ga0 = ld0 | ld1 ? {gfxh_we, ioctl_addr[12:0]} : {gs_rd[13], pk_addr(gs_rd[12:0], 1'b1)};
wire [13:0] ga1 = ld0 | ld1 ? {gfxh_we, ioctl_addr[12:0]} : {gs_rd[13], pk_addr(gs_rd[12:0], 1'b0)};
wire  [7:0] g0s_raw, g0t_raw;

assign gr_i[0].a_addr = {2'b0, ga0};
assign gr_i[0].a_d    = ioctl_dout;
assign gr_i[0].a_we   = ld0;
assign gr_i[0].b_addr = {2'b0, gt_rd[13], pk_addr(gt_rd[12:0], 1'b1)};
assign gr_i[0].b_d    = 8'd0;
assign gr_i[0].b_we   = 1'b0;
assign g0s_raw = gr_o[0].a_q;
assign g0t_raw = gr_o[0].b_q;

assign gr_i[1].a_addr = {2'b0, ga1};
assign gr_i[1].a_d    = ioctl_dout;
assign gr_i[1].a_we   = ld1;
assign gr_i[1].b_addr = {2'b0, gt_rd[13], pk_addr(gt_rd[12:0], 1'b0)};
assign gr_i[1].b_d    = 8'd0;
assign gr_i[1].b_we   = 1'b0;
assign g1s_raw = gr_o[1].a_q;
assign g1t_raw = gr_o[1].b_q;

reg [2:0] tbank[32];
always @(posedge clk) if (tb_we) tbank[tb_addr] <= tb_d;

wire bpp3 = vflags4[7];
wire [7:0] g2s_q, g2t_q;
assign gr_i[2].a_addr = {4'd0, gfx2_we ? ioctl_addr[11:0] : gs_rd[11:0]};
assign gr_i[2].a_d    = ioctl_dout;
assign gr_i[2].a_we   = gfx2_we;
assign gr_i[2].b_addr = {4'd0, gt_rd[11:0]};
assign gr_i[2].b_d    = 8'd0;
assign gr_i[2].b_we   = 1'b0;
assign g2s_q = gr_o[2].a_q;
assign g2t_q = gr_o[2].b_q;

wire [7:0] g1s_sw = vflags3[3] ? {g1s_raw[7:2], g1s_raw[0], g1s_raw[1]} : g1s_raw;
wire [7:0] g1t_sw = vflags3[3] ? {g1t_raw[7:2], g1t_raw[0], g1t_raw[1]} : g1t_raw;
reg  [13:0] gs_rd_d, gt_rd_d;
always @(posedge clk) begin gs_rd_d <= gs_rd; gt_rd_d <= gt_rd; end
function bd_zero(input [13:0] a);
    bd_zero = a < 14'h0008 || (a >= 14'h1000 && a < 14'h10D8) || (a >= 14'h1180 && a < 14'h11D0);
endfunction
assign g0s_q = gfx_packed ? {g0s_raw[7:4], g1s_raw[7:4]} : bd_patch && bd_zero(gs_rd_d) ? 8'd0 : g0s_raw;
assign g1s_q = gfx_packed ? {g0s_raw[3:0], g1s_raw[3:0]} : g1s_sw;
assign g0t_q = gfx_packed ? {g0t_raw[7:4], g1t_raw[7:4]} : bd_patch && bd_zero(gt_rd_d) ? 8'd0 : g0t_raw;
assign g1t_q = gfx_packed ? {g0t_raw[3:0], g1t_raw[3:0]} : g1t_sw;

reg [7:0] pal[64];
always @(posedge clk) if (pal_we) pal[ioctl_addr[5:0]] <= ioctl_dout;
wire c4 = vflags5[6];

reg [3:0] bgp[128];
always @(posedge clk) if (bgp_we) bgp[ioctl_addr[6:0]] <= ioctl_dout[3:0];
wire mar = vflags4[6];

// 8 bits wide: dpram_dc's byteena is width_a/8 bits, so narrower widths fail to elaborate in Quartus
reg  [7:0] lb_addr;
reg  [4:0] lb_data;
reg        lb_c3 = 1'b0;
reg        lb_we = 1'b0;
wire [4:0] lb_q;
wire [7:0] lb_q8;
assign     lb_q = lb_q8[4:0];

assign vr_i[3].a_addr = {8'd0, lb_addr};
assign vr_i[3].a_d    = {2'b00, lb_c3, lb_data};
assign vr_i[3].a_we   = lb_we;
assign vr_i[3].b_addr = 16'd0;
assign vr_i[3].b_d    = 8'd0;
assign vr_i[3].b_we   = 1'b0;
assign lb_q8 = vr_o[3].a_q;

reg  [7:0] lb2_addr;
reg  [4:0] lb2_data;
reg        lb2_we = 1'b0;
wire [7:0] lb2_q8;
wire [4:0] lb2_q = lb2_q8[4:0];

assign vr_i[4].a_addr = {8'd0, lb2_addr};
assign vr_i[4].a_d    = {3'b000, lb2_data};
assign vr_i[4].a_we   = lb2_we;
assign vr_i[4].b_addr = 16'd0;
assign vr_i[4].b_d    = 8'd0;
assign vr_i[4].b_we   = 1'b0;
assign lb2_q8 = vr_o[4].a_q;

function [10:0] tile_code(input [7:0] code, input [7:0] attr, input [2:0] bank);
    case (ext_mode)
        4'd1:    tile_code = gfxbank[3] && code[7:6] == 2'b10 ? {2'b01, gfxbank[2], gfxbank[0], code[5:0]} : {2'b00, code};
        4'd2:    tile_code = {1'b0, attr[5], code};
        4'd9:    tile_code = {gfxbank[3], gfxbank[0], code};
        4'd10:   tile_code = {gfxbank[0], 1'b0, code};
        4'd11:   tile_code = {attr[5:4], code};
        4'd13:   tile_code = (gfxbank[2] && code[7:6] == 2'b10) || (gfxbank[3] && code[7:6] == 2'b11) ?
                             {gfxbank4, ~gfxbank4, gfxbank[1], gfxbank[0], code[5:0]} : {2'b00, code};
        4'd3:    tile_code = {gfxbank[1:0], code};
        4'd5:    tile_code = {1'b0, code[7] & gfxbank[0], code};
        4'd7:    tile_code = gfxbank[3] && code[7:6] == 2'b10 ?
                             {2'b00, code} + 10'd128 + {3'd0, gfxbank[0], 6'd0} + {2'd0, gfxbank[2], 7'd0} +
                             {1'b0, ~gfxbank4, 8'd0} : {2'b00, code};
        4'd14,
        4'd15:   tile_code = {bank, code};
        default: tile_code = {2'b00, code};
    endcase
endfunction

reg  [7:0] cur_p0 = 8'd0, cur_p1 = 8'd0, nxt_p0 = 8'd0, nxt_p1 = 8'd0, cur_p2 = 8'd0, nxt_p2 = 8'd0;
reg  [2:0] cur_col = 3'd0, nxt_col = 3'd0;
reg        cur_c3 = 1'b0, nxt_c3 = 1'b0;
reg  [2:0] t_line;
wire [7:0] xn    = {x[7:3] + 5'd1, 3'b000} ^ {8{flip_x}};
wire [7:0] vf    = y ^ {8{flip_y}};
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
            3'd4: begin nxt_col <= col_fix(ot_q[2:0]); nxt_c3 <= c4 & ot_q[6]; end
            3'd5: if (db) gt_addr <= {1'b0, ~db_bg[7] || xn[7:3] == 5'd28 ? 2'b11 : 2'b00, vr_q, t_line};
                  else gt_addr <= {tile_code(vr_q, ot_q, ext_mode == 4'd14 ? {1'b0, col_bank[xn[7:5]], 1'b0} : tbank[xn[7:3]]) | {2'b00, mar & bgp[{2'b10, xn[7:3]}][0], 8'd0}, t_line};
            3'd7: begin nxt_p0 <= g0t_q; nxt_p1 <= g1t_q; nxt_p2 <= g2t_q; end
            default: ;
        endcase
    end
    if (ph == 3'd0 && x[2:0] == 3'd7) begin
        cur_p0  <= nxt_p0;
        cur_p1  <= nxt_p1;
        cur_p2  <= nxt_p2;
        cur_col <= nxt_col;
        cur_c3  <= nxt_c3;
    end
end

wire [2:0] t_bit = ~(x[2:0] ^ {3{flip_x}});
wire [1:0] t_pen = {cur_p0[t_bit], cur_p1[t_bit]};
wire [2:0] t_pen3 = {cur_p0[t_bit], cur_p1[t_bit], cur_p2[t_bit]};

wire       blank_h = ~active;
wire [2:0] sn      = x[6:4];
wire [7:0] s_vf    = y ^ {8{flip_y}};

reg  [7:0] s_sum;
reg  [5:0] s_code;
reg        s_fx, s_fy, s_hit;
reg  [2:0] s_color;
reg        s_c3, r_c3, spr_c3;
reg  [7:0] s_attr;
reg  [7:0] s_x;
reg  [7:0] sp0h0, sp0h1, sp1h0, sp1h1, sp2h0, sp2h1;

reg        r_hit = 1'b0, r_fx;
reg  [2:0] r_color;
reg  [7:0] r_x;
reg  [7:0] rp0h0, rp0h1, rp1h0, rp1h1, rp2h0, rp2h1;

reg        shell_v = 1'b0, missile_v = 1'b0;
reg  [7:0] shell_x, missile_x, b_y;

wire [3:0] s_row = s_sum[3:0] ^ {4{s_fy}};

function [7:0] spr_ext(input [5:0] code, input [7:0] attr);
    case (ext_mode)
        4'd1:    spr_ext = gfxbank[3] && code[5:4] == 2'b10 ? (rcl ? {2'b01, gfxbank[0], gfxbank[2], code[3:0]} :
                                                                      {2'b01, gfxbank[2], gfxbank[0], code[3:0]}) : {2'b00, code};
        4'd2:    spr_ext = {1'b0, attr[5], code};
        4'd3:    spr_ext = {gfxbank[1:0], code};
        4'd4,
        4'd5:    spr_ext = {2'b01, code};
        4'd6:    spr_ext = {attr[5:4], code};
        4'd7:    spr_ext = gfxbank[3] && code[5:4] == 2'b10 ?
                           {2'b00, code} + 8'd32 + {3'd0, gfxbank[0], 4'd0} + {2'd0, gfxbank[2], 5'd0} +
                           {1'b0, ~gfxbank4, 6'd0} : {2'b00, code};
        4'd8:    spr_ext = {2'b10, code};
        4'd9:    spr_ext = {gfxbank[3], gfxbank[0], code};
        4'd10,
        4'd14:   spr_ext = {gfxbank[0], 1'b1, code};
        4'd11:   spr_ext = {attr[5:4], code};
        4'd12:   spr_ext = {1'b0, attr[4], code};
        4'd13:   spr_ext = (gfxbank[2] && code[5:4] == 2'b10) || (gfxbank[3] && code[5:4] == 2'b11) ?
                           {gfxbank4, ~gfxbank4, gfxbank[1], gfxbank[0], code[3:0]} : {2'b00, code};
        default: spr_ext = {2'b00, code};
    endcase
endfunction

reg  [7:0] s_code8;
wire [7:0] spr_code = db ? {2'b01, s_code} : vflags5[3] ? s_code8 : spr_ad ? {s_attr[5], s_attr[4] | s_code8[6], s_code8[5:0]} :
                      spr_ext(s_code, s_attr);

wire [7:0] y16   = y + 8'd16;
wire [1:0] spage = vflags2[3] ? y16[7:6] : 2'b00;
wire [2:0] shb   = vflags2[1] ? 3'b110 : 3'b011;

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
                3'd4: begin
                    os_addr <= {spage, 3'b010, sn, 2'd3};
                    s_code <= os_q[5:0]; s_code8 <= os_q;
                    s_fx <= os_q[6] & ~vflags5[3] & ~spr_ad; s_fy <= os_q[7] & ~vflags5[3];
                end
                3'd5: begin s_color <= col_fix(os_q[2:0]); s_c3 <= c4 & os_q[6]; s_attr <= os_q; end
                3'd6: begin s_x <= os_q; s_hit <= s_sum[7:4] == 4'hF; end
                default: ;
            endcase
            4'd1: case (ph)
                3'd1: gs_addr <= {spr_hi, spr_code, s_row[3], 1'b0, s_row[2:0]};
                3'd2: gs_addr <= {spr_hi, spr_code, s_row[3], 1'b1, s_row[2:0]};
                3'd3: begin sp0h0 <= g0s_q; sp1h0 <= g1s_q; sp2h0 <= g2s_q; end
                3'd4: begin sp0h1 <= g0s_q; sp1h1 <= g1s_q; sp2h1 <= g2s_q; end
                default: ;
            endcase
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
        r_hit <= s_hit; r_fx <= s_fx; r_color <= s_color; r_c3 <= s_c3; r_x <= s_x;
        rp0h0 <= sp0h0; rp0h1 <= sp0h1; rp1h0 <= sp1h0; rp1h1 <= sp1h1; rp2h0 <= sp2h0; rp2h1 <= sp2h1;
        r2_hit <= s2_hit; r2_fx <= s2_fx; r2_color <= s2_color; r2_x <= s2_x;
        r2p0h0 <= s2p0h0; r2p0h1 <= s2p0h1; r2p1h0 <= s2p1h0; r2p1h1 <= s2p1h1;
    end
end

wire       rend  = blank_h ? x >= 8'h88 : x < 8'h08;
wire [3:0] ri    = x[3:0] ^ 4'd8;
wire [3:0] rc    = ri ^ {4{r_fx}};
wire [2:0] rbit  = ~rc[2:0];
wire [1:0] r_pen = rc[3] ? {rp0h1[rbit], rp1h1[rbit]} : {rp0h0[rbit], rp1h0[rbit]};
wire [2:0] r_pen3 = rc[3] ? {rp0h1[rbit], rp1h1[rbit], rp2h1[rbit]} : {rp0h0[rbit], rp1h0[rbit], rp2h0[rbit]};
wire [7:0] wa    = r_x + {4'd0, ri};
wire [3:0] rc2   = ri ^ {4{r2_fx}};
wire [2:0] rbit2 = ~rc2[2:0];
wire [1:0] r2_pen = rc2[3] ? {r2p0h1[rbit2], r2p1h1[rbit2]} : {r2p0h0[rbit2], r2p1h0[rbit2]};
wire [7:0] wa2   = r2_x + {4'd0, ri};

function [4:0] lb_merge(input [4:0] buf_v, input [1:0] pn, input [2:0] col);
    reg [1:0] bp;
    reg [2:0] bc;
    reg       any;
    begin
        bp  = buf_v[4:3];
        bc  = buf_v[2:0];
        any = |pn;
        lb_merge[3]  = bp[0] | (pn[0] & ~bp[1]);
        lb_merge[4]  = bp[1] | (pn[1] & ~bp[0]);
        lb_merge[0]  = bc[0] | (any & col[0] & ~bc[1] & ~bc[2]);
        lb_merge[1]  = bc[1] | (any & col[1] & ~bc[2] & ~bc[0]);
        lb_merge[2]  = bc[2] | (any & col[2] & ~bc[0] & ~bc[1]);
    end
endfunction

wire [7:0] ra = flip_x ? 8'd254 - x : x - 8'd1;
reg  [4:0] spr, spr2;

always @(posedge clk) begin
    case (ph)
        3'd1: begin lb_addr <= ra; lb2_addr <= ra; end
        3'd3: begin
            spr  <= lb_q;  spr_c3 <= lb_q8[5]; lb_data  <= 5'd0; lb_c3 <= 1'b0; lb_we  <= active;
            spr2 <= lb2_q; lb2_data <= 5'd0; lb2_we <= active;
        end
        3'd4: begin lb_addr <= wa; lb_we <= 1'b0; lb2_addr <= wa2; lb2_we <= 1'b0; end
        3'd6: begin
            lb_data  <= bpp3 ? (lb_q[4:2] == 3'd0 && r_pen3 != 3'd0 ? {r_pen3, r_color[1:0]} : lb_q) :
                               lb_merge(lb_q, r_pen, r_color);
            lb_c3    <= lb_q[4:3] != 2'b00 ? lb_q8[5] : |r_pen & r_c3;
            lb_we    <= rend & r_hit & (|wa[7:4] | bpp3);
            lb2_data <= lb_merge(lb2_q, r2_pen, r2_color);  lb2_we <= rend & r2_hit & |wa2[7:4];
        end
        default: begin lb_we <= 1'b0; lb2_we <= 1'b0; end
    endcase
end

reg  [10:0] rcv_addr;
wire  [7:0] rcv_q;

assign vr_i[5].a_addr = {5'd0, rc_addr};
assign vr_i[5].a_d    = cpu_dout;
assign vr_i[5].a_we   = rc_we;
assign vr_i[5].b_addr = {5'd0, rcv_addr};
assign vr_i[5].b_d    = 8'd0;
assign vr_i[5].b_we   = 1'b0;
assign rc_q = vr_o[5].a_q;
assign rcv_q = vr_o[5].b_q;

reg  [11:0] rcg_addr;
wire  [7:0] rcg_hi, rcg_lo;

assign gr_i[3].a_addr = {3'd0, rcg_we ? ioctl_addr[12:0] : {1'b0, rcg_addr}};
assign gr_i[3].a_d    = ioctl_dout;
assign gr_i[3].a_we   = rcg_we;
assign gr_i[3].b_addr = {3'd0, 1'b1, rcg_addr};
assign gr_i[3].b_d    = 8'd0;
assign gr_i[3].b_we   = 1'b0;
assign rcg_hi = gr_o[3].a_q;
assign rcg_lo = gr_o[3].b_q;

reg  [2:0] rc_row, rc_col;
reg  [3:0] rc_pen = 4'd0;
wire [8:0] rc_bx = {1'b0, x ^ {8{crt_flip}}} + rc_h;
wire [7:0] rc_by = (y ^ {8{crt_flip}}) + rc_v;

always @(posedge clk) begin
    case (ph)
        3'd1: begin rcv_addr <= {rc_by[7:3], rc_bx[8:3]}; rc_row <= rc_by[2:0]; rc_col <= rc_bx[2:0]; end
        3'd3: rcg_addr <= {rcv_q, rc_row, rc_col[2]};
        3'd5: rc_pen <= {rcg_hi[{1'b0, rc_col[1:0]}], rcg_hi[{1'b1, rc_col[1:0]}], rcg_lo[{1'b0, rc_col[1:0]}], rcg_lo[{1'b1, rc_col[1:0]}]};
        default: ;
    endcase
end

localparam [63:0] RC_RG = {8'hFF, 8'hDE, 8'hB8, 8'h97, 8'h68, 8'h47, 8'h21, 8'h00};
localparam [31:0] RC_B  = {8'hFF, 8'hAD, 8'h52, 8'h00};
wire  [7:0] rcp    = pal[{2'b10, rc_pen}];
wire [23:0] rc_rgb = {RC_RG[rcp[2:0]*8 +: 8], RC_RG[rcp[5:3]*8 +: 8], RC_B[rcp[7:6]*8 +: 8]};

reg  [16:0] sr = 17'd0;
reg   [1:0] sr_hold = 2'd0;
reg  [16:0] sr_frame = 17'd0;
wire [16:0] sr_n = {sr[12] ^ ~sr[0], sr[16:1]};
wire        vsync = ~vcnt[8];
assign      n3a   = ~sr[0];

function [6:0] star(input [16:0] s);
    star = {(s & 17'h1FE01) == 17'h1FE00, ~s[8:3]};
endfunction

reg [6:0] star_a, star_b;

reg  [25:0] blink_cnt = 26'd0;
reg   [1:0] blink = 2'd0;
always @(posedge clk) begin
    if (!pause) begin
        if (blink_cnt == 26'd40874802) begin blink_cnt <= 26'd0; blink <= blink + 2'd1; end
        else blink_cnt <= blink_cnt + 26'd1;
    end
end

always @(posedge clk) begin
    if (!stars_on || (vflags3[5] && vsync)) sr <= 17'd0;
    else if (vsync && pause) sr <= sr_frame;
    else if (active && !vsync && (ph == 3'd2 || ph == 3'd5)) begin
        if (sr_hold != 2'd2 && !flip_x) sr_hold <= sr_hold + 2'd1;
        else sr <= sr_n;
    end
    if (vsync) sr_hold <= 2'd0;
    if (vsync && !pause) sr_frame <= sr;
    if (ph == 3'd1) begin star_a <= star(sr); star_b <= star(sr_n); end
end

wire [4:0] mix = spr2[4:3] != 2'b00 ? spr2 : lb_merge(spr, t_pen, cur_col);
wire [1:0] pen = mix[4:3];
wire       mc3 = spr[4:3] != 2'b00 ? spr_c3 : cur_c3;
wire [7:0] pv  = pal[{c4 & mc3, mix[2:0], pen}];
wire [4:0] m3  = spr[4:2] != 3'd0 ? spr : {t_pen3, cur_col[1:0]};
wire [7:0] pv3 = pal[{m3[1:0], m3[4:2]}];
wire       pen_on = bpp3 ? m3[4:2] != 3'd0 : pen != 2'd0;
wire [7:0] pvx = bpp3 ? pv3 : pv;

wire [7:0] bx = crt_flip ? 8'd255 - x : x;
localparam [191:0] MSH_BUL = {24'h000000, 24'h0000FF, 24'hFF0000, 24'hFF00FF, 24'h00FF00, 24'h00FFFF, 24'hFFFF00, 24'hFFFFFF};
wire [8:0] shell_d   = {1'b0, bx} + {1'b0, shell_x}   - 9'd251;
wire [8:0] missile_d = {1'b0, bx} + {1'b0, missile_x} - 9'd251;
wire       shell_on   = shell_v   & (bullet_mode ? (shell_d == 9'h1FE || shell_d == 9'h1FF) : shell_d < 9'd4);
wire       missile_on = missile_v & (bullet_mode ? (missile_d == 9'h1FE || missile_d == 9'h1FF) : missile_d < 9'd4);

wire       m_st   = bgp[{2'b10, x[7:3] + 5'd1}][2];
wire       st_en  = (y[0] ^ flip_y) ^ (x[3] ^ flip_x);
wire [6:0] st     = star_b[6] ? star_b : star_a;
wire       st_blk = !vflags3[5] || (blink == 2'd0 ? st[5] : blink == 2'd1 ? st[3] : blink == 2'd2 ? y[1] : 1'b1);
wire       st_on  = stars_on & st_en & st[6] & st_blk & ~(stars_232 & bx >= 8'd232) & ~(vflags4[2] & x[7]) & (~mar | m_st);

wire bg_blue = vflags3[2] & (flip_x ? x >= 8'd128 : x < 8'd128);

wire [7:0] gi    = x < 8'd128 ? x : x < 8'd248 ? x - 8'd120 : 8'd0;
wire [7:0] mi    = x - 8'd128;
wire       brown = vflags4[1] && x >= 8'd128 && x < 8'd248;
wire [8:0] br_r  = {1'b0, mi} + {2'b00, mi[7:1]};
wire [7:0] bg_grad = gi;
wire [1:0] sp    = bgp[{2'b00, flip_x ? ~x[7:3] : x[7:3]}][1:0];
wire [4:0] mc    = x[7:3];
wire [3:0] mbg   = mc == 5'd31 ? 4'd0 : flip_x ? bgp[{2'b01, 5'd30 - mc}] : bgp[{2'b00, mc + 5'd1}];
wire [7:0] mblue = (mbg[0] ? 8'h0E : 8'h00) + (mbg[1] ? 8'h1F : 8'h00) + (mbg[2] ? 8'h43 : 8'h00) + (mbg[3] ? 8'h8F : 8'h00);
wire [23:0] strat = {~sp[1] & bg_rgb[2] ? 8'h7C : 8'h00, ~sp[1] & bg_rgb[1] ? 8'h3C : 8'h00, ~sp[0] & bg_rgb[0] ? 8'h47 : 8'h00};

wire [8:0] db_edge = 9'd256 - {1'b0, db_split};
wire       db_side = flip_x ? {1'b0, x} >= db_edge : {1'b0, x} < db_edge;
wire [2:0] db_col  = db_side ? db_bg[2:0] : db_bg[6:4];
wire [23:0] db_bgc = {db_col[0] ? 8'h47 : 8'h00, db_col[1] ? 8'h47 : 8'h00, db_col[2] ? 8'h47 : 8'h00};
wire       db_hide = db & db_bg[3] & db_side;
wire [7:0] db_tv   = pal[{1'b0, cur_col, t_pen}];
// Harem (ext 14): tile layer opaque, pen 0 = PROM colour entry 0 of the tile colour (sky / sand; MAME video_start harem)
wire       hm_bg   = ext_mode == 4'd14;
wire [7:0] hm_tv   = pal[{1'b0, cur_col, 2'b00}];
function [23:0] db_rgb(input [7:0] v);
    db_rgb = {RG_LUT[v[5:3]*8 +: 8], B_LUT[v[7:6]*8 +: 8], RG_LUT[v[2:0]*8 +: 8]};
endfunction

reg [23:0] rgb;
always @(*) begin
    if (db_hide)                     rgb = t_pen != 2'd0 && cur_col[2] ? db_rgb(db_tv) :
                                           st_on ? {ST_LUT[{st[4], st[5]}*8 +: 8], ST_LUT[{st[2], st[3]}*8 +: 8], ST_LUT[{st[0], st[1]}*8 +: 8]} :
                                           db_bgc;
    else if ((missile_on | shell_on) && vflags5[4]) rgb = bx[6] ? 24'hFF00FF : MSH_BUL[bx[4:2]*24 +: 24];
    else if (missile_on)             rgb = vflags3[6] ? 24'hFF00FF : 24'hFFFF00;
    else if (shell_on)               rgb = bullet_mode ? 24'hFFFF00 : 24'hFFFFFF;
    else if (pen_on && db)           rgb = db_rgb(pvx);
    else if (pen_on && vflags5[5])   rgb = {RG_LUT[pvx[2:0]*8 +: 8], B_LUT[pvx[7:6]*8 +: 8], RG_LUT[pvx[5:3]*8 +: 8]};
    else if (pen_on)                 rgb = {RG_LUT[pvx[2:0]*8 +: 8], RG_LUT[pvx[5:3]*8 +: 8], B_LUT[pvx[7:6]*8 +: 8]};
    else if (hm_bg)                  rgb = {RG_LUT[hm_tv[2:0]*8 +: 8], RG_LUT[hm_tv[5:3]*8 +: 8], B_LUT[hm_tv[7:6]*8 +: 8]};
    else if (rcl)                    rgb = rc_rgb;
    else if (st_on)                  rgb = {ST_LUT[{st[4], st[5]}*8 +: 8], ST_LUT[{st[2], st[3]}*8 +: 8], ST_LUT[{st[0], st[1]}*8 +: 8]};
    else if (bg_blue)                rgb = 24'h000047;
    else if (vflags3[4] && bg_en)    rgb = 24'h000056;
    else if (vflags5[2] && bg_en && (flip_x ? x >= 8'd200 : x < 8'd56)) rgb = 24'h000056;
    else if (vflags4[0] && bg_en)    rgb = brown ? {br_r[7:0], mi - {2'b00, mi[7:2]}, {1'b0, mi[7:1]}} :
                                                   {8'h00, bg_grad, bg_grad[6:0], 1'b0};
    else if (vflags4[3])             rgb = strat;
    else if (mar)                    rgb = {16'h0000, mblue};
    else if (db)                     rgb = db_bgc;
    else if (vflags3[7])             rgb = {bg_rgb[2] ? 8'h55 : 8'h00, bg_rgb[1] ? 8'h47 : 8'h00, bg_rgb[0] ? 8'h55 : 8'h00};
    else                             rgb = 24'd0;
end

always @(posedge clk) begin
    if (ph == 3'd0) {r, g, b} <= rgb_gbr ? {rgb[15:0], rgb[23:16]} : rgb;
end

endmodule
