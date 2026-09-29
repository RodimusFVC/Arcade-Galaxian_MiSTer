//============================================================================
//
//  Pac-Man video: tile/sprite fetch, sprite line buffer, colour lookup
//
//  Ported from "A simulation model of Pacman hardware"
//  Copyright (c) MikeJ - January 2006 (www.fpgaarcade.com), BSD licence;
//  MiSTer merge by Alexey Melnikov (Sorgelig)
//
//============================================================================

module pacman_video
(
    input               clk,
    input               ce6,

    input         [8:0] hcnt,
    input         [8:0] vcnt,
    input        [11:0] ab,             // sync bus address
    input         [7:0] db,             // sync bus data
    input               hblank,
    input               vblank,
    input               flip,           // tile flip (game latch ^ CRT flip)
    input               crt_flip,       // mirror sprites for CRT flip
    input         [2:0] gfx_dec,        // [0] D4/D6 and A0/A2 swapped, [1] Ponpoko byte order, [2] crush4 split planes
    input               dl_active,      // ROM download in progress (port A belongs to the loader)
    input               spr_xy_we,      // CPU write to 5060-506F (sync bus phase)

    // Jr. Pac-Man (latch 2 at 5070 and the scrolling playfield)
    input               jr,
    input               jr_charbank,
    input               jr_spritebank,
    input               jr_palbank,
    input               jr_colbank,
    input               jr_bgpri,       // playfield pens over sprites
    input         [2:0] jr_line,        // playfield line within the tile, scroll and flip applied

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               dl_gfx,         // gfx1 region write
    input               dl_pal,         // palette PROM write (proms 0x00-0x1F)
    input               dl_lut,         // colour lookup PROM write (proms 0x20-0x11F)
    input               dl_jr_lo,       // Jr palette PROM 9E (low nibble)
    input               dl_jr_hi,       // Jr palette PROM 9F (high nibble)

    output        [7:0] rgb             // palette PROM byte: B[7:6] G[5:3] R[2:0]
);

// sprite X/Y registers (5060-506F)
wire [7:0] xy_raw;
dpram_dc #(.widthad_a(4)) sprite_xy_ram
(
    .clock_a(clk),
    .address_a(ab[3:0]),
    .data_a(db),
    .wren_a(ce6 & spr_xy_we),

    .clock_b(clk),
    .address_b(ab[3:0]),
    .q_b(xy_raw)
);

wire       xadj = ~(ab[1] & ab[2]) ^ ab[3];
wire [7:0] xy   = ~crt_flip ? ~xy_raw :
                  ab[0]     ? xy_raw - 8'd19 :
                              xy_raw - 8'd15 + {6'd0, xadj, 1'b0};
wire [7:0] dr   = hblank ? xy : 8'hFF;

// character / sprite address generation
reg  [7:0] db_reg;
reg  [3:0] char_sum_reg;
reg        char_match_reg;
reg        char_hblank_reg;

always @(posedge clk) begin
    if (ce6 && hcnt[2:0] == 3'd3) begin
        reg [8:0] sum;
        sum = {vcnt[7:0], 1'b1} + {dr, ~hblank};
        char_sum_reg    <= (jr & ~hblank) ? {sum[4], jr_line ^ {3{flip}}} : sum[4:1];
        char_match_reg  <= (sum[8:5] == 4'hF);
        char_hblank_reg <= hblank;
        db_reg          <= db;
    end
end

wire xflip = char_hblank_reg ? db_reg[1] ^ crt_flip : flip;
wire yflip = char_hblank_reg ? db_reg[0] ^ crt_flip : flip;
wire obj_on = char_match_reg | hcnt[8];

wire [12:0] ca;
assign ca[12]   = char_hblank_reg;
assign ca[11:6] = db_reg[7:2];
assign ca[5]    = char_hblank_reg ? char_sum_reg[3] ^ xflip : db_reg[1];
assign ca[4]    = char_hblank_reg ? hcnt[3] : db_reg[0];
assign ca[3]    = hcnt[2] ^ yflip;
assign ca[2]    = char_sum_reg[2] ^ xflip;
assign ca[1]    = char_sum_reg[1] ^ xflip;
assign ca[0]    = char_sum_reg[0] ^ xflip;

wire [13:0] ca_jr = {ca[12], ca[12] ? jr_spritebank : jr_charbank, ca[11:0]};   // Jr: 16K, bank bit below the region

wire [7:0] gfx_q;
wire       gfx_eyes = gfx_dec[0];
// Ponpoko: character halves swapped, sprite 8-byte blocks rotated by one
wire [12:0] ca_pp = ca[12] ? {ca[12:5], ca[4:3] - 2'd1, ca[2:0]} : ca ^ 13'h0008;
wire [12:0] ca_rom = gfx_dec[1] ? ca_pp : gfx_eyes ? {ca[12:3], ca[0], ca[1], ca[2]} : ca;
wire [7:0] gfx_q2;
wire [7:0] gfx_dout = gfx_eyes   ? {gfx_q[7], gfx_q[4], gfx_q[5], gfx_q[6], gfx_q[3:0]} :
                      gfx_dec[2] ? {gfx_q2[7:4], gfx_q[3:0]} : gfx_q;   // crush4: plane 0 sits in the ROM's upper half
dpram_dc #(.widthad_a(14)) gfx_rom
(
    .clock_a(clk),
    .address_a(dl_active ? ioctl_addr[13:0] : {1'b1, ca_rom}),
    .data_a(ioctl_dout),
    .wren_a(dl_gfx),
    .q_a(gfx_q2),

    .clock_b(clk),
    .address_b(jr ? ca_jr : {1'b0, ca_rom}),
    .q_b(gfx_q)
);

// 2bpp shift registers (planes packed four pixels per nibble)
reg  [3:0] shift_regl, shift_regu;
reg        vout_obj_on, vout_yflip, vout_hblank;
reg  [4:0] vout_db;

wire       ip        = hcnt[0] & hcnt[1];
wire [1:0] shift_sel = vout_yflip ? {ip, 1'b1} : {1'b1, ip};
wire [1:0] shift_op  = vout_yflip ? {shift_regu[0], shift_regl[0]} : {shift_regu[3], shift_regl[3]};

always @(posedge clk) begin
    if (ce6) begin
        case (shift_sel)
            2'b01: begin shift_regu <= {1'b0, shift_regu[3:1]}; shift_regl <= {1'b0, shift_regl[3:1]}; end
            2'b10: begin shift_regu <= {shift_regu[2:0], 1'b0}; shift_regl <= {shift_regl[2:0], 1'b0}; end
            2'b11: begin shift_regu <= gfx_dout[7:4];            shift_regl <= gfx_dout[3:0];            end
            default: ;
        endcase

        if (hcnt[2:0] == 3'd7) begin
            vout_obj_on <= obj_on;
            vout_yflip  <= yflip;
            vout_hblank <= hblank;
            vout_db     <= db[4:0];
        end
    end
end

// colour lookup PROM (4A)
wire [7:0] lut_4a;
dpram_dc #(.widthad_a(8)) col_rom_4a
(
    .clock_a(clk),
    .address_a(ioctl_addr[7:0] - 8'h20),
    .data_a(ioctl_dout),
    .wren_a(dl_lut),

    .clock_b(clk),
    .address_b({jr & jr_colbank, vout_db, shift_op}),
    .q_b(lut_4a)
);

// sprite line buffer: read-modify-write at ra_t1, cleared as it is displayed
reg  [7:0] ra, ra_t1;
reg        vout_obj_on_t1, vout_hblank_t1;
reg  [7:0] lut_4a_t1;
reg  [1:0] shift_op_t1;

wire cntr_ld = (hcnt[3:0] == 4'd7) & (vout_hblank | hblank | ~vout_obj_on);

always @(posedge clk) begin
    if (ce6) begin
        ra             <= cntr_ld ? dr : ra + 8'd1;
        ra_t1          <= ra;
        vout_obj_on_t1 <= vout_obj_on;
        vout_hblank_t1 <= vout_hblank;
        lut_4a_t1      <= lut_4a;
        shift_op_t1    <= shift_op;
    end
end

wire [7:0] sprite_ram_q;
wire [5:0] sprite_ram_op = sprite_ram_q[5:0];
wire [5:0] sprite_ram_reg = vout_obj_on_t1 ? sprite_ram_op : 6'd0;
wire       video_op_sel   = |sprite_ram_reg[5:2];
wire [5:0] sprite_ram_ip  = ~vout_hblank_t1 ? 6'd0 :
                            video_op_sel    ? sprite_ram_reg : {lut_4a_t1[3:0], shift_op_t1};

dpram_dc #(.widthad_a(8)) sprite_ram
(
    .clock_a(clk),
    .address_a(ra_t1),
    .data_a({2'b00, sprite_ram_ip}),
    .wren_a(ce6 & vout_obj_on_t1),

    .clock_b(clk),
    .address_b(ra_t1),
    .q_b(sprite_ram_q)
);

wire [3:0] final_col = (vout_hblank | vblank)             ? 4'd0 :
                       (jr & jr_bgpri & |shift_op)        ? lut_4a[3:0] :           // Jr: opaque playfield pens on top
                       video_op_sel                       ? sprite_ram_reg[5:2] : lut_4a[3:0];

// palette PROM (7F); Jr. Pac-Man: two 4-bit PROMs (9E low, 9F high), 32 colours, bank on latch 2 Q0
wire [7:0] pm_rgb, jr_lo, jr_hi;
dpram_dc #(.widthad_a(5)) col_rom_7f
(
    .clock_a(clk),
    .address_a(ioctl_addr[4:0]),
    .data_a(ioctl_dout),
    .wren_a(dl_pal),

    .clock_b(clk),
    .address_b({1'b0, final_col}),
    .q_b(pm_rgb)
);

dpram_dc #(.widthad_a(5)) jr_pal_lo
(
    .clock_a(clk),
    .address_a(ioctl_addr[4:0]),
    .data_a(ioctl_dout),
    .wren_a(dl_jr_lo),

    .clock_b(clk),
    .address_b({jr_palbank, final_col}),
    .q_b(jr_lo)
);

dpram_dc #(.widthad_a(5)) jr_pal_hi
(
    .clock_a(clk),
    .address_a(ioctl_addr[4:0]),
    .data_a(ioctl_dout),
    .wren_a(dl_jr_hi),

    .clock_b(clk),
    .address_b({jr_palbank, final_col}),
    .q_b(jr_hi)
);

assign rgb = jr ? {jr_hi[3:0], jr_lo[3:0]} : pm_rgb;

endmodule
