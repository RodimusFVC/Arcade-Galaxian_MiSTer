//  Based on MAME galaxian.cpp (Aaron Giles, Couriersud, Stephane Humbert, Robbbert, BSD-3-Clause)

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
    output logic        gfxh_cs,
    output logic        tms_cs,
    output logic        tmsp_cs,
    output logic        rcg_cs
);
    always_comb begin
        {prog_cs, gfx0_cs, gfx1_cs, gfx2_cs, pal_cs, snd_cs, bgp_cs, samp_cs, sbp_cs, sbd_cs, dk_cs, gfxh_cs, tms_cs, tmsp_cs, rcg_cs} = '0;

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
        else if (ioctl_addr >= 25'h28000 && ioctl_addr < 25'h2A000) tms_cs  = 1'b1;
        else if (ioctl_addr >= 25'h2A000 && ioctl_addr < 25'h2A020) tmsp_cs = 1'b1;
        else if (ioctl_addr >= 25'h2C000 && ioctl_addr < 25'h2E000) rcg_cs  = 1'b1;
    end
endmodule
