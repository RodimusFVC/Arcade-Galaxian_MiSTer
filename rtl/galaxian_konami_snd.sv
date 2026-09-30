//============================================================================
//
//  Konami sound board (Frogger / Scramble): Z80 at 1.789772 MHz, command
//  latch, one or two AY-3-8910s with switchable RC low-pass filters
//
//  Maps, timer and filter control per MAME galaxian.cpp (frogger_sound_map,
//  konami_sound_map, konami_sound_timer_r, konami_sound_filter_w) and the
//  nl_konami netlist (1K / 0.22uF / 0.047uF). Filters, DC removal and the
//  AY timer pattern follow the Time Pilot core (Ace, Soltan_G42).
//
//============================================================================

module galaxian_konami_snd
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               two_ay,         // 0 Frogger (1 AY, timer bits 3/5 swapped), 1 Scramble (2 AYs)
    input               fr_timer,       // Frogger timer on a 2-AY board (Quaak)
    input               timer_9000,     // the timer also reads at 9000 (Turpin S)
    input               no_filter,      // no RC filters fitted (Hustler)
    input               hb_map,         // Hustler bootleg: ROM 0000-2FFF, RAM 8000-8FFF, AY A6 address / A7 data
    input               rom12k,         // ROM 0000-2FFF (scramble.cpp scramble_sound_map), else 0000-1FFF
    input               hs_map,         // Hot Shocker: latch AY at A6 data / A7 address; the IRQ is set by irq_set and
                                        // cleared by reading the latch (AY port A), not by the acknowledge
    input               irq_set,
    input               pause,

    input               latch_we,       // PPI 1 port A: command
    input         [7:0] latch_d,
    input         [7:0] control,        // PPI 1 port B: [3] falling edge = IRQ, [4] mute

    input        [13:0] rom_addr,       // ROM load (16K)
    input         [7:0] rom_data,
    input               rom_we,
    input               rom_swap01,     // Frogger: the first 2K has D0 / D1 swapped (undone on reads: the config
                                        // arrives after the ROM download)

    output signed [15:0] out
);

// 1.789772 MHz = 49.152 MHz x 5.6 / 153.8 ~ 30 / 824 (as the Time Pilot core)
reg [9:0] frac = 10'd0;
reg       cen = 1'b0;
always @(posedge clk) begin
    if (frac >= 10'd794) begin frac <= frac - 10'd794; cen <= ~pause; end
    else                 begin frac <= frac + 10'd30;  cen <= 1'b0;   end
end

//----------------------------------------------------------- CPU --------------------------------------------------------------//

wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
wire [15:0] addr;
wire  [7:0] dout;
reg   [7:0] din;
reg         int_n = 1'b1;

T80sed cpu
(
    .RESET_n(~reset),
    .CLK_n(clk),
    .CLKEN(cen),
    .WAIT_n(1'b1),
    .INT_n(int_n),
    .NMI_n(1'b1),
    .BUSRQ_n(1'b1),
    .M1_n(m1_n),
    .MREQ_n(mreq_n),
    .IORQ_n(iorq_n),
    .RD_n(rd_n),
    .WR_n(wr_n),
    .RFSH_n(rfsh_n),
    .HALT_n(),
    .BUSAK_n(),
    .A(addr),
    .DI(din),
    .DO(dout)
);

// command latch; control bit 3 falling edge sets the IRQ, held until acknowledged
reg [7:0] latch = 8'd0;
reg       ctl3_d = 1'b0;
wire      latch_rd;
always @(posedge clk) begin
    if (latch_we) latch <= latch_d;
    ctl3_d <= control[3];
    if (reset | (hs_map ? latch_rd : ~iorq_n & ~m1_n)) int_n <= 1'b1;
    else if (hs_map ? irq_set : ctl3_d & ~control[3]) int_n <= 1'b0;
end

wire mem = ~mreq_n & rfsh_n;
wire io  = ~iorq_n & m1_n;


// Frogger: ROM 0000-1FFF, RAM 4000-43FF (mirror to 5FFF), filters 6000-7FFF (A15 ignored)
// Scramble: ROM 0000-1FFF, RAM 8000-83FF (mirror to EFFF), filters 9000-9FFF (+ B/D/F000)
wire rom_cs = mem && (hb_map ? addr[15:14] == 2'b00 : two_ay ? addr[15:13] == 3'b000 || (rom12k && addr[15:12] == 4'h2) :
                      addr[14:13] == 2'b00);
wire ram_cs = mem && (hb_map ? addr[15:12] == 4'h8 : two_ay ? addr[15] && !addr[12] : addr[14:13] == 2'b10);
wire flt_cs = mem && ~wr_n && !hb_map && (two_ay ? addr[15] && addr[12] : addr[14:13] == 2'b11);

wire [7:0] rom_q, ram_q;
wire [7:0] rom_d = rom_swap01 && addr[13:11] == 3'b000 ? {rom_q[7:2], rom_q[0], rom_q[1]} : rom_q;

dpram_dc #(.widthad_a(14)) rom
(
    .clock_a(clk), .address_a(rom_addr), .data_a(rom_data), .wren_a(rom_we),
    .clock_b(clk), .address_b(addr[13:0]), .q_b(rom_q)
);

// 1K mirrored, 4K on the Hustler bootleg
dpram_dc #(.widthad_a(12)) ram
(
    .clock_a(clk), .address_a({hb_map ? addr[11:10] : 2'b00, addr[9:0]}), .data_a(dout), .wren_a(ram_cs & ~wr_n),
    .q_a(ram_q)
);

//------------------------------------------------------------ AY --------------------------------------------------------------//

// AY #1 (3D): A6 data, A7 address (Frogger: A6 data, else A7 address); AY #2 (3C, Scramble): A4 address, else A5 data
wire io_w = io & ~wr_n;
wire io_r = io & ~rd_n;
wire ay_k    = (two_ay | hb_map) & ~hs_map;       // A6 address / A7 data decode
wire a1_addr_w = io_w & (ay_k ? addr[6] : ~addr[6] & addr[7]);
wire a1_data_w = io_w & (ay_k ? ~addr[6] & addr[7] : addr[6]);
wire a1_rd     = io_r & (ay_k ? addr[7] : addr[6]);

// latch read = AY #1 data read with register 14 (port A) selected
reg  [7:0] a1_reg = 8'd0;
always @(posedge clk) if (a1_addr_w) a1_reg <= dout;
assign latch_rd = a1_rd & (a1_reg == 8'h0E);
wire a2_addr_w = two_ay & io_w & addr[4];
wire a2_data_w = two_ay & io_w & ~addr[4] & addr[5];
wire a2_rd     = two_ay & io_r & addr[5];

// timer (MAME konami_sound_timer_r): the chain runs at 8x the CPU clock, period 40960
reg [15:0] tcnt = 16'd0;
always @(posedge clk) if (cen) tcnt <= tcnt >= 16'd40952 ? 16'd0 : tcnt + 16'd8;
wire        t_hi  = tcnt >= 16'd20480;
wire [15:0] t_low = t_hi ? tcnt - 16'd20480 : tcnt;
wire  [7:0] timer = {t_hi, t_low[14], t_low[13], t_low[11], 4'b1110};
wire  [7:0] timer_fr = {timer[7:6], timer[3], timer[4], timer[5], timer[2:0]};

wire [7:0] a1_dout, a2_dout;
wire [7:0] a1A, a1B, a1C, a2A, a2B, a2C;

jt49_bus #(.COMP(3'b100)) ay1
(
    .rst_n(~reset), .clk(clk), .clk_en(cen),
    .bdir(a1_addr_w | a1_data_w), .bc1(a1_addr_w | a1_rd), .din(dout),
    .sel(1'b1), .dout(a1_dout), .sound(), .A(a1A), .B(a1B), .C(a1C), .sample(),
    .IOA_in(latch), .IOA_out(), .IOB_in(two_ay && !fr_timer ? timer : timer_fr), .IOB_out()
);

jt49_bus #(.COMP(3'b100)) ay2
(
    .rst_n(~reset), .clk(clk), .clk_en(cen),
    .bdir(a2_addr_w | a2_data_w), .bc1(a2_addr_w | a2_rd), .din(dout),
    .sel(1'b1), .dout(a2_dout), .sound(), .A(a2A), .B(a2B), .C(a2C), .sample(),
    .IOA_in(8'hFF), .IOA_out(), .IOB_in(8'hFF), .IOB_out()
);

always @(*) begin
    din = 8'hFF;
    if      (rom_cs) din = rom_d;
    else if (ram_cs) din = ram_q;
    else if (io_r)   din = (a1_rd ? a1_dout : 8'hFF) & (a2_rd ? a2_dout : 8'hFF);
    else if (timer_9000 && mem && addr == 16'h9000) din = timer;
end

//---------------------------------------------------------- Filters -----------------------------------------------------------//

// A6-A11 of a filter write: AY #1 channels A, B, C (low bit 0.22uF, high bit 0.047uF); A0-A5 the same for AY #2
reg [11:0] flt = 12'd0;
always @(posedge clk) if (cen && flt_cs) flt <= addr[11:0];

reg [9:0] dc_div = 10'd0;
always @(posedge clk) dc_div <= dc_div + 10'd1;
wire cen_dc = dc_div == 10'd0;

// one channel: DC removal, the three filter settings, selection by the two control bits
function signed [15:0] pick(input [1:0] sel, input signed [15:0] d, input signed [15:0] l, input signed [15:0] m,
                            input signed [15:0] h);
    case (sel)
        2'b00: pick = d;
        2'b10: pick = l;       // high bit: 0.047uF
        2'b01: pick = m;       // low bit: 0.22uF
        default: pick = h;
    endcase
endfunction

wire [7:0] ch_raw [6];
assign ch_raw[0] = a1A; assign ch_raw[1] = a1B; assign ch_raw[2] = a1C;
assign ch_raw[3] = a2A; assign ch_raw[4] = a2B; assign ch_raw[5] = a2C;

wire signed [15:0] ch_out [6];
genvar i;
generate
    for (i = 0; i < 6; i = i + 1) begin : chan
        wire signed [15:0] dcr, lt, md, hv;
        jt49_dcrm2 #(16) dcrm(.clk(clk), .cen(cen_dc), .rst(reset), .din({3'd0, ch_raw[i], 5'd0}), .dout(dcr));
        tp_lpf_light  f_l(.clk(clk), .reset(reset), .in(dcr), .out(lt));
        tp_lpf_medium f_m(.clk(clk), .reset(reset), .in(dcr), .out(md));
        tp_lpf_heavy  f_h(.clk(clk), .reset(reset), .in(dcr), .out(hv));
        // AY #1 uses A6-A11, AY #2 A0-A5; per channel {high, low} = {A(n+1), A(n)}
        wire [1:0] sel = i < 3 ? {flt[7 + 2 * i], flt[6 + 2 * i]} : {flt[1 + 2 * (i - 3)], flt[2 * (i - 3)]};
        assign ch_out[i] = no_filter ? dcr : pick(sel, dcr, lt, md, hv);
    end
endgenerate

// mute (control bit 4) and the inverting output amplifier
wire signed [18:0] sum = 19'(ch_out[0]) + 19'(ch_out[1]) + 19'(ch_out[2]) +
                         (two_ay ? 19'(ch_out[3]) + 19'(ch_out[4]) + 19'(ch_out[5]) : 19'sd0);
wire signed [18:0] amp = control[4] ? 19'sd0 : -sum;
assign out = amp > 19'sd32767 ? 16'sd32767 : amp < -19'sd32767 ? -16'sd32767 : amp[15:0];

endmodule
