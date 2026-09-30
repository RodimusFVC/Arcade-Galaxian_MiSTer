//============================================================================
//
//  TMS5110 VSM: PROM-driven CTL/PDC sequencer + bit-serial speech ROMs
//  Copyright (C) 2026 Rodimus
//
//  Port of MAME devices/sound/tms5110.cpp tmsprom_device (BSD-3-Clause;
//  Frank Palazzolo, Jarek Burczynski, Aaron Giles, Jonathan Gevaryahu,
//  Couriersud), wired as MAME bagman.cpp
//
//============================================================================

module tmsprom
(
    input             clk,
    input             reset,
    input             ce_romclk,        // PROM clock (chip clock / 2)
    input             chip_busy,
    input             enable,           // LS259 Q3
    input       [2:0] bit_sel,          // speech ROM data bit that is streamed
    input             csq0,             // LS259 Q4: ROM 0 select
    input             csq1,             // LS259 Q5: ROM 1 select (only while Q4 is high)

    input             prom_wr,
    input       [4:0] prom_waddr,
    input       [7:0] prom_wdata,

    output     [12:0] rom_addr,         // speech ROMs, 2 x 4K
    input       [7:0] rom_q,            // registered one clock after rom_addr

    input             m0,               // bit request from the chip (address advances first)
    output            data_bit,
    output reg  [3:0] ctl,
    output reg        pdc
);

(* ramstyle = "logic" *) reg [7:0] prom [0:31];
always_ff @(posedge clk) if (prom_wr) prom[prom_waddr] <= prom_wdata;

reg  [4:0]  prom_cnt;
reg  [11:0] address;
reg         base;
reg         tick_pend, enable_d, csq0_d, csq1_d;

assign rom_addr = {base, address};
assign data_bit = rom_q[bit_sel];

// MAME update_prom_cnt: while enabled, the stop bit of the current entry moves to the upper half
wire [7:0] ctrl_cur = prom[prom_cnt];
wire [4:0] cnt_u    = (enable && ctrl_cur[7]) ? (prom_cnt | 5'h10) : (prom_cnt & 5'h0F);
wire [7:0] ctrl     = prom[cnt_u];

always_ff @(posedge clk) begin
    enable_d <= enable;
    csq0_d   <= csq0;
    csq1_d   <= csq1;

    if (reset) begin
        prom_cnt <= 0; address <= 0; base <= 0;
        tick_pend <= 0; ctl <= 0; pdc <= 0;
        enable_d <= 0; csq0_d <= 0; csq1_d <= 0;
    end else begin
        if (ce_romclk) tick_pend <= 1;

        // chip bit request: address advances, data follows the ROM latency
        if (m0) address <= address + 12'd1;

        if (enable != enable_d)
            prom_cnt <= enable ? (cnt_u & 5'h10) : cnt_u;
        else if ((tick_pend | ce_romclk) && !chip_busy) begin
            tick_pend <= 0;
            prom_cnt  <= ((cnt_u + 5'd1) & 5'h0F) | (cnt_u & 5'h10);
            if (ctrl[6]) address <= 0;
            ctl <= {ctrl[2], 1'b0, ctrl[2], 1'b0};
            pdc <= ctrl[1];
        end

        // MAME rom_csq_w: a line going low selects its ROM; ROM 1 only while Q4 is high
        if (csq0_d && !csq0) base <= 1'b0;
        if (csq1_d && !csq1 && csq0) base <= 1'b1;
    end
end

endmodule
