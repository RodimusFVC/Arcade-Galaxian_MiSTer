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
//   0x14000 - 0x1401F  colour PROM       "proms"
//   0x14100 - 0x1413F  background PROM   "user1" (Strategy X, Mariner)
//   0x14140 - 0x1415F  Mariner PROM      "user2" (char bank, star columns)
//   0x16000 - 0x16FFF  gfx plane 2       "gfx1" third plane (New Sinbad 7, 3 bits per pixel)
//   0x18000 - 0x1BFFF  sound CPU         "audiocpu"
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
    output logic        pal_cs
);
    always_comb begin
        {prog_cs, gfx0_cs, gfx1_cs, gfx2_cs, pal_cs, snd_cs, bgp_cs} = '0;

        if      (ioctl_addr < 25'h10000) prog_cs = 1'b1;
        else if (ioctl_addr < 25'h12000) gfx0_cs = 1'b1;
        else if (ioctl_addr < 25'h14000) gfx1_cs = 1'b1;
        else if (ioctl_addr < 25'h14020) pal_cs  = 1'b1;
        else if (ioctl_addr >= 25'h14100 && ioctl_addr < 25'h14160) bgp_cs = 1'b1;
        else if (ioctl_addr >= 25'h16000 && ioctl_addr < 25'h17000) gfx2_cs = 1'b1;
        else if (ioctl_addr >= 25'h18000 && ioctl_addr < 25'h1C000) snd_cs = 1'b1;
    end
endmodule
