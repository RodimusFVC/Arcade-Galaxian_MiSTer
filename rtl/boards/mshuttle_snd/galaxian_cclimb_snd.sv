//  Based on MAME cclimber_a.cpp (Nicola Salmoria, hap, BSD-3-Clause)

module galaxian_cclimb_snd
(
    input               clk,
    input               reset,
    input               pause,

    input               trigger,
    input         [7:0] rate,
    input         [4:0] volume,
    input         [7:0] start_addr,
    input         [7:0] loop_addr,

    output       [12:0] rom_a,
    input         [7:0] rom_q,

    output reg    [7:0] out = 8'd0
);

reg [7:0] div = 8'd0;
always @(posedge clk) div <= div == 8'd191 ? 8'd0 : div + 8'd1;
wire tick256 = div == 8'd0 && !pause;

reg  [13:0] addr = 14'd0;
reg   [7:0] cnt  = 8'd0;
reg         trig_d = 1'b0;
assign rom_a = addr[13:1];

wire  [3:0] nib = addr[0] ? rom_q[3:0] : rom_q[7:4];
reg   [3:0] dac = 4'd0;
wire [18:0] lvl = {15'd0, dac} * {14'd0, volume} * 19'd561;
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
