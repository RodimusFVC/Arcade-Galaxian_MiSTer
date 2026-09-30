//============================================================================
//
//  Galaxian / Moon Cresta board (Namco / Midway / Nichibutsu)
//
//  Derived from "FPGA GALAXIAN" by Katsumi Degawa (c) 2004 and the MiSTer
//  port by Alexey Melnikov (Sorgelig). Memory maps per MAME galaxian.cpp.
//
//============================================================================

module galaxian_board
(
    input               clk,            // 49.152 MHz
    input               reset,
    input         [2:0] ph,             // pixel phase, 6.144 MHz pixel clock steps when ph == 0
    input               pause,

    input         [7:0] variant,        // memory map: 0 Galaxian, 1 Moon Cresta, 2 Scorpion (MC), 3 Crazy Kong (MC),
                                        // 4 Jump Bug, 5 Frogger, 6 Scramble / The End, 7 Super Cobra, 8 Turtles,
                                        // 9 Frog (Falcon) / Hustler, 10 Frogger (AM), 11 Turpin (S), 12 Stern type 2,
                                        // 13 Hustler bootleg, 14 Hustler bootleg without PPIs, 15 Mars / Mr. Kougar,
                                        // 16 Hot Shocker, 17 Triple Punch, 18 Scramble bootleg on Galaxian I/O,
                                        // 19 Scramble bootleg (bit-wide inputs), 20 Tazz-Mania bootleg, 21 Mandinka,
                                        // 22 Crazy Kong on Galaxian (Crazy Kong memory, Galaxian I/O at C000 on A11-A10),
                                        // 23 Crazy Kong on Scramble (PPIs 7000 / 7800, latches A800, watchdog B000),
                                        // 24 Amigo (IN0-IN3 4000-4003, 4000 write = sound command, 5000 sound control,
                                        // RAM 8000, video 8800, objects 9000, Turtles latches A000 on A5-A3, watchdog A800)
    input         [7:0] vflags,         // [0] Scramble shells, [1] RGB -> GBR harness (Eagle), [2] Mr. Kougar packed gfx
    input         [7:0] bflags,         // [0] NMI enable on latch 0, [1] 2K work RAM, [2] stars cut, [3] Moon Cresta
                                        // decryption, [4] same on opcodes only, [5] latch 2 is gfx bank 0,
                                        // [6] Moon Cresta sound mixer
    input         [7:0] bflags2,        // [0] no watchdog, [1] no discrete sound, [2] AY on Z80 I/O 00-02 (Bongo),
                                        // [3] B000 reads DSW (Bongo discrete), [4] pitch clock / 8 (Bongo discrete),
                                        // [5] no stars right of H = 232 (Jump Bug status area)
    input         [7:0] bflags3,        // [0] sound CPU board (Check Man), [1] its Japan / Dingo map, [2] sound command on
                                        // any OUT (else a 7800 write), [3] Check Man decryption, [4] Check Man (Japan)
                                        // protection at 3800, [5] Dingo protection at 3000 / 3035
    input         [7:0] vflags2,        // see galaxian_video.sv
    input         [7:0] bflags4,        // [0] 1K object RAM, [1] Zig Zag ROM 2000/3000 swap on 7002, [2] Fantastic ROM
                                        // unscramble, [3] two AYs at 8800 (Fantastic), [4] AY written through
                                        // 4800-4FFF address lines (Zig Zag), [5] AY clock 3.072 MHz
    input         [7:0] vflags3,        // see galaxian_video.sv
    input         [7:0] bflags5,        // [0] Konami sound board (Z80 + AY + filters), [1] its second AY (Scramble),
                                        // [2] first sound ROM D0 / D1 swapped (Frogger), [3] Scramble / The End
                                        // protection on PPI 1 port C, [4] watchdog also at 7800 (Atlantis, Frogger
                                        // VD), [5] Frogger
                                        // timer on a 2-AY board (Quaak), [6] timer also read at 9000 (Turpin S),
                                        // [7] Turpin NV on the Scramble map (ROM C000-CFFF, colour latches 6803-5)
    input         [7:0] vflags4,        // see galaxian_video.sv
    input         [7:0] bflags6,        // Stern: [0] type 2 as Tazz-Mania 3 (plain PPIs, latches on A3-A0), [1] PPI 1
                                        // port C reads FC (Rescue bootleg), [2] ROM A9-A0 inverted in 0000-0FFF,
                                        // 2000-2FFF, 4000-4FFF (Tazz-Mania ET), [3] Strategy X colour latches B000 G,
                                        // B002 B, B00A R, [4] B002 = background enable (Tazz-Mania 2), [5] Hustler
                                        // program decryption, [6] Billiard program decryption, [7] object RAM at 5880
                                        // (5800-587F plain RAM) and RAM 4800-4BFF (Scramble Reben bootleg)
    input         [7:0] bflags7,        // [0] sound board without RC filters (Hustler), [1] Hustler bootleg sound map,
                                        // [2] sound ROM 0000-2FFF (scramble.cpp), [3] Mariner protection reads
                                        // (9008 = 03, B401 = 07, MAME init_mariner), [4] New Sinbad 7 on the Mars map
                                        // (IRQ at VBLANK instead of NMI, ROM A000-AFFF, PPI 0 at C100, PPI 1 also C200),
                                        // [5] flip latches swapped (x006 = flip Y, Videotron boards), [6] S2650 CPU on
                                        // the Galaxian map (galaxold hunchbkg_map), [7] Superbike data port latch
    input         [7:0] bflags8,        // [0] program A3-A0 scrambled (MAME init_devilfsh), [1] 6801 = NMI enable (Mr.
                                        // Kougar), [2] PPI 1 port C reads 00, [3] no sound mute on control bit 4,
                                        // [4] Hot Shocker ROM patch (2EF9 = RET, MAME init_hotshock), [5] Cavelon ROM
                                        // banking (any 8000-FFFF access toggles 0000-1FFF), [6] AY on Z80 I/O 00 data /
                                        // 01 address and read (Triple Punch), [7] Triple Punch protection ports 02 / 03
    input         [7:0] bflags9,        // [0] Super Cobra (E) program XOR (MAME init_scobrae), [1] Super Bond (decode_superbon),
                                        // [2] ROM C000-C7FF (Mandinga RF), [3] Devil Fish (G) A4-A0 swap, [4] VBLANK
                                        // flip-flop drives INT instead of NMI, [5] each 256-byte block reversed (Big Kong),
                                        // [6] watchdog also read at 6800 (Mandinga), [7] ROM D400-E3FF (Big Kong)
    input         [7:0] vflags5,        // see galaxian_video.sv
    input         [7:0] bflags10,       // [0] Victory program decode (MAME decode_victoryc), [1] RAM 8000-87FF (Victory),
                                        // [2] Crazy Mazey program decode (MAME init_crazym), [3] Mighty Monkey
                                        // program XOR (MAME init_mimonkey, table by A2-A0 and D7 / D2-D0)
    input         [7:0] rom_top,        // end of program ROM >> 8 (0 = 40)
    input         [7:0] ext_mode,       // tile/sprite code extension (see galaxian_video.sv)

    input         [7:0] in0,            // 6000 / A000
    input         [7:0] in1,            // 6800 / A800
    input         [7:0] in2,            // 7000 / B000
    input         [7:0] in3,            // DSW (AY port A on Bongo)

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               ioctl_wr0,      // ioctl index 0

    input               crt_flip,

    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output reg          video_hs = 1'b0,
    output reg          video_vs = 1'b0,
    output reg          video_hblank = 1'b1,
    output reg          video_vblank = 1'b1,

    output signed [15:0] audio,

    // hiscore (CPU paused): work RAM second port; video RAM through the CPU port
    input        [15:0] hs_address,
    input         [7:0] hs_data_in,
    output        [7:0] hs_data_out,
    input               hs_write
);

wire ce6 = (ph == 3'd0);

//------------------------------------------------------- ROM load map --------------------------------------------------------//

wire prog_cs, gfx0_cs, gfx1_cs, gfx2_cs, pal_cs, snd_cs, bgp_cs;

selector rom_selector
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(prog_cs),
    .snd_cs(snd_cs),
    .bgp_cs(bgp_cs),
    .gfx0_cs(gfx0_cs),
    .gfx1_cs(gfx1_cs),
    .gfx2_cs(gfx2_cs),
    .pal_cs(pal_cs)
);

//------------------------------------------------------- Video timing --------------------------------------------------------//

// H counts 080-1FF (384), V counts 0F8-1FF (264) and steps on HSYNC (H = 0B0); 60.61 Hz
reg [8:0] hcnt = 9'h080;
reg [8:0] vcnt = 9'h0F8;
reg       vblank = 1'b1;

wire vcnt_step     = (hcnt == 9'h0AF);
wire rising_vblank = vcnt_step & (vcnt == 9'h1EF);

always @(posedge clk) begin
    if (ce6) begin
        hcnt <= (hcnt == 9'h1FF) ? 9'h080 : hcnt + 9'd1;
        if (vcnt_step) begin
            vcnt <= (vcnt == 9'h1FF) ? 9'h0F8 : vcnt + 9'd1;
            if      (vcnt == 9'h1EF) vblank <= 1'b1;
            else if (vcnt == 9'h10F) vblank <= 1'b0;
        end

        // outputs lag the counters by one pixel, like the video pipeline
        video_hblank <= ~hcnt[8];
        video_vblank <= vblank;
        video_hs     <= hcnt >= 9'h0B0 && hcnt < 9'h0D0;
        video_vs     <= ~vcnt[8];
    end
end

//-------------------------------------------------------- Address map ---------------------------------------------------------//

// Galaxian (MAME galaxian_map): ROM, 4000 RAM (1K mirrored, 2K with bflags[1]), 5000 video RAM, 5800 object RAM,
// 6000/6800/7000 inputs, 7800 watchdog; latches on A2-A0 above 6000.
// Moon Cresta (mooncrst_map): the same with RAM at 8000, video at 9000, objects at 9800 and I/O at A000-BFFF.
// Scorpion (scorpnmc_map): Moon Cresta, ROM 0000-3FFF + 5000-67FF, RAM 4000-47FF + 8000-83FF.
// Crazy Kong (ckongmc_map): ROM 0000-5FFF, RAM 6000-6BFF, video 9000-93FF, objects 9800-9BFF (1K), I/O at A000.
// Jump Bug (jumpbug_map): ROM 0000-3FFF + 8000-AFFF, RAM 4000-47FF, video 4800, objects 5000, AY 5800/5900,
// I/O 6000-7FFF, protection B000-BFFF.
// Frogger (frogger_map): ROM 0000-3FFF, RAM 8000-87FF, watchdog 8800, video A800, objects B000, latches B800 on
// A4-A2, PPIs C000-FFFF (A13 PPI 0, A12 PPI 1, port on A2-A1).
// Scramble / The End (theend_map): ROM, RAM 4000-47FF, video 4800, objects 5000, latches 6800, watchdog 7000,
// PPIs 8000-FFFF (A8 PPI 0, A9 PPI 1, port on A1-A0).
// Super Cobra (scobra_map, A14 ignored): ROM 0000-7FFF, RAM 8000-87FF, video 8800, objects 9000, PPI 0 9800,
// PPI 1 A000, latches A800, watchdog B000.
// Turtles / Amidar (turtles_map, A14 ignored): ROM 0000-7FFF, RAM 8000-87FF, video 9000, objects 9800, latches
// A000-A03F on A5-A3, watchdog A800, PPI 0 B000 / PPI 1 B800 (port on A5-A4).
// Frog (frogf_map): ROM, RAM 8000, video 8800, objects 9000, latches A800 on A3-A1, watchdog B800, PPIs C000-FFFF
// (A12 PPI 0, A13 PPI 1, port on A4-A3).
// Frogger AM (froggeram_map): ROM 0000-2FFF, PPIs 4000-43FF (A8 / A9, data bit-reversed), RAM 8000, watchdog 8800,
// video A800, objects B000, latches B800.
// Turpin S (turpins_map): ROM 0000-7FFF, RAM 8000, video 9000, objects 9800, PPI 0 A000, latches A800, watchdog
// B800, PPI 1 C000.
// Hustler bootleg (hustlerb_map): ROM 0000-7FFF, RAM 8000, video 8800, objects 9000, latches A800 on A2-A0 (A806
// flip Y, A807 flip X), watchdog B000, PPIs C100 / C200.
// Hustler bootleg (hustlerb6_map): ROM 0000-3FFF, IN0-2 at 4800 / 4801 / 4803 (4800 write = sound command), sound
// control 5000, RAM 8000, video 8800, objects 9000, latches A800 on A2-A0, no watchdog.
// Mars / Mr. Kougar (scramble.cpp mars_map / mrkougar_map): the Scramble map with latches 6800-680F on A3-A0, PPIs
// 8100 / 8200 (port on A3, A1).
// Hot Shocker (hotshock_map): the Scramble memory, latches at 6000 (6004 flip, 6006 gfx bank) and 6801 (NMI), watchdog
// write 7000, IN0-IN3 at 8000-8003 (8000 write = sound command), 9000 write = sound IRQ; no PPIs.
// Triple Punch (triplep_map): the Scramble map with ROM 5800-67FF, PPI 0 only (8100), AY and protection on Z80 I/O.
// Scramble bootleg (galaxold scramblb_map): the Scramble memory with the Galaxian I/O at 6000-7FFF, protection 8102 /
// 8202. Scramble bootleg (scramb_common_map): Scramble memory, latches 6800, watchdog 7000, pitch 7800, inputs one bit
// per address at 6000 / 6800 / 7800, 5800-5FFF reads 25. Tazz-Mania bootleg (tazzmang_map): ROM 0000-5FFF, RAM 8000,
// objects 8800, video 9000, watchdog 9800, the Moon Cresta I/O at A000-BFFF (DSW also at 7000).
// Stern type 2 (scobra.cpp type2_map): ROM 0000-7FFF, RAM 8000, objects 8800, video 9000, watchdog 9800, PPI 0 A000,
// PPI 1 A800 (port on A3-A2; Tazz-Mania 3 A1-A0), latches B000 on A3-A1 (Tazz-Mania 3 A3-A0).
wire [7:0] top = rom_top == 8'd0 ? 8'h40 : rom_top;

// {rom, ram, vid, obj, io, ram index[11:0]}
function [16:0] decode(input [15:0] a);
    reg rom, ram, vid, obj, io;
    reg [11:0] ri;
    begin
        rom = a[15:8] < top;
        ri  = {1'b0, bflags[1] & a[10], a[9:0]};
        case (variant[4:0])
            5'd0: begin
                rom = a[15:8] < top || (bflags9[2] && a[15:11] == 5'b11000);
                ram = a[15:11] == 5'b01000 || (bflags10[1] && a[15:11] == 5'b10000) || (bflags6[7] && (a[15:10] == 6'b010010 || a[15:7] == 9'b010110000));
                ri  = bflags10[1] && a[15] ? {1'b1, a[10:0]} :
                      !bflags6[7] ? {1'b0, bflags[1] & a[10], a[9:0]} : a[15:11] == 5'b01000 ? {1'b0, a[10:0]} :
                      a[12] ? {5'b11000, a[6:0]} : {2'b10, a[9:0]};
                vid = a[15:11] == 5'b01010;
                obj = a[15:11] == 5'b01011;
                io  = a[15:13] == 3'b011;
            end
            5'd1: begin
                ram = a[15:11] == 5'b10000;
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
                rom = a[15:8] < top || (bflags7[4] && a[15:12] == 4'hA) || (ext_mode[3:0] == 4'd9 && a[15:14] == 2'b11);
                ram = a[15:11] == 5'b01000;
                ri  = {1'b0, a[10:0]};
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
            5'd4: begin
                rom = a < 16'h4000 || (a >= 16'h8000 && a < 16'hB000);
                ram = a[15:11] == 5'b01000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b01001;
                obj = a[15:11] == 5'b01010;
                io  = a[15:13] == 3'b011;
            end
            default: begin                          // 3 Crazy Kong (MC), 22 / 23 Crazy Kong on Galaxian / Scramble
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

//----------------------------------------------------------- CPU --------------------------------------------------------------//

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

reg   [7:0] ctl_9n = 8'd0;              // 7000-7007: 0/1 NMI enable, 4 stars, 6 flip X, 7 flip Y
reg   [7:0] snd_9l = 8'd0;              // 6800-6807: FS1-3, HIT, -, FIRE, VOL1, VOL2
reg   [3:0] lfo_9m = 4'hF;              // 6004-6007: background LFO DAC
reg   [7:0] pitch  = 8'd0;              // 7800
reg   [3:0] gfxbank = 4'd0;             // 6000-6002: graphics bank 0 (D1-D0), 1, 2 (Moon Cresta, Pisces)
reg         gfxbank4 = 1'b0;            // Jump Bug 6006
reg   [2:0] bg_rgb = 3'd0;              // Turtles background colour latches (R, G, B)
reg   [3:0] watchdog = 4'd0;
wire        watchdog_reset = (watchdog == 4'd8) & ~bflags2[0];

T80sed z80
(
    .RESET_n(~(reset | watchdog_reset | s26)),
    .CLK_n(clk),
    .CLKEN(ce6 & hcnt[0] & ~pause),
    .WAIT_n(wait_n),
    .INT_n(bflags9[4] ? cpu_nmi_n : cpu_int_n),
    .NMI_n(cpu_nmi_n | bflags9[4]),
    .BUSRQ_n(1'b1),
    .M1_n(z80_m1_n),
    .MREQ_n(z80_mreq_n),
    .IORQ_n(z80_iorq_n),
    .RD_n(z80_rd_n),
    .WR_n(z80_wr_n),
    .RFSH_n(z80_rfsh_n),
    .HALT_n(),
    .BUSAK_n(),
    .A(z80_addr),
    .DI(cpu_din),
    .DO(z80_dout)
);

// S2650 plug-in board (MAME hunchbkg): one access per ack (every 12 pixels, 1.536 MHz / 3), replayed on the Z80 bus
// with its address moved onto the Galaxian map: ROM pages 0000 / 2000 / 4000 / 6000 (4K) -> 0000-3FFF, 1C00 RAM ->
// 4000, 1800 video -> 5000, 1480 objects -> 5800 (A7 inverted), 1500 / 1580 / 1600 (1700) / 1680 I/O -> 6000 / 6800 /
// 7000 / 7800. The NMI flip-flop drives SENSE.
wire        s26_req, s26_wr, s26_mio, s26_ene, s26_dc, s26_intack;
wire [14:0] s26_ad;
wire  [7:0] s26_dw, s26_dr;
wire  [1:0] s26_ph;
reg   [1:0] s26_div = 2'd0;
reg         s26_new = 1'b0, s26_new2 = 1'b0, s26_req_t = 1'b0, s26_mio_t = 1'b1, s26_ene_t = 1'b0, s26_dc_t = 1'b0;
reg         s26_act = 1'b0, s26_io = 1'b0, s26_ene_r = 1'b0, s26_dc_r = 1'b0, s26_w = 1'b0;
reg  [14:0] s26_a = 15'd0;
reg   [7:0] s26_d = 8'd0;
reg   [7:0] sbk_latch = 8'd0;

wire s26_ack = s26 & ce6 & ~pause & hcnt[1:0] == 2'b00 & s26_div == 2'd0;

always @(posedge clk) begin
    if (ce6 && hcnt[1:0] == 2'b00) s26_div <= (s26_div == 2'd2) ? 2'd0 : s26_div + 2'd1;
    s26_new  <= s26_ack;
    s26_new2 <= s26_new;
    if (s26_ack) {s26_req_t, s26_mio_t, s26_ene_t, s26_dc_t} <= {s26_req, s26_mio, s26_ene, s26_dc};
    if (reset | watchdog_reset | ~s26) begin                  // the CPU leaves reset executing the byte at 0000
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
    // Superbike: WRTD (data port) latches D << 4, read back on extended port 00
    if (reset) sbk_latch <= 8'd0;
    else if (s26_new2 && s26_act && s26_io && s26_w && !s26_ene_r && s26_dc_r && bflags7[7]) sbk_latch <= {s26_d[3:0], 4'd0};
end

s2650_cpu s2650
(
    .clk(clk),
    .reset(reset | watchdog_reset | ~s26),
    .req(s26_req),
    .ack(s26_ack),
    .ad(s26_ad),
    .wr(s26_wr),
    .dw(s26_dw),
    .dr(s26_dr),
    .mio(s26_mio),
    .ene(s26_ene),
    .dc(s26_dc),
    .ph(s26_ph),
    .irq(1'b0),
    .intack(s26_intack),
    .ivec(8'h03),
    .sense(~cpu_nmi_n),
    .flag()
);

wire [15:0] s26_zaddr = ~s26_a[12]               ? {2'b00, s26_a[14:13], s26_a[11:0]} :
                        s26_a[11:10] == 2'b11     ? {6'b010000, s26_a[9:0]} :
                        s26_a[11:10] == 2'b10     ? {6'b010100, s26_a[9:0]} :
                        s26_a[10:7] == 4'b1001    ? {8'h58, ~s26_a[7], s26_a[6:0]} :
                        s26_a[10:7] == 4'b1010    ? {13'h0C00, s26_a[2:0]} :
                        s26_a[10:7] == 4'b1011    ? {13'h0D00, s26_a[2:0]} :
                        s26_a[10:8] == 3'b110 && !s26_a[7] ? {13'h0E00, s26_a[2:0]} :
                        s26_a[10:8] == 3'b111 && !s26_a[7] ? {13'h0E00, s26_a[2:0]} :
                        s26_a[10:7] == 4'b1101    ? {13'h0F00, s26_a[2:0]} : 16'hFFFF;
wire        s26_mem  = s26_act & ~s26_io;
assign s26_dr = s26_io ? (s26_ene_r && s26_a[7:0] == 8'h00 ? sbk_latch : 8'h00) : cpu_din;

assign cpu_m1_n   = s26 | z80_m1_n;
assign cpu_mreq_n = s26 ? ~s26_mem : z80_mreq_n;
assign cpu_iorq_n = s26 | z80_iorq_n;
assign cpu_rd_n   = s26 ? ~(s26_mem & ~s26_w) : z80_rd_n;
assign cpu_wr_n   = s26 ? ~(s26_mem & s26_w) : z80_wr_n;
assign cpu_rfsh_n = s26 | z80_rfsh_n;
assign cpu_addr   = s26 ? s26_zaddr : z80_addr;
assign cpu_dout   = s26 ? s26_d : z80_dout;

wire        mem = ~cpu_mreq_n & cpu_rfsh_n;
wire [11:0] ram_idx;
wire        rom_cs, ram_cs, vid_cs, obj_cs, io_cs;
assign      {rom_cs, ram_cs, vid_cs, obj_cs, io_cs, ram_idx} = decode(cpu_addr);
wire  [1:0] io_sel = variant[4:0] == 5'd22 ? cpu_addr[11:10] : cpu_addr[12:11];   // 6000, 6800, 7000, 7800
wire        jb     = variant[4:0] == 5'd4;
wire        ay_cs  = jb && cpu_addr[15:9] == 7'b0101100;     // 5800 data, 5900 address
wire        prot_cs = jb && cpu_addr[15:12] == 4'hB;
wire        fg      = variant[4:0] == 5'd5;
wire        sc      = variant[4:0] == 5'd6;
wire        sb      = variant[4:0] == 5'd7;
wire        tu      = variant[4:0] == 5'd8;
wire        ff      = variant[4:0] == 5'd9;                           // Frog (Falcon)
wire        fa      = variant[4:0] == 5'd10;                          // Frogger (AM)
wire        ts      = variant[4:0] == 5'd11;                          // Turpin (S)
wire        st2     = variant[4:0] == 5'd12;                          // Stern type 2
wire        hb      = variant[4:0] == 5'd13;                          // Hustler bootleg
wire        hb6     = variant[4:0] == 5'd14;                          // Hustler bootleg without PPIs
wire        mr      = variant[4:0] == 5'd15;                          // Mars / Mr. Kougar
wire        mr_lat  = mr && cpu_addr[15:4] == 12'h680;
wire        mmk_rom = ext_mode[3:0] == 4'd9 && cpu_addr[15:14] == 2'b11;   // Mighty Monkey ROM C000-FFFF
wire        hsk     = variant[4:0] == 5'd16;                          // Hot Shocker
wire        tp      = variant[4:0] == 5'd17;                          // Triple Punch
wire        gs      = variant[4:0] == 5'd18;                          // Scramble bootleg, Galaxian I/O
wire        sb2     = variant[4:0] == 5'd19;                          // Scramble bootleg, bit-wide inputs
wire        tzb     = variant[4:0] == 5'd20;                          // Tazz-Mania bootleg
wire        ck2     = variant[4:0] == 5'd23;                          // Crazy Kong on Scramble
wire        ami     = variant[4:0] == 5'd24;                          // Amigo
wire        mdk     = variant[4:0] == 5'd21;                          // Mandinka: latches A000, watchdog A800, PPIs B000 / B800
wire        hb_lat  = (hb || hb6) && cpu_addr[15:4] == 12'hA80;
wire        st2_lat = st2 && cpu_addr[15:4] == 12'hB00;
wire        tnv     = sc && bflags5[7];                               // Turpin NV
wire        tnv_rom = tnv && cpu_addr[15:12] == 4'hC;                 // C000-CFFF = ROM 4000-4FFF
wire        fg_lat  = fg && cpu_addr[15:11] == 5'b10111;              // B800-BFFF
wire        tu_lat  = (tu && cpu_addr[15] && cpu_addr[13:11] == 3'b100) ||   // A000-A7FF
                      (ami && cpu_addr[15:11] == 5'b10100);
wire        ff_lat  = ff && cpu_addr[15:11] == 5'b10101;              // A800-AFFF, index A3-A1
wire        x_lat   = (fa && cpu_addr[15:4] == 12'hB80) ||            // B800-B80F (Frogger AM)
                      (ts && cpu_addr[15:4] == 12'hA80);              // A800-A80F (Turpin S), index A2-A0
wire        k_lat   = (sc && !tnv && cpu_addr[15:11] == 5'b01101) || // 6800 (Scramble / The End / Triple Punch)
                      ((tp || sb2) && cpu_addr[15:11] == 5'b01101) ||
                      (sb && !mmk_rom && cpu_addr[15] && cpu_addr[13:11] == 3'b101) || // A800 (Super Cobra)
                      (mdk && cpu_addr[15:11] == 5'b10100) ||         // A000 (Mandinka)
                      (ck2 && cpu_addr[15:4] == 12'hA80);             // A800 (Crazy Kong on Scramble)
wire        fg_wd   = (fg && cpu_addr[15:11] == 5'b10001) ||          // 8800 watchdog
                      (sc && (cpu_addr[15:11] == 5'b01110 || (bflags5[4] && cpu_addr[15:11] == 5'b01111))) || // 7000 (+ 7800)
                      (sb && !mmk_rom && cpu_addr[15] && cpu_addr[13:11] == 3'b110) ||   // B000
                      (tu && cpu_addr[15] && cpu_addr[13:11] == 3'b101) ||               // A800
                      (ff && cpu_addr[15:11] == 5'b10111) ||                             // B800
                      (fa && cpu_addr == 16'h8800) || (ts && cpu_addr == 16'hB800) ||
                      (st2 && cpu_addr == 16'h9800) || (hb && cpu_addr == 16'hB000) || ((mr || tp) && cpu_addr == 16'h7000) ||
                      (sb2 && cpu_addr[15:3] == 13'h0E00) || (tzb && cpu_addr == 16'h9800) ||
                      (mdk && cpu_addr == 16'hA800) || (ck2 && cpu_addr == 16'hB000) || (ami && cpu_addr == 16'hA800) || (sc && bflags9[6] && cpu_addr[15:11] == 5'b01101);
wire        fg_ppi  = (fg && cpu_addr[15:14] == 2'b11) || (sc && cpu_addr[15] && !tnv_rom && !mmk_rom) ||    // PPIs
                      (ff && cpu_addr[15:14] == 2'b11) || (fa && cpu_addr[15:10] == 6'b010000) ||
                      (ts && (cpu_addr[15:2] == 14'h2800 || cpu_addr[15:2] == 14'h3000)) ||
                      (st2 && (cpu_addr[15:4] == 12'hA00 || cpu_addr[15:4] == 12'hA80)) ||
                      (hb && cpu_addr[15:10] == 6'b110000) ||
                      (mr && (cpu_addr[15:4] == 12'h810 || cpu_addr[15:4] == 12'h820)) ||
                      (tp && cpu_addr[15:8] == 8'h81) ||
                      (mdk && cpu_addr[15:12] == 4'hB) || (ck2 && cpu_addr[15:12] == 4'h7) ||
                      (mr && bflags7[4] && (cpu_addr[15:4] == 12'hC10 || cpu_addr[15:4] == 12'hC20)) ||
                      (sb && !mmk_rom && cpu_addr[15] && (cpu_addr[13:11] == 3'b011 || cpu_addr[13:11] == 3'b100)) ||
                      (tu && cpu_addr[15] && cpu_addr[13:12] == 2'b11);

// one write strobe per CPU write cycle
reg  wr_d = 1'b1;
always @(posedge clk) wr_d <= cpu_wr_n;
wire wr = s26 ? s26_new2 & s26_mem & s26_w : mem & ~cpu_wr_n & wr_d;

// video RAM is fetched by the tile generator all through the active area: the CPU waits until HBLANK or VBLANK
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
    else if (wr && k_lat) ctl_9n[cpu_addr[2:0]] <= cpu_dout[0];      // 1 NMI, 3 blue background, 4 stars, 6/7 flip
    else if (wr && ff_lat) begin
        case (cpu_addr[3:1])
            3'd1: ctl_9n[6] <= cpu_dout[0];
            3'd2: ctl_9n[1] <= cpu_dout[0];
            3'd3: ctl_9n[7] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && x_lat) ctl_9n[cpu_addr[2:0]] <= cpu_dout[0];      // 1 NMI, 6/7 flip
    else if (wr && hb_lat) begin                                     // Hustler bootlegs: A801 NMI
        case (cpu_addr[2:0])
            3'd1: ctl_9n[1] <= cpu_dout[0];
            3'd2: if (hb6) ctl_9n[6] <= cpu_dout[0];                 // A802 flip X (hustlerb6)
            3'd6: ctl_9n[7] <= cpu_dout[0];                          // A806 flip Y
            3'd7: if (hb) ctl_9n[6] <= cpu_dout[0];                  // A807 flip X (hustlerb)
            default: ;
        endcase
    end
    else if (wr && sb2 && cpu_addr == 16'h7800) pitch <= cpu_dout;
    else if (wr && hsk && cpu_addr == 16'h6004) begin ctl_9n[6] <= cpu_dout[0]; ctl_9n[7] <= cpu_dout[0]; end
    else if (wr && hsk && cpu_addr == 16'h6006) gfxbank[1:0] <= cpu_dout[1:0];
    else if (wr && hsk && cpu_addr == 16'h6801) ctl_9n[1] <= cpu_dout[0];
    else if (wr && mr_lat) begin                                     // 6801 stars (Mr. Kougar NMI), 6802 NMI, 6809/B flip
        case (cpu_addr[3:0])
            4'h1: if (bflags8[1]) ctl_9n[1] <= cpu_dout[0]; else ctl_9n[4] <= cpu_dout[0];
            4'h2: if (!bflags8[1]) ctl_9n[1] <= cpu_dout[0];
            4'h9: ctl_9n[6] <= cpu_dout[0];
            4'hB: ctl_9n[7] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && st2_lat && bflags6[0]) begin                      // Tazz-Mania 3: B000 stars, B001 NMI, B00C/E flip
        case (cpu_addr[3:0])
            4'h0: ctl_9n[4] <= cpu_dout[0];
            4'h1: ctl_9n[1] <= cpu_dout[0];
            4'h2: if (bflags6[4]) ctl_9n[3] <= cpu_dout[0];          // Tazz-Mania ET background enable
            4'hC: ctl_9n[7] <= cpu_dout[0];
            4'hE: ctl_9n[6] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && st2_lat) begin                                    // B000 stars (G), B002 (B / bg), B004 NMI, B00A (R),
        case (cpu_addr[3:1])                                          // B00C flip Y, B00E flip X
            3'd0: if (bflags6[3]) bg_rgb[1] <= cpu_dout[0]; else ctl_9n[4] <= cpu_dout[0];
            3'd1: if (bflags6[3]) bg_rgb[0] <= cpu_dout[0]; else if (bflags6[4]) ctl_9n[3] <= cpu_dout[0];
            3'd2: ctl_9n[1] <= cpu_dout[0];
            3'd5: if (bflags6[3]) bg_rgb[2] <= cpu_dout[0];
            3'd6: ctl_9n[7] <= cpu_dout[0];
            3'd7: ctl_9n[6] <= cpu_dout[0];
            default: ;
        endcase
    end
    else if (wr && tnv && cpu_addr[15:11] == 5'b01101) begin          // Turpin NV 6800
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
            // Jump Bug 6002-6006 = gfx banks 0-4
            2'd0: if (jb) case (cpu_addr[2:0])
                      3'd2: gfxbank[1:0] <= {1'b0, cpu_dout[0]};
                      3'd3: gfxbank[2] <= cpu_dout[0];
                      3'd4: gfxbank[3] <= cpu_dout[0];
                      3'd6: gfxbank4 <= cpu_dout[0];
                      default: ;
                  endcase
                  else if (cpu_addr[2]) lfo_9m[cpu_addr[1:0]] <= cpu_dout[0];
                  else if (cpu_addr[1:0] == 2'd0 || (cpu_addr[1:0] == 2'd2 && bflags[5])) gfxbank[1:0] <= cpu_dout[1:0];
                  else if (cpu_addr[1:0] != 2'd3) gfxbank[cpu_addr[1:0] + 2'd1] <= cpu_dout[0];
            2'd1: snd_9l[cpu_addr[2:0]] <= cpu_dout[0];
            2'd2: ctl_9n[cpu_addr[2:0]] <= cpu_dout[0];
            2'd3: pitch <= cpu_dout;
        endcase
    end
end

// NMI flip-flop: set at VBLANK, held clear while the enable latch is 0; watchdog = 8 frames (MAME)
wire nmi_en = (bflags[0] ? ctl_9n[0] : ctl_9n[1]) & ~bflags7[4];
wire wdr    = (mem & ~cpu_rd_n & ((io_cs & io_sel == 2'd3) | fg_wd)) | (wr & hsk & cpu_addr == 16'h7000);

always @(posedge clk) begin
    if (!nmi_en)                  cpu_nmi_n <= 1'b1;
    else if (ce6 & rising_vblank) cpu_nmi_n <= 1'b0;

    // New Sinbad 7 (MAME irq0_line_hold): IRQ from VBLANK until acknowledged
    if (reset | ~bflags7[4] | (~cpu_iorq_n & ~cpu_m1_n)) cpu_int_n <= 1'b1;
    else if (ce6 & rising_vblank)                       cpu_int_n <= 1'b0;

    if (reset | wdr | pause)      watchdog <= 4'd0;
    else if (ce6 & rising_vblank) watchdog <= watchdog_reset ? 4'd0 : watchdog + 4'd1;
end

//---------------------------------------------------------- Memories ----------------------------------------------------------//

wire [7:0] rom_q, ram_q, vram_q, obj_q;

// hiscore.dat ranges in video RAM (on-screen high score digits) reach it while the CPU is paused
wire [16:0] hs_dec = decode(hs_address);
wire [11:0] hs_idx = hs_dec[11:0];
wire        hs_vid = hs_dec[14];
wire  [7:0] hs_ram_q;
assign      hs_data_out = hs_vid ? vram_q : hs_ram_q;

// Fantastic (MAME init_fantastc): 1K block i of 0000-7FFF comes from 4K block lut[i], quarter i & 3
function [2:0] fa_lut(input [4:0] i);
    case (i)
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

// Zig Zag swaps ROMs 2000 / 3000 with the 7002 latch
// Cavelon (MAME init_cavelon): every access to 8000-FFFF flips the bank; bank 1 (power-on) = ROM 4000-5FFF at 0000
reg  cav_bank = 1'b1;
reg  cav_acc_d = 1'b0;
wire cav_acc = bflags8[5] & mem & cpu_addr[15] & ~(cpu_rd_n & cpu_wr_n);
always @(posedge clk) begin
    cav_acc_d <= cav_acc;
    if (reset) cav_bank <= 1'b1;
    else if (cav_acc & ~cav_acc_d) cav_bank <= ~cav_bank;
end

wire [15:0] rom_a = tnv_rom ? {4'h4, cpu_addr[11:0]} :
                    bflags8[0] ? {cpu_addr[15:4], cpu_addr[2], cpu_addr[0], cpu_addr[3], cpu_addr[1]} :
                    bflags9[3] ? {cpu_addr[15:5], cpu_addr[1], cpu_addr[0], cpu_addr[3], cpu_addr[4], cpu_addr[2]} :
                    bflags9[5] ? {cpu_addr[15:8], ~cpu_addr[7:0]} :
                    bflags8[5] && cav_bank && cpu_addr[15:13] == 3'b000 ? {3'b010, cpu_addr[12:0]} :
                    bflags6[2] && !cpu_addr[12] && cpu_addr[15:13] < 3'd3 ? {cpu_addr[15:10], ~cpu_addr[9:0]} :
                    bflags4[2] && !cpu_addr[15] ? {1'b0, fa_lut(cpu_addr[14:10]), cpu_addr[11:10], cpu_addr[9:0]} :
                    bflags4[1] && cpu_addr[15:13] == 3'b001 ? {cpu_addr[15:13], cpu_addr[12] ^ ctl_9n[2], cpu_addr[11:0]} :
                    cpu_addr;

dpram_dc #(.widthad_a(16)) prog_rom
(
    .clock_a(clk), .address_a(ioctl_addr[15:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr0 & prog_cs),
    .clock_b(clk), .address_b(rom_a), .q_b(rom_q)
);

dpram_dc #(.widthad_a(12)) work_ram
(
    .clock_a(clk), .address_a(ram_idx), .data_a(cpu_dout), .wren_a(wr & ram_cs), .q_a(ram_q),
    .clock_b(clk), .address_b(hs_idx), .data_b(hs_data_in), .wren_b(hs_write & ~hs_vid), .q_b(hs_ram_q)
);

// Moon Cresta program decryption (MAME decode_mooncrst): all of 0000-3FFF, or opcode fetches only (Moon Quasar)
function [7:0] mc_decrypt(input [7:0] d, input a0);
    reg [7:0] r;
    begin
        r = d ^ {1'b0, d[1], 3'b000, d[5], 2'b00};
        mc_decrypt = a0 ? r : {r[7], r[2], r[5:3], r[6], r[1:0]};
    end
endfunction

wire       decrypt = cpu_addr[15:14] == 2'b00 && (bflags[3] || (bflags[4] && !cpu_m1_n));
wire       hus_rom = cpu_addr[15:14] == 2'b00;
wire [7:0] rom_d   = bflags8[4] && cpu_addr == 16'h2EF9 ? 8'hC9 : decrypt ? mc_decrypt(rom_q, cpu_addr[0]) : bflags3[3] ? cm_decrypt(rom_q, cpu_addr[2:0]) :
                     bflags6[5] && hus_rom ? hus_decrypt(rom_q, cpu_addr[7:0]) :
                     bflags6[6] && hus_rom ? bil_decrypt(rom_q, cpu_addr[7:0]) :
                     bflags9[0] && cpu_addr < 16'h6000 ? sce_decrypt(rom_q, cpu_addr[7:0]) :
                     bflags10[0] ? vic_decrypt(rom_q, cpu_addr[7:0]) :
                     bflags10[3] && cpu_addr < 16'h4000 ? rom_q ^ mmk_x :
                     bflags10[2] && cpu_addr < 16'h4000 ? crz_decrypt(rom_q, cpu_addr[0]) :
                     bflags9[1] && cpu_addr < 16'h1000 ? rom_q ^ (cpu_addr[9] ? (cpu_addr[7] ? 8'h10 : 8'h12) :
                                                                               (cpu_addr[7] ? 8'h82 : 8'h92)) : rom_q;

// Mighty Monkey (MAME init_mimonkey): rows 8-15 of the table repeat rows 0-7, so A9 drops out
reg [7:0] mmk_x;
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

// Victory (MAME decode_victoryc): XOR by A7 / A5 / A2 / A0, then D6 D3 D5 D4 D2 D7 D1 D0
function [7:0] vic_decrypt(input [7:0] d, input [7:0] a);
    reg [7:0] x;
    begin
        x = d ^ {a[7], a[2], 3'b000, a[5], 2'b00} ^ {4'b0000, a[0], 3'b000};
        vic_decrypt = {x[6], x[3], x[5], x[4], x[2], x[7], x[1], x[0]};
    end
endfunction

// Crazy Mazey (MAME init_crazym): XOR chosen by D5-D3 of the stored byte and A0
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

// Super Cobra (E) (MAME init_scobrae): XOR by the low address bits (A6-A0, mirrored when A7), then inverted
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

// Jump Bug protection reads (MAME jumpbug_protection_r)
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

// Check Man (Japan) protection (MAME checkmaj_protection_r, keyed on the PC after the LD A,(3800) operand) and Dingo
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

// Check Man program decryption (MAME decode_checkman): per A2-A0, up to two data bits XORed with others
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

// PC-keyed protection reads (MAME pc() = the address after the instruction): an I/O read follows the instruction's
// last memory read, a memory read follows the one before it
reg  [15:0] last_rd = 16'd0, prev_rd = 16'd0;
reg         mrd_d   = 1'b0;
wire        mrd     = mem & ~cpu_rd_n;
always @(posedge clk) begin
    mrd_d <= mrd;
    if (mrd & ~mrd_d) begin prev_rd <= last_rd; last_rd <= cpu_addr; end
end
wire [15:0] tp_pc  = last_rd + 16'd1;
wire [15:0] mr_pc  = prev_rd + 16'd1;

// Scramble bootleg on Galaxian I/O (MAME scramblb_protection_1_r / _2_r)
wire  [7:0] sbp1 = mr_pc == 16'h01DA ? 8'h80 : 8'h00;
wire  [7:0] sbp2 = mr_pc == 16'h01CA ? 8'h90 : 8'h00;

// Triple Punch (MAME triplep_pip_r / _pap_r)
wire  [7:0] tp_pip = tp_pc == 16'h015A ? 8'hFF : tp_pc == 16'h0886 ? 8'h05 : 8'h00;
wire  [7:0] tp_pap = tp_pc == 16'h015D ? 8'h04 : 8'h00;

// Konami PPIs: 0 = IN0 / IN1 / IN2, 1 = sound command / sound control / IN3
wire [7:0] ppi0_q, ppi1_q, ppi1_pa, ppi1_pb;
wire       ppi0_sel = fg_ppi & (fg ? cpu_addr[13] : ff ? cpu_addr[12] : sc | fa | hb | mr | tp ? cpu_addr[8] : tu ? ~cpu_addr[11] :
                                ts ? cpu_addr[15:13] == 3'b101 : st2 | mdk | ck2 ? ~cpu_addr[11] : cpu_addr[13:11] == 3'b011);
wire       ppi1_sel = fg_ppi & (fg ? cpu_addr[12] : ff ? cpu_addr[13] : sc | fa | hb | mr | tp ? cpu_addr[9] : tu ?  cpu_addr[11] :
                                ts ? cpu_addr[15:13] == 3'b110 : st2 | mdk | ck2 ?  cpu_addr[11] : cpu_addr[13:11] == 3'b100);
wire [1:0] ppi_a    = fg ? cpu_addr[2:1] : ff ? cpu_addr[4:3] : tu ? cpu_addr[5:4] : mr ? {cpu_addr[3], cpu_addr[1]} :
                      st2 && !bflags6[0] ? cpu_addr[3:2] : cpu_addr[1:0];
// Frogger (AM): the PPI data bus is wired bit-reversed (both directions)
wire [7:0] ppi_q0   = (ppi0_sel ? ppi0_q : 8'hFF) & (ppi1_sel ? ppi1_q : 8'hFF);
wire [7:0] ppi_q    = fa ? {ppi_q0[0], ppi_q0[1], ppi_q0[2], ppi_q0[3], ppi_q0[4], ppi_q0[5], ppi_q0[6], ppi_q0[7]} : ppi_q0;
wire [7:0] ppi_din  = fa ? {cpu_dout[0], cpu_dout[1], cpu_dout[2], cpu_dout[3], cpu_dout[4], cpu_dout[5], cpu_dout[6], cpu_dout[7]} : cpu_dout;

// Scramble / The End protection (MAME theend_protection_w / _r, a PAL at 6J): nibbles written to PPI 1 port C
// shift through a 12-bit state; the low nibble is the operation. IN2 bits 5 and 7 read ~result[7].
wire       prot     = bflags5[3];
wire [7:0] ppi1_pc;
wire       ppi1_pc_we;
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

galaxian_ppi ppi0
(
    .clk(clk), .reset(reset), .addr(ppi_a), .din(ppi_din), .we(wr & ppi0_sel), .dout(ppi0_q),
    .pa_in(in0), .pb_in(in1), .pc_in(in2_k), .pa_out(), .pb_out(), .pc_out(), .pc_we()
);

galaxian_ppi ppi1
(
    .clk(clk), .reset(reset), .addr(ppi_a), .din(ppi_din), .we(wr & ppi1_sel), .dout(ppi1_q),
    .pa_in(8'hFF), .pb_in(8'hFF), .pc_in(prot ? prot_res : bflags6[1] ? 8'hFC : bflags8[2] ? 8'h00 : in3), .pa_out(ppi1_pa), .pb_out(ppi1_pb),
    .pc_out(ppi1_pc), .pc_we(ppi1_pc_we)
);

wire [7:0] ay_dout, ay2_dout;

// Hustler bootleg without PPIs: 4800 write = sound command, 5000 = sound control
reg  [7:0] hb6_ctl = 8'd0;
always @(posedge clk) if (reset) hb6_ctl <= 8'd0; else if (wr && (hb6 || ami) && cpu_addr == 16'h5000) hb6_ctl <= cpu_dout;
wire       snd_cmd_we = hb6 ? wr && cpu_addr == 16'h4800 : ami ? wr && cpu_addr == 16'h4000 :
                        hsk ? wr && cpu_addr == 16'h8000 : wr & ppi1_sel & ppi_a == 2'd0;
wire [7:0] snd_ctl    = hsk ? 8'h00 : (hb6 || ami ? hb6_ctl : ppi1_pb) & ~{3'b000, bflags8[3], 4'b0000};
wire       snd_irq    = wr & hsk & cpu_addr == 16'h9000;

// Hustler / Billiard (MAME init_hustler / init_billiard): 0000-3FFF XOR-masked from A7-A0 (Billiard also shuffled)
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
wire       io_rd = ~cpu_iorq_n & cpu_m1_n & ~cpu_rd_n;

// Fantastic AYs: 8803 address / 880B data / 8807 read, second 880C address / 880E data / 880D read
wire       fa_cs = bflags4[3] && mem && cpu_addr[15:4] == 12'h880;

always @(*) begin
    cpu_din = 8'hFF;
    if (io_rd) cpu_din = bflags2[2] && cpu_addr[7:0] == 8'h02 ? ay_dout :
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
    else if (ami && cpu_addr[15:2] == 14'h1000)                     // 4000-4003 IN0-IN3 (Amigo)
        cpu_din = cpu_addr[1:0] == 2'd0 ? in0 : cpu_addr[1:0] == 2'd1 ? in1 : cpu_addr[1:0] == 2'd2 ? in2 : in3;
    else if (hsk && cpu_addr[15:2] == 14'h2000)                     // 8000-8003 IN0-IN3
        cpu_din = cpu_addr[1:0] == 2'd0 ? in0 : cpu_addr[1:0] == 2'd1 ? in1 : cpu_addr[1:0] == 2'd2 ? in2 : in3;
    else if (hb6 && cpu_addr[15:2] == 14'h1200)                      // 4800 IN0, 4801 IN1, 4803 IN2
        cpu_din = cpu_addr[1:0] == 2'd0 ? in0 : cpu_addr[1:0] == 2'd1 ? in1 : cpu_addr[1:0] == 2'd3 ? in2 : 8'hFF;
    else if (tnv_rom) cpu_din = rom_d;
    else if (fa_cs) cpu_din = cpu_addr[3:0] == 4'h7 ? ay_dout : cpu_addr[3:0] == 4'hD ? ay2_dout : 8'hFF;
    else if (prot_cs) cpu_din = prot_q;
    else if (cm_prot) cpu_din = cm_prot_q;
    else if (dg_prot) cpu_din = cpu_addr[0] ? 8'h8C : 8'hAA;
    else if (rom_cs) cpu_din = rom_d;
    else if (ram_cs) cpu_din = ram_q;
    else if (vid_cs) cpu_din = vram_q;
    else if (obj_cs) cpu_din = obj_q;
    else if (io_cs) case (io_sel)
        2'd0: cpu_din = in0;
        2'd1: cpu_din = in1;
        2'd2: cpu_din = bflags2[3] ? in3 : in2;
        2'd3: cpu_din = 8'hFF;
    endcase
end

//----------------------------------------------------------- Video ------------------------------------------------------------//

// object RAM is 256 bytes mirrored, except Crazy Kong's 1K
wire [9:0] obj_idx = {variant[4:0] == 5'd3 || variant[4:0] == 5'd22 || ck2 || bflags4[0] ? cpu_addr[9:8] : 2'b00, cpu_addr[7] ^ bflags6[7], cpu_addr[6:0]};
wire n3a;
// Mighty Monkey: latches 0 / 2 are gfx banks, latch 4 the background enable, no stars
wire mmk = ext_mode[3:0] == 4'd9;

galaxian_video video
(
    .clk(clk),
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
    .ext_mode(ext_mode[3:0]),
    .vflags2(vflags2[3:0]),
    .vflags3(vflags3[7:0]),
    .vflags4(vflags4),
    .vflags5(vflags5[3:0]),
    .bg_en(mmk ? ctl_9n[4] : ctl_9n[3]),
    .bg_rgb(bg_rgb),
    .gfxbank(mmk ? {ctl_9n[2], 2'b00, ctl_9n[0]} : gfxbank),
    .gfxbank4(gfxbank4),
    .stars_232(bflags2[5]),

    .cpu_addr(pause ? hs_address[9:0] : obj_cs ? obj_idx : cpu_addr[9:0]),
    .cpu_dout(pause ? hs_data_in : cpu_dout),
    .vram_we(pause ? hs_write & hs_vid : wr & vid_cs),
    .obj_we(wr & obj_cs),
    .vram_q(vram_q),
    .obj_q(obj_q),

    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .gfx0_we(ioctl_wr0 & gfx0_cs),
    .gfx1_we(ioctl_wr0 & gfx1_cs),
    .gfx2_we(ioctl_wr0 & gfx2_cs),
    .pal_we(ioctl_wr0 & pal_cs),
    .bgp_we(ioctl_wr0 & bgp_cs),

    .n3a(n3a),

    .r(video_r),
    .g(video_g),
    .b(video_b)
);

//----------------------------------------------------------- Sound ------------------------------------------------------------//

wire signed [15:0] disc_audio, ay_audio;

galaxian_sound sound
(
    .clk(clk),
    .reset(reset),
    .mc(bflags[6]),
    .pdiv8(bflags2[4]),
    .pause(pause),
    .v2(vcnt[1]),
    .n3a(n3a),
    .lfo(lfo_9m),
    .fs(snd_9l[2:0]),
    .hit(snd_9l[3]),
    .fire(snd_9l[5]),
    .vol(snd_9l[7:6]),
    .pitch(pitch),
    .out(disc_audio)
);

// AY-3-8910: Jump Bug 5900 address / 5800 data, Bongo I/O 00 address / 01 data / 02 read (1.536 MHz);
// Check Man sound board (1.78975 MHz, Japan / Dingo 1.62 MHz)
reg [4:0] ay_div = 5'd0;
always @(posedge clk) ay_div <= ay_div + 5'd1;

// 1.78975 MHz = 49.152 MHz x 7159 / 196608, 1.62 MHz = 49.152 MHz x 675 / 20480
reg [17:0] cm_frac = 18'd0;
reg [14:0] cj_frac = 15'd0;
reg        cm_cen = 1'b0, cj_cen = 1'b0;
always @(posedge clk) begin
    if (cm_frac >= 18'd189449) begin cm_frac <= cm_frac - 18'd189449; cm_cen <= 1'b1; end
    else                       begin cm_frac <= cm_frac + 18'd7159;   cm_cen <= 1'b0; end
    if (cj_frac >= 15'd19805)  begin cj_frac <= cj_frac - 15'd19805;  cj_cen <= 1'b1; end
    else                       begin cj_frac <= cj_frac + 15'd675;    cj_cen <= 1'b0; end
end

wire snd_board = bflags3[0];
wire ay_cen    = ~pause & (snd_board ? (bflags3[1] ? cj_cen : cm_cen) : bflags4[5] ? ay_div[3:0] == 4'd0 : ay_div == 5'd0);

wire io_wr   = ~cpu_iorq_n & cpu_m1_n & ~cpu_wr_n;
wire bongo   = bflags2[2];
wire jb_ay   = mem & ~cpu_wr_n & ay_cs;
// Zig Zag: a write to 4900-49FF latches A7-A0 as AY data; 4800-48FF with A0 set writes it (A1 = address)
reg  [7:0] zz_latch = 8'd0;
wire zz_cs = bflags4[4] && cpu_addr[15:11] == 5'b01001;
always @(posedge clk) if (wr && zz_cs && cpu_addr[9:8] == 2'b01) zz_latch <= cpu_addr[7:0];
wire zz_w  = mem & ~cpu_wr_n & zz_cs & cpu_addr[9:8] == 2'b00 & cpu_addr[0];

wire fa_w    = fa_cs & ~cpu_wr_n;
wire fa_r    = fa_cs & ~cpu_rd_n;
wire tp_ay   = bflags8[6];
wire m_bdir  = jb_ay | (bongo & io_wr & cpu_addr[7:1] == 7'd0) | (tp_ay & io_wr & cpu_addr[7:1] == 7'd0) | zz_w |
               (fa_w & (cpu_addr[3:0] == 4'h3 || cpu_addr[3:0] == 4'hB));
wire m_bc1   = (jb_ay & cpu_addr[8]) | (bongo & io_wr & cpu_addr[7:0] == 8'h00) | (bongo & io_rd & cpu_addr[7:0] == 8'h02) |
               (zz_w & cpu_addr[1]) | (fa_w & cpu_addr[3:0] == 4'h3) | (fa_r & cpu_addr[3:0] == 4'h7) |
               (tp_ay & (io_wr | io_rd) & cpu_addr[7:0] == 8'h01);
wire ay2_bdir = fa_w & (cpu_addr[3:0] == 4'hC || cpu_addr[3:0] == 4'hE);
wire ay2_bc1  = (fa_w & cpu_addr[3:0] == 4'hC) | (fa_r & cpu_addr[3:0] == 4'hD);
wire s_bdir, s_bc1;
wire [7:0] s_din, snd_latch;
wire ay_bdir = snd_board ? s_bdir : m_bdir;
wire ay_bc1  = snd_board ? s_bc1  : m_bc1;
wire [7:0] ay_a, ay_b, ay_c;

// sound command: Check Man any OUT, Japan / Dingo a 7800 write; one strobe per CPU cycle
wire cmd_wr = snd_board & (bflags3[2] ? io_wr & wr_d : wr & io_cs & io_sel == 2'd3);

galaxian_sndcpu sndcpu
(
    .clk(clk),
    .reset(reset | ~snd_board),
    .mode(bflags3[1]),
    .pause(pause),
    .cmd_wr(cmd_wr),
    .cmd(cpu_dout),
    .vblank_irq(ce6 & rising_vblank),
    .line8_irq(ce6 & vcnt_step & vcnt[2:0] == 3'd7),
    .rom_addr(ioctl_addr[11:0]),
    .rom_data(ioctl_dout),
    .rom_we(ioctl_wr0 & snd_cs),
    .ay_bdir(s_bdir),
    .ay_bc1(s_bc1),
    .ay_din(s_din),
    .ay_dout(ay_dout),
    .latch(snd_latch)
);

jt49_bus #(.COMP(3'b010)) ay
(
    .rst_n(~reset),
    .clk(clk),
    .clk_en(ay_cen),
    .bdir(ay_bdir),
    .bc1(ay_bc1),
    .din(snd_board ? s_din : bflags4[4] ? zz_latch : cpu_dout),
    .sel(1'b1),
    .dout(ay_dout),
    .sound(),
    .A(ay_a),
    .B(ay_b),
    .C(ay_c),
    .sample(),
    .IOA_in(snd_board ? snd_latch : in3),
    .IOA_out(),
    .IOB_in(8'hFF),
    .IOB_out()
);

wire [7:0] ay2_a, ay2_b, ay2_c;

jt49_bus #(.COMP(3'b010)) ay2
(
    .rst_n(~reset),
    .clk(clk),
    .clk_en(ay_cen),
    .bdir(ay2_bdir),
    .bc1(ay2_bc1),
    .din(cpu_dout),
    .sel(1'b1),
    .dout(ay2_dout),
    .sound(),
    .A(ay2_a),
    .B(ay2_b),
    .C(ay2_c),
    .sample(),
    .IOA_in(8'hFF),
    .IOA_out(),
    .IOB_in(8'hFF),
    .IOB_out()
);

// AC coupling approximated by the DC remover (as the Crazy Climber core); two AYs at half weight each (MAME 0.25)
wire [9:0]  ay_sum  = {2'b00, ay_a} + {2'b00, ay_b} + {2'b00, ay_c};
wire [10:0] ay_sum2 = {1'b0, ay_sum} + {3'b000, ay2_a} + {3'b000, ay2_b} + {3'b000, ay2_c};
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

wire signed [15:0] konami_audio;

galaxian_konami_snd konami_snd
(
    .clk(clk),
    .reset(reset | ~bflags5[0]),
    .two_ay(bflags5[1]),
    .fr_timer(bflags5[5]),
    .timer_9000(bflags5[6]),
    .no_filter(bflags7[0]),
    .hb_map(bflags7[1]),
    .rom12k(bflags7[2]),
    .hs_map(hsk),
    .irq_set(snd_irq),
    .pause(pause),
    .latch_we(snd_cmd_we),
    .latch_d(ppi_din),
    .control(snd_ctl),
    .rom_addr(ioctl_addr[13:0]),
    .rom_data(ioctl_dout),
    .rom_we(ioctl_wr0 & snd_cs),
    .rom_swap01(bflags5[2]),
    .out(konami_audio)
);

// discrete (unless cut) plus AY plus the Konami board; a sound source that is idle stays at 0
wire signed [17:0] mix = (bflags2[1] ? 18'sd0 : {{2{disc_audio[15]}}, disc_audio}) + {{2{ay_audio[15]}}, ay_audio} +
                         {{2{konami_audio[15]}}, konami_audio};
assign audio = mix > 18'sd32767 ? 16'sd32767 : mix < -18'sd32767 ? -16'sd32767 : mix[15:0];

endmodule
