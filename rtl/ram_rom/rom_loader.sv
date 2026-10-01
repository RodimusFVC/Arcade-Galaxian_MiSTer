//============================================================================
//
//  Galaxian ROM loader
//  ROM layout matched to MAME galaxian.cpp regions
//
//============================================================================

// ioctl index 0 (MRA), all images stored exactly as dumped:
//   0x00000 - 0x0FFFF  main CPU          "maincpu"
//   0x10000 - 0x11FFF  gfx plane 0       "gfx1" first half
//   0x12000 - 0x13FFF  gfx plane 1       "gfx1" second half
//   0x14000 - 0x1403F  colour PROM       "proms" (64 bytes: Driving Force)
//   0x14100 - 0x1413F  background PROM   "user1" (Strategy X, Mariner)
//   0x14140 - 0x1415F  Mariner PROM      "user2" (char bank, star columns)
//   0x16000 - 0x16FFF  gfx plane 2       "gfx1" third plane (New Sinbad 7, 3 bits per pixel)
//   0x18000 - 0x1BFFF  sound CPU         "audiocpu"
//   0x1C000 - 0x1DFFF  sample ROM        "cclimber_audio:samples" (Moon Shuttle)
//   0x1E000 - 0x1E7FF  speech CPU        "i8039" (Space Battle)
//   0x1F000 - 0x1FFFF  speech data       "sbhoei_sound_rom" (Space Battle)
//   0x20000 - 0x22FFF  speech ROM        "digitalker" (Scorpion)
//   0x24000 - 0x27FFF  gfx planes 0 / 1 upper 8K (16K planes: Rack + Roll)
//
// ioctl index 1: board variant, flags and input map (see the top level)
// ioctl indexes 3 and 4 are reserved for hiscore config and NVRAM

module selector
(
    input  logic [24:0] ioctl_addr,
    output logic        prog_cs,
    output logic        snd_cs,
    output logic        bgp_cs,
    output logic        gfx0_cs,
    output logic        gfx1_cs,
    output logic        gfx2_cs,
    output logic        pal_cs,
    output logic        samp_cs,
    output logic        sbp_cs,
    output logic        sbd_cs,
    output logic        dk_cs,
    output logic        gfxh_cs
);
    always_comb begin
        {prog_cs, gfx0_cs, gfx1_cs, gfx2_cs, pal_cs, snd_cs, bgp_cs, samp_cs, sbp_cs, sbd_cs, dk_cs, gfxh_cs} = '0;

        if      (ioctl_addr < 25'h10000) prog_cs = 1'b1;
        else if (ioctl_addr < 25'h12000) gfx0_cs = 1'b1;
        else if (ioctl_addr < 25'h14000) gfx1_cs = 1'b1;
        else if (ioctl_addr < 25'h14040) pal_cs  = 1'b1;
        else if (ioctl_addr >= 25'h14100 && ioctl_addr < 25'h14160) bgp_cs = 1'b1;
        else if (ioctl_addr >= 25'h16000 && ioctl_addr < 25'h17000) gfx2_cs = 1'b1;
        else if (ioctl_addr >= 25'h18000 && ioctl_addr < 25'h1C000) snd_cs = 1'b1;
        else if (ioctl_addr >= 25'h1C000 && ioctl_addr < 25'h1E000) samp_cs = 1'b1;
        else if (ioctl_addr >= 25'h1E000 && ioctl_addr < 25'h1E800) sbp_cs = 1'b1;
        else if (ioctl_addr >= 25'h1F000 && ioctl_addr < 25'h20000) sbd_cs = 1'b1;
        else if (ioctl_addr >= 25'h20000 && ioctl_addr < 25'h23000) dk_cs = 1'b1;
        else if (ioctl_addr >= 25'h24000 && ioctl_addr < 25'h28000) gfxh_cs = 1'b1;
    end
endmodule
