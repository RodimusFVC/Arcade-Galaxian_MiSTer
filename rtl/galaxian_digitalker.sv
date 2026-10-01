//============================================================================
//
//  National Semiconductor MM54104 Digitalker (Scorpion), per MAME
//  digitalk.cpp (Olivier Galibert, from Kevin Horton's analysis).
//
//  A 1 MHz stream (4 MHz / 4). Each step decodes one 128-sample waveform
//  from the speech ROM into a buffer - 2-bit ADPCM, mirrored for the voiced
//  modes 0 / 2, straight for the unvoiced mode 3 - which then plays with each
//  sample held for the pitch period (pitch_vals, 1 us units). Silent segments
//  and the 81.92 ms end silence are counted out. The control flow follows
//  MAME step for step; mode 3 addresses the ROM with the full 14 bits (MAME
//  truncates its local address to 8 bits).
//
//============================================================================

module galaxian_digitalker
(
    input                clk,           // 49.152 MHz
    input                reset,
    input                pause,

    input          [7:0] data,          // D7-D0
    input                cs,            // 1 = deselected
    input                cms,
    input                wr,
    output reg           intr = 1'b1,   // 1 = idle

    input         [13:0] rom_addr,
    input          [7:0] rom_data,
    input                rom_we,

    output reg signed [15:0] out = 16'sd0
);

//------------------------------------------------------ Tables -------------------------------------------------------//

function [14:0] level(input [2:0] v, input [2:0] i);          // MAME pcm_levels[v][i]
    case ({v, i})
            6'o00: level = 15'd473; 6'o01: level = 15'd945; 6'o02: level = 15'd1418; 6'o03: level = 15'd1890;
            6'o04: level = 15'd2363; 6'o05: level = 15'd2835; 6'o06: level = 15'd3308; 6'o07: level = 15'd3781;
            6'o10: level = 15'd655; 6'o11: level = 15'd1310; 6'o12: level = 15'd1966; 6'o13: level = 15'd2621;
            6'o14: level = 15'd3276; 6'o15: level = 15'd3931; 6'o16: level = 15'd4586; 6'o17: level = 15'd5242;
            6'o20: level = 15'd925; 6'o21: level = 15'd1851; 6'o22: level = 15'd2776; 6'o23: level = 15'd3702;
            6'o24: level = 15'd4627; 6'o25: level = 15'd5553; 6'o26: level = 15'd6478; 6'o27: level = 15'd7404;
            6'o30: level = 15'd1249; 6'o31: level = 15'd2498; 6'o32: level = 15'd3747; 6'o33: level = 15'd4996;
            6'o34: level = 15'd6245; 6'o35: level = 15'd7494; 6'o36: level = 15'd8743; 6'o37: level = 15'd9992;
            6'o40: level = 15'd1638; 6'o41: level = 15'd3276; 6'o42: level = 15'd4914; 6'o43: level = 15'd6552;
            6'o44: level = 15'd8190; 6'o45: level = 15'd9828; 6'o46: level = 15'd11466; 6'o47: level = 15'd13104;
            6'o50: level = 15'd2252; 6'o51: level = 15'd4504; 6'o52: level = 15'd6757; 6'o53: level = 15'd9009;
            6'o54: level = 15'd11261; 6'o55: level = 15'd13514; 6'o56: level = 15'd15766; 6'o57: level = 15'd18018;
            6'o60: level = 15'd2989; 6'o61: level = 15'd5979; 6'o62: level = 15'd8968; 6'o63: level = 15'd11957;
            6'o64: level = 15'd14947; 6'o65: level = 15'd17936; 6'o66: level = 15'd20925; 6'o67: level = 15'd23915;
            6'o70: level = 15'd4095; 6'o71: level = 15'd8190; 6'o72: level = 15'd12285; 6'o73: level = 15'd16380;
            6'o74: level = 15'd20475; 6'o75: level = 15'd24570; 6'o76: level = 15'd28665; 6'o77: level = 15'd32760;
        default: level = 15'd0;
    endcase
endfunction

function signed [15:0] dac_v(input [2:0] v, input [3:0] d);
    dac_v = d >= 4'd9 ? -$signed({1'b0, level(v, 3'(4'd15 - d))}) : d != 4'd0 ? $signed({1'b0, level(v, 3'(d - 4'd1))}) : 16'sd0;
endfunction

function signed [3:0] delta1(input [3:0] i);
    case (i)
        4'd0, 4'd1:   delta1 = -4'sd4;
        4'd2, 4'd3:   delta1 = -4'sd1;
        4'd4, 4'd5:   delta1 = -4'sd2;
        4'd10, 4'd11: delta1 = 4'sd2;
        4'd12, 4'd13: delta1 = 4'sd1;
        4'd14, 4'd15: delta1 = 4'sd4;
        default:      delta1 = 4'sd0;
    endcase
endfunction

function signed [3:0] delta2(input [3:0] i);                    // { 0,-1,-2,-3, 1,0,-1,-2, 2,1,0,-1, 3,2,1,0 }
    delta2 = $signed({2'b00, i[3:2]}) - $signed({2'b00, i[1:0]});
endfunction

function [6:0] pitch_val(input [4:0] i);
    case (i)
        5'd0:  pitch_val = 7'd97; 5'd1:  pitch_val = 7'd95; 5'd2:  pitch_val = 7'd92; 5'd3:  pitch_val = 7'd89;
        5'd4:  pitch_val = 7'd87; 5'd5:  pitch_val = 7'd84; 5'd6:  pitch_val = 7'd82; 5'd7:  pitch_val = 7'd80;
        5'd8:  pitch_val = 7'd77; 5'd9:  pitch_val = 7'd75; 5'd10: pitch_val = 7'd73; 5'd11: pitch_val = 7'd71;
        5'd12: pitch_val = 7'd69; 5'd13: pitch_val = 7'd67; 5'd14: pitch_val = 7'd65; 5'd15: pitch_val = 7'd63;
        5'd16: pitch_val = 7'd61; 5'd17: pitch_val = 7'd60; 5'd18: pitch_val = 7'd58; 5'd19: pitch_val = 7'd56;
        5'd20: pitch_val = 7'd55; 5'd21: pitch_val = 7'd53; 5'd22: pitch_val = 7'd52; 5'd23: pitch_val = 7'd50;
        5'd24: pitch_val = 7'd49; 5'd25: pitch_val = 7'd48; 5'd26: pitch_val = 7'd46; 5'd27: pitch_val = 7'd45;
        5'd28: pitch_val = 7'd43; 5'd29: pitch_val = 7'd42; 5'd30: pitch_val = 7'd41; default: pitch_val = 7'd40;
    endcase
endfunction

//---------------------------------------------------- Memories -------------------------------------------------------//

reg  [13:0] ra = 14'd0;
wire  [7:0] rq;
dpram_dc #(.widthad_a(14)) rom
(
    .clock_a(clk), .address_a(rom_addr), .data_a(rom_data), .wren_a(rom_we),
    .clock_b(clk), .address_b(ra), .q_b(rq)
);

// waveform buffer: {volume, DAC code} per sample
reg   [6:0] wpos = 7'd0, wcnt = 7'd0;           // write address, next sample index
reg         bw = 1'b0;
reg   [6:0] bd = 7'd0;
reg   [7:0] dac_index = 8'd128;
wire  [7:0] bq;
dpram_dc #(.widthad_a(7)) buffer
(
    .clock_a(clk), .address_a(wpos), .data_a({1'b0, bd}), .wren_a(bw),
    .clock_b(clk), .address_b(dac_index[6:0]), .q_b(bq)
);

//----------------------------------------------------- Control -------------------------------------------------------//

// 1 MHz stream tick = 49.152 MHz x 125 / 6144
reg [12:0] frac = 13'd0;
reg        tick = 1'b0;
always @(posedge clk) begin
    if (frac >= 13'd6019) begin frac <= frac - 13'd6019; tick <= ~pause; end
    else                  begin frac <= frac + 13'd125;  tick <= 1'b0;   end
end


//------------------------------------------------------ Engine -------------------------------------------------------//

localparam [4:0] S_IDLE = 5'd0, S_START = 5'd1, S_START2 = 5'd2, S_START3 = 5'd3, S_CHK = 5'd4, S_RD1 = 5'd5,
                 S_RD2 = 5'd6, S_RD3 = 5'd7, S_RD4 = 5'd8, S_HDR = 5'd9, S_HDR2 = 5'd10, S_SEC = 5'd11,
                 S_FETCH = 5'd12, S_FETCH2 = 5'd13, S_L = 5'd14, S_END = 5'd15,
                 S_SEGH = 5'd16, S_BYTE = 5'd17;
reg  [4:0] st = S_IDLE;

reg [15:0] bpos = 16'hFFFF;
reg [13:0] apos = 14'd0;
reg  [1:0] mode = 2'd0, stop_after = 2'd0;
reg  [4:0] cur_segment = 5'd0, segments = 5'd0, prev_pitch = 5'd0, pitch_id = 5'd0;
reg  [3:0] cur_repeat = 4'd0, repeats = 4'd0;
reg  [6:0] pitch = 7'd0, pitch_pos = 7'd0;
reg [15:0] cur_bits = 16'd0, bits = 16'd0;
reg [19:0] zero_count = 20'd0;
reg  [7:0] v1 = 8'd0, v2 = 8'd0;
reg  [7:0] dac = 8'd0;
reg  [2:0] vol = 3'd0;

// sections: 0 zeros x32, 1 forward, 2 hold, 3 reverse, 4 zeros x31, 5 hold, 6 forward (k = 1 from l = 1), 7 hold,
// 8 reverse, 9 unvoiced forward; section list per mode
reg  [3:0] sec = 4'd0;
reg  [5:0] k = 6'd0, zc = 6'd0;
reg  [1:0] l = 2'd0;
function [3:0] next_sec(input [1:0] m, input [3:0] s);
    case ({m, s})
        {2'd0, 4'd0}: next_sec = 4'd1; {2'd0, 4'd1}: next_sec = 4'd2; {2'd0, 4'd2}: next_sec = 4'd3;
        {2'd0, 4'd3}: next_sec = 4'd4;
        {2'd2, 4'd1}: next_sec = 4'd2; {2'd2, 4'd2}: next_sec = 4'd3;
        {2'd2, 4'd3}: next_sec = 4'd5; {2'd2, 4'd5}: next_sec = 4'd6; {2'd2, 4'd6}: next_sec = 4'd7;
        {2'd2, 4'd7}: next_sec = 4'd8;
        default:      next_sec = 4'd15;                            // done
    endcase
endfunction

reg        pin_intr = 1'b0;
reg        cs_l = 1'b1, cms_l = 1'b1, wr_l = 1'b1, start_req = 1'b0;
reg  [7:0] cmd = 8'hFF;

// MAME digitalker_control_w: cs, then cms, then wr
always @(posedge clk) begin : pins
    reg c1, start, set_intr;
    start = 1'b0; set_intr = 1'b0;
    if (reset) begin
        cs_l <= 1'b1; cms_l <= 1'b1; wr_l <= 1'b1;
    end
    else begin
        if (cs != cs_l && !cs && !wr_l) begin if (cms_l) set_intr = 1'b1; else start = 1'b1; end
        c1 = cs;
        if (wr != wr_l && !wr && !c1) begin if (cms) set_intr = 1'b1; else start = 1'b1; end
        cs_l <= cs; cms_l <= cms; wr_l <= wr;
    end
    if (start) begin start_req <= 1'b1; cmd <= data; end
    else if (st == S_START) start_req <= 1'b0;
    pin_intr <= set_intr;
end

wire [1:0] lmin = (mode == 2'd2 && k == 6'd0) ? 2'd1 : 2'd0;
wire [5:0] sh   = 6'd6 + {3'd0, l, 1'b0};
wire [3:0] idx  = 4'(bits >> sh);
wire       need_step = zero_count == 20'd0 && dac_index == 8'd128;
wire       step_go   = need_step && !(stop_after == 2'd0 && bpos == 16'hFFFF && (cur_segment == segments || cur_repeat == repeats));
// stream ticks that land while a waveform is being decoded wait here, so no stream time is lost
reg  [3:0] tpend = 4'd0;
wire       play = st == S_IDLE && !start_req && !step_go && (tpend != 4'd0 || tick);

always @(posedge clk) begin
    bw <= 1'b0;
    if (pin_intr) intr <= 1'b1;
    if (reset) begin
        st <= S_IDLE; bpos <= 16'hFFFF; intr <= 1'b1; dac_index <= 8'd128; zero_count <= 20'd0;
        cur_segment <= 5'd0; segments <= 5'd0; cur_repeat <= 4'd0; repeats <= 4'd0; stop_after <= 2'd0;
        pitch_pos <= 7'd0; out <= 16'sd0;
    end
    else begin
        // playback, one sample per stream tick while the engine is idle
        tpend <= tpend + (tick ? 4'd1 : 4'd0) - (play ? 4'd1 : 4'd0);
        if (play) begin
            if (zero_count != 20'd0) begin out <= 16'sd0; zero_count <= zero_count - 20'd1; end
            else if (dac_index != 8'd128) begin
                out <= dac_v(bq[6:4], bq[3:0]);
                if (pitch_pos + 7'd1 == pitch) begin pitch_pos <= 7'd0; dac_index <= dac_index + 8'd1; end
                else pitch_pos <= pitch_pos + 7'd1;
            end
            else out <= 16'sd0;
        end

        case (st)
            S_IDLE:
                if (start_req) st <= S_START;
                else if (step_go) st <= S_CHK;
            // digitalker_start_command: the segment list address from the command's vector
            S_START:  begin ra <= {5'd0, cmd, 1'b0}; st <= S_START2; end
            S_START2: begin ra <= {5'd0, cmd, 1'b1}; st <= S_START3; end
            S_START3: begin v1 <= rq; st <= S_RD4; end
            S_RD4: begin
                bpos <= {2'b00, v1[5:0], rq};
                cur_segment <= 5'd0; segments <= 5'd0; cur_repeat <= 4'd0; repeats <= 4'd0;
                dac_index <= 8'd128; zero_count <= 20'd0; intr <= 1'b0;
                st <= S_IDLE;
            end
            // digitalker_step
            S_CHK:
                if (cur_segment == segments || cur_repeat == repeats) begin
                    if (stop_after == 2'd0) begin ra <= bpos[13:0]; st <= S_RD1; end
                    else if (stop_after == 2'd1) begin
                        intr <= 1'b1; bpos <= 16'hFFFF; zero_count <= 20'd81920; stop_after <= 2'd2;
                        cur_segment <= 5'd0; cur_repeat <= 4'd0; segments <= 5'd0; repeats <= 4'd0;
                        ra <= apos; st <= S_HDR;
                    end
                    else begin stop_after <= 2'd0; ra <= apos; st <= S_HDR; end
                end
                else begin ra <= apos; st <= S_HDR; end
            S_RD1: begin ra <= bpos[13:0] + 14'd1; st <= S_RD2; end
            S_RD2: begin v1 <= rq; ra <= bpos[13:0] + 14'd2; st <= S_RD3; end
            S_RD3: begin v2 <= rq; st <= S_SEGH; end
            S_SEGH: begin : seg_hdr
                reg [13:0] a;
                a = {rq[5:0], v2};
                bpos <= bpos + 16'd3;
                apos <= a;
                segments <= {1'b0, v1[3:0]} + 5'd1;
                repeats <= {1'b0, v1[6:4]} + 4'd1;
                mode <= rq[7:6];
                stop_after <= {1'b0, v1[7]};
                cur_segment <= 5'd0; cur_repeat <= 4'd0;
                if (a == 14'd0) begin
                    // 40 x 128 x segments x repeats
                    zero_count <= 20'd5120 * ({1'b0, v1[3:0]} + 5'd1) * ({1'b0, v1[6:4]} + 4'd1);
                    segments <= 5'd0; repeats <= 4'd0;
                    st <= S_IDLE;
                end
                else begin ra <= a; st <= S_HDR; end
            end
            // waveform header byte (one clock for the read)
            S_HDR: st <= S_HDR2;
            S_HDR2: begin
                v1   <= rq;
                vol  <= rq[7:5];
                wcnt <= 7'd0;
                dac  <= 8'd0;
                k    <= 6'd0;
                l    <= 2'd0;
                if (mode == 2'd3) begin
                    pitch <= pitch_val(rq[4:0]);
                    bits  <= (cur_segment == 5'd0 && cur_repeat == 4'd0) ? 16'h0040 : cur_bits;
                    sec   <= 4'd9; k <= 6'd0; st <= S_FETCH;
                end
                else if (mode == 2'd1) begin
                    zero_count <= 20'd1; cur_segment <= segments; st <= S_IDLE;
                end
                else begin : voiced
                    reg [4:0] pid;
                    reg signed [6:0] nv;
                    reg [3:0] dlt;
                    dlt = rq[3:0] > {1'b0, cur_repeat[2:0]} + 4'd1 ? {1'b0, cur_repeat[2:0]} + 4'd1 : rq[3:0];
                    nv  = rq[4] ? $signed({2'b00, prev_pitch}) - $signed({3'b000, dlt}) : $signed({2'b00, prev_pitch}) + $signed({3'b000, dlt});
                    pid = cur_segment == 5'd0 ? rq[4:0] : nv < 0 ? 5'd0 : nv > 7'sd31 ? 5'd31 : nv[4:0];
                    pitch_id <= pid;
                    pitch <= pitch_val(pid);
                    bits  <= 16'h0080;
                    if (mode == 2'd0) begin sec <= 4'd0; zc <= 6'd32; st <= S_SEC; end
                    else begin sec <= 4'd1; k <= 6'd1; st <= S_FETCH; end
                end
            end
            // zeros / holds
            S_SEC:
                case (sec)
                    4'd0, 4'd4: begin
                        bw <= 1'b1; bd <= {vol, 4'd0}; wpos <= wcnt; wcnt <= wcnt + 7'd1;
                        if (zc == 6'd1) begin
                            sec <= next_sec(mode, sec); k <= 6'd1; st <= next_sec(mode, sec) == 4'd15 ? S_END : S_FETCH;
                        end
                        zc <= zc - 6'd1;
                    end
                    4'd2, 4'd5, 4'd7: begin
                        bw <= 1'b1; bd <= {vol, dac[3:0]}; wpos <= wcnt; wcnt <= wcnt + 7'd1;
                        sec <= next_sec(mode, sec);
                        k <= next_sec(mode, sec) == 4'd6 ? 6'd1 : 6'd7;
                        l <= 2'd0;
                        st <= S_FETCH;
                    end
                    default: st <= S_END;
                endcase
            // one source byte
            S_FETCH: begin
                ra <= sec == 4'd9 ? apos + 14'd1 + {cur_segment, 5'd0} + {8'd0, k} : apos + {8'd0, k};
                st <= S_FETCH2;
            end
            S_FETCH2: st <= S_BYTE;
            S_BYTE: begin
                if (sec == 4'd3 || sec == 4'd8) begin
                    bits <= {bits[7:0], k != 6'd0 ? rq : 8'h80};
                    l <= 2'd3;
                end
                else begin
                    bits <= bits | {rq, 8'd0};
                    l <= (sec == 4'd6 && k == 6'd1) ? 2'd1 : 2'd0;
                end
                st <= S_L;
            end
            // one sample per clock
            S_L: begin : sample
                reg [7:0] d;
                reg fwd;
                fwd = !(sec == 4'd3 || sec == 4'd8);
                d = fwd ? dac + 8'($signed(sec == 4'd9 ? delta2(idx) : delta1(idx)))
                        : dac - 8'($signed(delta1(idx)));
                dac <= d;
                bw <= 1'b1; bd <= {vol, d[3:0]}; wpos <= wcnt; wcnt <= wcnt + 7'd1;
                if (fwd ? l == 2'd3 : l == lmin) begin
                    if (fwd) bits <= bits >> 8;
                    if (fwd ? k == (sec == 4'd9 ? 6'd31 : 6'd8) : k == 6'd0) begin
                        sec <= sec == 4'd9 ? 4'd15 : next_sec(mode, sec);
                        zc  <= 6'd31;
                        st  <= sec == 4'd9 || next_sec(mode, sec) == 4'd15 ? S_END : S_SEC;
                    end
                    else begin
                        k  <= fwd ? k + 6'd1 : k - 6'd1;
                        st <= S_FETCH;
                    end
                end
                else l <= fwd ? l + 2'd1 : l - 2'd1;
            end
            // end of step: bookkeeping, then play unless a silence is running
            S_END: begin
                if (mode == 2'd3) begin
                    cur_bits <= bits;
                    if (cur_segment + 5'd1 == segments) begin cur_segment <= 5'd0; cur_repeat <= cur_repeat + 4'd1; end
                    else cur_segment <= cur_segment + 5'd1;
                end
                else if (cur_repeat + 4'd1 == repeats) begin
                    apos <= apos + 14'd9; prev_pitch <= pitch_id; cur_repeat <= 4'd0; cur_segment <= cur_segment + 5'd1;
                end
                else cur_repeat <= cur_repeat + 4'd1;
                if (zero_count == 20'd0) dac_index <= 8'd0;
                st <= S_IDLE;
            end
            default: st <= S_IDLE;
        endcase
    end
end

endmodule
