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
                                        // 4 Jump Bug, 5 Frogger
    input         [7:0] vflags,         // [0] Scramble shells, [1] RGB -> GBR harness (Eagle)
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
                                        // [2] first sound ROM D0 / D1 swapped (Frogger)
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
    output        [2:0] dbg,            // DIAG-REVERT-2026-09-29: Konami sound board activity

    // hiscore (CPU paused): work RAM second port; video RAM through the CPU port
    input        [15:0] hs_address,
    input         [7:0] hs_data_in,
    output        [7:0] hs_data_out,
    input               hs_write
);

wire ce6 = (ph == 3'd0);

//------------------------------------------------------- ROM load map --------------------------------------------------------//

wire prog_cs, gfx0_cs, gfx1_cs, pal_cs, snd_cs;

selector rom_selector
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(prog_cs),
    .snd_cs(snd_cs),
    .gfx0_cs(gfx0_cs),
    .gfx1_cs(gfx1_cs),
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
wire [7:0] top = rom_top == 8'd0 ? 8'h40 : rom_top;

// {rom, ram, vid, obj, io, ram index[11:0]}
function [16:0] decode(input [15:0] a);
    reg rom, ram, vid, obj, io;
    reg [11:0] ri;
    begin
        rom = a[15:8] < top;
        ri  = {1'b0, bflags[1] & a[10], a[9:0]};
        case (variant[2:0])
            3'd0: begin
                ram = a[15:11] == 5'b01000;
                vid = a[15:11] == 5'b01010;
                obj = a[15:11] == 5'b01011;
                io  = a[15:13] == 3'b011;
            end
            3'd1: begin
                ram = a[15:11] == 5'b10000;
                vid = a[15:11] == 5'b10010;
                obj = a[15:11] == 5'b10011;
                io  = a[15:13] == 3'b101;
            end
            3'd2: begin
                rom = a < 16'h4000 || (a >= 16'h5000 && a < 16'h6800);
                ram = a[15:11] == 5'b01000 || a[15:10] == 6'b100000;
                ri  = {a[15], a[10:0]};
                vid = a[15:11] == 5'b10010;
                obj = a[15:11] == 5'b10011;
                io  = a[15:13] == 3'b101;
            end
            3'd5: begin
                ram = a[15:11] == 5'b10000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b10101;
                obj = a[15:11] == 5'b10110;
                io  = 1'b0;
            end
            3'd4: begin
                rom = a < 16'h4000 || (a >= 16'h8000 && a < 16'hB000);
                ram = a[15:11] == 5'b01000;
                ri  = {1'b0, a[10:0]};
                vid = a[15:11] == 5'b01001;
                obj = a[15:11] == 5'b01010;
                io  = a[15:13] == 3'b011;
            end
            default: begin
                ram = a[15:11] == 5'b01100 || a[15:10] == 6'b011010;
                ri  = {a[11], a[10:0]};
                vid = a[15:10] == 6'b100100;
                obj = a[15:10] == 6'b100110;
                io  = a[15:13] == 3'b101;
            end
        endcase
        decode = {rom, ram, vid, obj, io, ri};
    end
endfunction

//----------------------------------------------------------- CPU --------------------------------------------------------------//

wire        cpu_m1_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n;
wire [15:0] cpu_addr;
wire  [7:0] cpu_dout;
reg   [7:0] cpu_din;
reg         cpu_nmi_n = 1'b1;
reg         wait_n = 1'b1;

reg   [7:0] ctl_9n = 8'd0;              // 7000-7007: 0/1 NMI enable, 4 stars, 6 flip X, 7 flip Y
reg   [7:0] snd_9l = 8'd0;              // 6800-6807: FS1-3, HIT, -, FIRE, VOL1, VOL2
reg   [3:0] lfo_9m = 4'hF;              // 6004-6007: background LFO DAC
reg   [7:0] pitch  = 8'd0;              // 7800
reg   [3:0] gfxbank = 4'd0;             // 6000-6002: graphics bank 0 (D1-D0), 1, 2 (Moon Cresta, Pisces)
reg         gfxbank4 = 1'b0;            // Jump Bug 6006
reg   [3:0] watchdog = 4'd0;
wire        watchdog_reset = (watchdog == 4'd8) & ~bflags2[0];

T80sed z80
(
    .RESET_n(~(reset | watchdog_reset)),
    .CLK_n(clk),
    .CLKEN(ce6 & hcnt[0] & ~pause),
    .WAIT_n(wait_n),
    .INT_n(1'b1),
    .NMI_n(cpu_nmi_n),
    .BUSRQ_n(1'b1),
    .M1_n(cpu_m1_n),
    .MREQ_n(cpu_mreq_n),
    .IORQ_n(cpu_iorq_n),
    .RD_n(cpu_rd_n),
    .WR_n(cpu_wr_n),
    .RFSH_n(cpu_rfsh_n),
    .HALT_n(),
    .BUSAK_n(),
    .A(cpu_addr),
    .DI(cpu_din),
    .DO(cpu_dout)
);

wire        mem = ~cpu_mreq_n & cpu_rfsh_n;
wire [11:0] ram_idx;
wire        rom_cs, ram_cs, vid_cs, obj_cs, io_cs;
assign      {rom_cs, ram_cs, vid_cs, obj_cs, io_cs, ram_idx} = decode(cpu_addr);
wire  [1:0] io_sel = cpu_addr[12:11];   // 6000, 6800, 7000, 7800
wire        jb     = variant[2:0] == 3'd4;
wire        ay_cs  = jb && cpu_addr[15:9] == 7'b0101100;     // 5800 data, 5900 address
wire        prot_cs = jb && cpu_addr[15:12] == 4'hB;
wire        fg      = variant[2:0] == 3'd5;
wire        fg_lat  = fg && cpu_addr[15:11] == 5'b10111;              // B800-BFFF
wire        fg_wd   = fg && cpu_addr[15:11] == 5'b10001;              // 8800 watchdog
wire        fg_ppi  = fg && cpu_addr[15:14] == 2'b11;                 // C000-FFFF

// one write strobe per CPU write cycle
reg  wr_d = 1'b1;
always @(posedge clk) wr_d <= cpu_wr_n;
wire wr = mem & ~cpu_wr_n & wr_d;

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
wire nmi_en = bflags[0] ? ctl_9n[0] : ctl_9n[1];
wire wdr    = mem & ~cpu_rd_n & ((io_cs & io_sel == 2'd3) | fg_wd);

always @(posedge clk) begin
    if (!nmi_en)                  cpu_nmi_n <= 1'b1;
    else if (ce6 & rising_vblank) cpu_nmi_n <= 1'b0;

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
wire [15:0] rom_a = bflags4[2] && !cpu_addr[15] ? {1'b0, fa_lut(cpu_addr[14:10]), cpu_addr[11:10], cpu_addr[9:0]} :
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
wire [7:0] rom_d   = decrypt ? mc_decrypt(rom_q, cpu_addr[0]) : bflags3[3] ? cm_decrypt(rom_q, cpu_addr[2:0]) : rom_q;

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

// Konami PPIs: 0 = IN0 / IN1 / IN2, 1 = sound command / sound control / IN3
wire [7:0] ppi0_q, ppi1_q, ppi1_pa, ppi1_pb;
wire       ppi0_sel = fg_ppi & cpu_addr[13];
wire       ppi1_sel = fg_ppi & cpu_addr[12];
wire [1:0] ppi_a    = cpu_addr[2:1];

galaxian_ppi ppi0
(
    .clk(clk), .reset(reset), .addr(ppi_a), .din(cpu_dout), .we(wr & ppi0_sel), .dout(ppi0_q),
    .pa_in(in0), .pb_in(in1), .pc_in(in2), .pa_out(), .pb_out(), .pc_out(), .pc_we()
);

galaxian_ppi ppi1
(
    .clk(clk), .reset(reset), .addr(ppi_a), .din(cpu_dout), .we(wr & ppi1_sel), .dout(ppi1_q),
    .pa_in(8'hFF), .pb_in(8'hFF), .pc_in(in3), .pa_out(ppi1_pa), .pb_out(ppi1_pb), .pc_out(), .pc_we()
);

wire [7:0] ay_dout, ay2_dout;
wire       io_rd = ~cpu_iorq_n & cpu_m1_n & ~cpu_rd_n;

// Fantastic AYs: 8803 address / 880B data / 8807 read, second 880C address / 880E data / 880D read
wire       fa_cs = bflags4[3] && mem && cpu_addr[15:4] == 12'h880;

always @(*) begin
    cpu_din = 8'hFF;
    if (io_rd) cpu_din = bflags2[2] && cpu_addr[7:0] == 8'h02 ? ay_dout : 8'hFF;
    else if (fg_ppi) cpu_din = (ppi0_sel ? ppi0_q : 8'hFF) & (ppi1_sel ? ppi1_q : 8'hFF);
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
wire [9:0] obj_idx = {variant[2:0] == 3'd3 || bflags4[0] ? cpu_addr[9:8] : 2'b00, cpu_addr[7:0]};
wire n3a;

galaxian_video video
(
    .clk(clk),
    .ph(ph),
    .hcnt(hcnt),
    .vcnt(vcnt),

    .flip_x(ctl_9n[6] ^ crt_flip),
    .flip_y(ctl_9n[7] ^ crt_flip),
    .crt_flip(crt_flip),
    .stars_on(ctl_9n[4] & ~bflags[2]),
    .bullet_mode(vflags[0]),
    .rgb_gbr(vflags[1]),
    .ext_mode(ext_mode[3:0]),
    .vflags2(vflags2[3:0]),
    .vflags3(vflags3[3:0]),
    .gfxbank(gfxbank),
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
    .pal_we(ioctl_wr0 & pal_cs),

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
wire m_bdir  = jb_ay | (bongo & io_wr & cpu_addr[7:1] == 7'd0) | zz_w |
               (fa_w & (cpu_addr[3:0] == 4'h3 || cpu_addr[3:0] == 4'hB));
wire m_bc1   = (jb_ay & cpu_addr[8]) | (bongo & io_wr & cpu_addr[7:0] == 8'h00) | (bongo & io_rd & cpu_addr[7:0] == 8'h02) |
               (zz_w & cpu_addr[1]) | (fa_w & cpu_addr[3:0] == 4'h3) | (fa_r & cpu_addr[3:0] == 4'h7);
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
    .pause(pause),
    .latch_we(wr & ppi1_sel & ppi_a == 2'd0),
    .latch_d(cpu_dout),
    .control(ppi1_pb),
    .rom_addr(ioctl_addr[12:0]),
    .rom_data(ioctl_dout),
    .rom_we(ioctl_wr0 & snd_cs),
    .rom_swap01(bflags5[2]),
    .out(konami_audio),
    .dbg(dbg)                           // DIAG-REVERT-2026-09-29
);

// discrete (unless cut) plus AY plus the Konami board; a sound source that is idle stays at 0
wire signed [17:0] mix = (bflags2[1] ? 18'sd0 : {{2{disc_audio[15]}}, disc_audio}) + {{2{ay_audio[15]}}, ay_audio} +
                         {{2{konami_audio[15]}}, konami_audio};
assign audio = mix > 18'sd32767 ? 16'sd32767 : mix < -18'sd32767 ? -16'sd32767 : mix[15:0];

endmodule
