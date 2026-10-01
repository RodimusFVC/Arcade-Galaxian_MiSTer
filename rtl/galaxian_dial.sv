//============================================================================
//
//  Dial steps for Moon War (MAME IPT_DIAL, KEYDELTA 4): one pulse per
//  quadrature bar, the direction held with it. Player 1 takes the spinner,
//  the mouse X axis and D-pad left / right; player 2 its D-pad. Relative
//  moves queue up and leave at most one step per 750 Hz tick, so the game's
//  4-bit counter (read once a frame) can't wrap between reads.
//
//============================================================================

module galaxian_dial
(
    input               clk,            // 49.152 MHz
    input               reset,

    input         [8:0] spinner,        // hps_io: [8] toggles per event, [7:0] signed delta
    input        [24:0] mouse,          // hps_io: [24] toggles per event, {[4], [15:8]} signed X
    input         [1:0] pad1,           // {left, right}
    input         [1:0] pad2,

    output reg    [1:0] step = 2'b00,   // one clock per bar, players 2 / 1
    output reg    [1:0] dir  = 2'b00    // 1 = right (count up)
);

reg [15:0] div = 16'd0;
reg  [1:0] pad_div = 2'd0;
always @(posedge clk) div <= div + 16'd1;
wire tick = div == 16'd0;

reg        spin_seen = 1'b0, mouse_seen = 1'b0;
wire       spin_ev  = spinner[8] != spin_seen;
wire       mouse_ev = mouse[24] != mouse_seen;
wire signed [10:0] spin_d  = spin_ev  ? {{3{spinner[7]}}, spinner[7:0]} : 11'sd0;
wire signed [10:0] mouse_d = mouse_ev ? {{2{mouse[4]}}, mouse[4], mouse[15:8]} : 11'sd0;

// D-pad: a step every third tick = 250 bars / s (MAME: 4 per frame)
wire        pad_tick = tick && pad_div == 2'd0;
wire signed [10:0] pad_d = pad_tick && (pad1[1] ^ pad1[0]) ? (pad1[0] ? 11'sd1 : -11'sd1) : 11'sd0;

reg  signed [10:0] pend = 11'sd0;
wire signed [10:0] pend_in = pend + spin_d + mouse_d + pad_d;

always @(posedge clk) begin
    step <= 2'b00;
    spin_seen  <= spinner[8];
    mouse_seen <= mouse[24];
    if (tick) pad_div <= pad_div == 2'd2 ? 2'd0 : pad_div + 2'd1;
    if (reset) pend <= 11'sd0;
    else if (tick && pend_in != 11'sd0) begin
        step[0] <= 1'b1;
        dir[0]  <= ~pend_in[10];
        pend    <= pend_in[10] ? pend_in + 11'sd1 : pend_in - 11'sd1;
    end
    else pend <= pend_in > 11'sd255 ? 11'sd255 : pend_in < -11'sd255 ? -11'sd255 : pend_in;
    if (pad_tick && (pad2[1] ^ pad2[0])) begin
        step[1] <= 1'b1;
        dir[1]  <= pad2[0];
    end
end

endmodule
