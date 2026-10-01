//============================================================================
//
//  Crazy Climber sample generator (Moon Shuttle): 8K of 4-bit samples played
//  through a 4-bit DAC and a 5-bit volume latch. Per MAME cclimber_a.cpp: a
//  rising trigger starts at the AY port A address x 64, a 70 byte jumps to
//  the port B address x 64, and each step lasts (256 - rate) ticks of the AY
//  clock / 2 (256 kHz).
//
//============================================================================

module galaxian_cclimb_snd
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               pause,

    input               trigger,        // A004 != 0
    input         [7:0] rate,           // A800
    input         [4:0] volume,         // B000
    input         [7:0] start_addr,     // AY port A
    input         [7:0] loop_addr,      // AY port B

    input        [12:0] rom_addr,
    input         [7:0] rom_data,
    input               rom_we,

    output reg    [7:0] out = 8'd0      // 0-254, one AY channel's scale at full volume
);

// 256 kHz = 49.152 MHz / 192
reg [7:0] div = 8'd0;
always @(posedge clk) div <= div == 8'd191 ? 8'd0 : div + 8'd1;
wire tick256 = div == 8'd0 && !pause;

reg  [13:0] addr = 14'd0;               // nibble address
reg   [7:0] cnt  = 8'd0;
reg         trig_d = 1'b0;
wire  [7:0] rom_q;

dpram_dc #(.widthad_a(13)) rom
(
    .clock_a(clk), .address_a(rom_addr), .data_a(rom_data), .wren_a(rom_we),
    .clock_b(clk), .address_b(addr[13:1]), .q_b(rom_q)
);

wire  [3:0] nib = addr[0] ? rom_q[3:0] : rom_q[7:4];
reg   [3:0] dac = 4'd0;
wire [18:0] lvl = {15'd0, dac} * {14'd0, volume} * 19'd561;   // x 17 x volume / 31
always @(posedge clk) out <= lvl[17:10];

always @(posedge clk) begin
    trig_d <= trigger;
    if (reset) begin
        addr <= 14'd0;
        cnt  <= 8'd0;
    end
    else if (trigger && !trig_d) addr <= {start_addr, 6'd0};
    else if (tick256) begin
        if ({1'b0, cnt} + 9'd1 >= 9'd256 - {1'b0, rate}) begin
            cnt <= 8'd0;
            dac <= nib;
            if (rom_q == 8'h70)  addr <= {loop_addr, 6'd0};
            else if (trigger)    addr <= addr + 14'd1;
        end
        else cnt <= cnt + 8'd1;
    end
end

endmodule
