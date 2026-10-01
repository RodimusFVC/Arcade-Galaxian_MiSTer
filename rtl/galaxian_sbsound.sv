//============================================================================
//
//  Space Battle (Hoei) discrete sound: MAME galaxian_a.cpp sbhoei_discrete
//
//  The Galaxian pitch counter and fire circuit (as rtl/galaxian_sound.sv),
//  three noise channels - the star LFSR's N3A latched on 2V (noise 3), 64H
//  (noise 1, MAME's "128H" rate) and 4V (noise 2, "4V+8V") - each gated by
//  an RC discharge into an op-amp band-pass, and one resistor mixer with
//  0.1uF coupling on the noise and fire inputs (sbhoei_mixer_desc).
//  Constants: verilator/sbsnd/consts.py. Voltages Q20, coefficients Q24,
//  band-pass coefficients Q28; 1.536 MHz fast stage, 48 kHz sample stage.
//
//============================================================================

module galaxian_sbsound
(
    input                    clk,            // 49.152 MHz
    input                    reset,
    input                    pause,
    input                    v2,             // 2V (vcnt[1])
    input                    v4,             // 4V (vcnt[2])
    input                    h64,            // 64H (hcnt[6])
    input                    n3a,            // star LFSR N3A
    input              [2:0] noise_en,       // A000 noise 1, A001 noise 2, A803 noise 3
    input                    fire,           // A805
    input              [1:0] vol,            // A806-A807
    input              [7:0] pitch,          // B800
    output reg signed [15:0] out = 16'sd0
);

localparam signed [35:0] N3_KDIS   = 36'sd924;
localparam signed [35:0] N3_BPA    = 36'sd2145923;
localparam signed [35:0] N3_BPC    = -36'sd2743368;
localparam signed [35:0] N3_A1     = -36'sd534373228;
localparam signed [35:0] N3_A2     = 36'sd266066400;
localparam signed [35:0] N3_B0     = -36'sd14508672;
localparam signed [35:0] N1_KDIS   = 36'sd2865;
localparam signed [35:0] N1_BPA    = 36'sd3025400;
localparam signed [35:0] N1_BPC    = -36'sd2578466;
localparam signed [35:0] N1_A1     = -36'sd534365014;
localparam signed [35:0] N1_A2     = 36'sd266066412;
localparam signed [35:0] N1_B0     = -36'sd15436473;
localparam signed [35:0] N2_KDIS   = 36'sd2865;
localparam signed [35:0] N2_BPA    = 36'sd3025400;
localparam signed [35:0] N2_BPC    = -36'sd2578466;
localparam signed [35:0] N2_A1     = -36'sd534365014;
localparam signed [35:0] N2_A2     = 36'sd266066412;
localparam signed [35:0] N2_B0     = -36'sd15436473;
localparam signed [35:0] VREF      = 36'sd3145728;
localparam signed [35:0] VPMAX     = 36'sd3670016;
localparam signed [35:0] VU        = 36'sd3460301;
localparam signed [35:0] VTTL      = 36'sd4194304;
localparam signed [35:0] V5        = 36'sd5242880;
localparam signed [35:0] V025      = 36'sd262144;
localparam signed [35:0] FIRE_KRC  = 36'sd3380;
localparam signed [35:0] CV_N      = 36'sd756350;
localparam signed [35:0] CV_F      = 36'sd13751816;
localparam signed [35:0] FI_KC     = 36'sd34099;
localparam signed [35:0] FI_KD     = 36'sd49575;
localparam signed [35:0] FI_KDIS   = 36'sd109;
localparam signed [35:0] MP00      = 36'sd329560;
localparam signed [35:0] MP20      = 36'sd482283;
localparam signed [35:0] MP30      = 36'sd0;
localparam signed [35:0] MN0       = 36'sd4494000;
localparam signed [35:0] MF0       = 36'sd2103575;
localparam signed [35:0] MP01      = 36'sd324654;
localparam signed [35:0] MP21      = 36'sd1474041;
localparam signed [35:0] MP31      = 36'sd0;
localparam signed [35:0] MN1       = 36'sd4427106;
localparam signed [35:0] MF1       = 36'sd2072262;
localparam signed [35:0] MP02      = 36'sd326457;
localparam signed [35:0] MP22      = 36'sd477742;
localparam signed [35:0] MP32      = 36'sd631852;
localparam signed [35:0] MN2       = 36'sd4451688;
localparam signed [35:0] MF2       = 36'sd2083769;
localparam signed [35:0] MP03      = 36'sd321643;
localparam signed [35:0] MP23      = 36'sd1460367;
localparam signed [35:0] MP33      = 36'sd622534;
localparam signed [35:0] MN3       = 36'sd4386038;
localparam signed [35:0] MF3       = 36'sd2053039;
localparam signed [35:0] KHP_N     = 36'sd1830502;
localparam signed [35:0] KHP_F     = 36'sd1058341;
localparam signed [35:0] KAMP      = 36'sd34916;

function signed [35:0] clamp(input signed [35:0] v, input signed [35:0] lo, input signed [35:0] hi);
    clamp = v < lo ? lo : v > hi ? hi : v;
endfunction

function signed [35:0] ck(input [1:0] ch, input [2:0] i);   // channel 0 = noise 3, 1 = noise 1, 2 = noise 2
    case ({ch, i})
        5'h00: ck = N3_KDIS; 5'h01: ck = N3_BPA; 5'h02: ck = N3_BPC; 5'h03: ck = N3_A1; 5'h04: ck = N3_A2; 5'h05: ck = N3_B0;
        5'h08: ck = N1_KDIS; 5'h09: ck = N1_BPA; 5'h0A: ck = N1_BPC; 5'h0B: ck = N1_A1; 5'h0C: ck = N1_A2; 5'h0D: ck = N1_B0;
        5'h10: ck = N2_KDIS; 5'h11: ck = N2_BPA; 5'h12: ck = N2_BPC; 5'h13: ck = N2_A1; 5'h14: ck = N2_A2; 5'h15: ck = N2_B0;
        default: ck = 36'sd0;
    endcase
endfunction

function signed [35:0] mk(input [1:0] v, input [2:0] i);    // mixer: 0 QA, 1 QC, 2 QD, 3 noise, 4 fire
    case ({v, i})
        5'h00: mk = MP00; 5'h01: mk = MP20; 5'h02: mk = MP30; 5'h03: mk = MN0; 5'h04: mk = MF0;
        5'h08: mk = MP01; 5'h09: mk = MP21; 5'h0A: mk = MP31; 5'h0B: mk = MN1; 5'h0C: mk = MF1;
        5'h10: mk = MP02; 5'h11: mk = MP22; 5'h12: mk = MP32; 5'h13: mk = MN2; 5'h14: mk = MF2;
        5'h18: mk = MP03; 5'h19: mk = MP23; 5'h1A: mk = MP33; 5'h1B: mk = MN3; 5'h1C: mk = MF3;
        default: mk = 36'sd0;
    endcase
endfunction

//-------------------------------------------------------- Timing --------------------------------------------------------//

// c = clock within a 1.536 MHz tick, ft = tick within a 48 kHz period
reg  [4:0] c = 5'd0, ft = 5'd0;
always @(posedge clk) begin
    if (reset) begin
        c  <= 5'd0;
        ft <= 5'd0;
    end
    else if (!pause) begin
        c <= c + 5'd1;
        if (c == 5'd31) ft <= ft + 5'd1;
    end
end

//------------------------------------------------------ Fast stage ------------------------------------------------------//

reg  [2:0] en_i = 3'd0;
reg        fire_i = 1'b0;
reg  [1:0] vol_i = 2'd0;
reg  [7:0] pitch_i = 8'hFF;
reg        v2_d = 1'b0, v4_d = 1'b0, h64_d = 1'b0;
reg  [2:0] noise = 3'd0;                     // {noise 2, noise 1, noise 3} samples

reg  [7:0] c1 = 8'hFF;
reg  [3:0] c2 = 4'd0;
reg signed [35:0] fi_v = 36'sd0, fi_cap = 36'sd0;
reg        fi_ff = 1'b1, fi_ffp, fi_run;
reg  [5:0] acc_b0 = 6'd0, acc_b2 = 6'd0, acc_b3 = 6'd0;
reg [31:0] acc_fire = 32'd0;

// published by the sample stage
reg signed [35:0] rcf = 36'sd0;

// fast multiplier: operands registered at issue, product registered the next clock, used the clock after
reg signed [35:0] fa, fb;
reg signed [71:0] fp;
always @(posedge clk) fp <= fa * fb;
wire signed [35:0] fq = 36'(fp >>> 24);
wire signed [35:0] fq_up = 36'((fp + 72'sd16777215) >>> 24);

wire [3:0] c2_n = (pitch_i != 8'hFF && c1 == 8'hFF) ? c2 + 4'd1 : c2;
wire signed [35:0] cvf = (noise[0] ? CV_N : 36'sd0) + rcf;
wire signed [35:0] u_fire = fire_i ? VU : 36'sd0;

function [0:0] ff_pre(input signed [35:0] v, input ff, input signed [35:0] th);
    ff_pre = (v >= th) ? 1'b0 : (v <= (th >>> 1)) ? 1'b1 : ff;
endfunction

always @(posedge clk) begin
    if (h64 && !h64_d) noise[1] <= n3a;       // 64H runs faster than the 1.536 MHz tick: sampled every clock
    h64_d <= h64;
    if (reset) begin
        c1 <= 8'hFF; c2 <= 4'd0; noise[0] <= 1'b0; noise[2] <= 1'b0; v2_d <= 1'b0; v4_d <= 1'b0;
        fi_v <= 36'sd0; fi_ff <= 1'b1; fi_cap <= 36'sd0;
        acc_b0 <= 6'd0; acc_b2 <= 6'd0; acc_b3 <= 6'd0; acc_fire <= 32'd0;
    end
    else if (!pause) begin
        case (c)
            5'd0: begin
                en_i <= noise_en; fire_i <= fire; vol_i <= vol; pitch_i <= pitch;
                if (v2 && !v2_d) noise[0] <= n3a;
                if (v4 && !v4_d) noise[2] <= n3a;
                v2_d <= v2;
                v4_d <= v4;
            end
            5'd1: begin
                if (pitch_i != 8'hFF) begin
                    c1 <= (c1 == 8'hFF) ? pitch_i : c1 + 8'd1;
                    c2 <= c2_n;
                end
                acc_b0 <= acc_b0 + c2_n[0];
                acc_b2 <= acc_b2 + c2_n[2];
                acc_b3 <= acc_b3 + c2_n[3];
            end
            5'd5: begin
                fi_run <= cvf >= V025;
                fi_ffp <= ff_pre(fi_v, fi_ff, cvf);
                fa <= ff_pre(fi_v, fi_ff, cvf) ? V5 - fi_v : fi_v;
                fb <= ff_pre(fi_v, fi_ff, cvf) ? FI_KC : FI_KD;
            end
            5'd7: if (fi_run) begin : fi_done
                reg signed [35:0] vn;
                vn = fi_ffp ? fi_v + fq : fi_v - fq;
                if (fi_ffp && vn >= cvf)               begin fi_v <= cvf;       fi_ff <= 1'b0; end
                else if (!fi_ffp && vn <= (cvf >>> 1)) begin fi_v <= cvf >>> 1; fi_ff <= 1'b1; end
                else                                   begin fi_v <= vn;        fi_ff <= fi_ffp; end
            end
            // fire RCDISC5: the diode charges C25 at once, R41 discharges it; only passed while the 555 is high
            5'd8: begin
                fa <= fi_cap - u_fire;
                fb <= FI_KDIS;
            end
            5'd10: begin
                if (fi_ff) begin
                    if (u_fire > fi_cap) begin fi_cap <= u_fire; acc_fire <= acc_fire + 32'(u_fire); end
                    else begin fi_cap <= fi_cap - fq_up; acc_fire <= acc_fire + 32'(fi_cap - fq_up); end
                end
                else if (u_fire > fi_cap) fi_cap <= u_fire;
            end
            5'd12: if (ft == 5'd31) begin acc_b0 <= 6'd0; acc_b2 <= 6'd0; acc_b3 <= 6'd0; acc_fire <= 32'd0; end
            default: ;
        endcase
    end
end

//----------------------------------------------------- Sample stage -----------------------------------------------------//

// snapshot after fast tick 31; one step per clock, a product issued in step n is read in step n + 2
reg  [5:0] s_b0, s_b2, s_b3;
reg [31:0] s_fire;
reg  [2:0] s_noise, s_en;
reg        s_fire_l;
reg  [1:0] s_vol;
reg  [6:0] st = 7'd127;

reg signed [35:0] cap[3], x1[3], x2[3], y1[3], y2[3], vo[3], hpc[4];
reg signed [35:0] rc173 = 36'sd0, amp_cap = 36'sd0, rcf_new = 36'sd0, diff, x, hsum, hfire, o;
reg signed [71:0] bq;
reg signed [15:0] out_new = 16'sd0;

reg signed [35:0] sa, sb;
reg signed [71:0] sp;
always @(posedge clk) sp <= sa * sb;
wire signed [35:0] sq = 36'(sp >>> 24);

// channel steps: 0-10 noise 3, 11-21 noise 1, 22-32 noise 2
wire [1:0] ch = st < 7'd11 ? 2'd0 : st < 7'd22 ? 2'd1 : 2'd2;
wire [3:0] cs = st < 7'd11 ? st[3:0] : st < 7'd22 ? 4'(st - 7'd11) : 4'(st - 7'd22);

integer i;
initial for (i = 0; i < 3; i = i + 1) begin cap[i] = 0; x1[i] = 0; x2[i] = 0; y1[i] = 0; y2[i] = 0; vo[i] = 0; end
initial for (i = 0; i < 4; i = i + 1) hpc[i] = 0;

always @(posedge clk) begin
    if (reset) begin
        st <= 7'd127;
        for (i = 0; i < 3; i = i + 1) begin cap[i] <= 0; x1[i] <= 0; x2[i] <= 0; y1[i] <= 0; y2[i] <= 0; vo[i] <= 0; end
        for (i = 0; i < 4; i = i + 1) hpc[i] <= 0;
        rc173 <= 36'sd0; amp_cap <= 36'sd0; rcf_new <= 36'sd0; out_new <= 16'sd0;
        rcf <= 36'sd0; out <= 16'sd0;
    end
    else begin
        if (ft == 5'd31 && c == 5'd12 && !pause) begin
            s_b0 <= acc_b0; s_b2 <= acc_b2; s_b3 <= acc_b3; s_fire <= acc_fire;
            s_noise <= noise; s_en <= {en_i[1], en_i[0], en_i[2]}; s_fire_l <= fire_i; s_vol <= vol_i;
            st <= 7'd0;
        end
        else if (st != 7'd127) st <= st + 7'd1;

        if (ft == 5'd15 && c == 5'd13 && !pause) begin
            rcf <= rcf_new; out <= out_new;
        end

        // noise channel k (s_noise / s_en bit k): RCDISC5 then the 1M band-pass (MAME biquad), clipped to the rails
        if (st < 7'd33) case (cs)
            4'd0: begin diff <= (s_en[ch] ? VU : 36'sd0) - cap[ch]; sa <= (s_en[ch] ? VU : 36'sd0) - cap[ch]; sb <= ck(ch, 3'd0); end
            4'd2: begin : rc_step
                reg signed [35:0] hc;
                if (s_noise[ch]) begin
                    hc = cap[ch] + (diff < 0 ? sq : diff);
                    cap[ch] <= hc;
                end
                else begin
                    hc = 36'sd0;
                    if (diff > 0) cap[ch] <= s_en[ch] ? VU : 36'sd0;
                end
                sa <= hc - VREF; sb <= ck(ch, 3'd1);
            end
            4'd4: begin x <= sq + ck(ch, 3'd2); sa <= y1[ch]; sb <= -ck(ch, 3'd3); end
            4'd5: begin sa <= y2[ch]; sb <= -ck(ch, 3'd4); end
            4'd6: begin bq <= sp; sa <= x; sb <= ck(ch, 3'd5); end
            4'd7: begin bq <= bq + sp; sa <= x2[ch]; sb <= -ck(ch, 3'd5); end
            4'd8: bq <= bq + sp;
            4'd9: bq <= bq + sp;
            4'd10: begin : bq_out
                reg signed [35:0] v;
                v = clamp(36'(bq >>> 28) + VREF, 36'sd0, VPMAX);
                vo[ch] <= v;
                x2[ch] <= x1[ch]; x1[ch] <= x; y2[ch] <= y1[ch]; y1[ch] <= v - VREF;
            end
            default: ;
        endcase
        else case (st)
            // fire RC (R47, C28) on !FIRE, then its CV term through R48
            7'd33: begin sa <= (s_fire_l ? 36'sd0 : VTTL) - rc173; sb <= FIRE_KRC; end
            7'd35: begin rc173 <= rc173 + sq; sa <= rc173 + sq; sb <= CV_F; end
            7'd37: rcf_new <= sq;
            // 0.1uF input coupling on the three noise inputs and fire (R || R91)
            7'd38: begin sa <= vo[0] - hpc[0]; sb <= KHP_N; end
            7'd39: begin sa <= vo[1] - hpc[1]; sb <= KHP_N; end
            7'd40: begin sa <= vo[2] - hpc[2]; sb <= KHP_N; hpc[0] <= hpc[0] + sq; hsum <= vo[0] - (hpc[0] + sq); end
            7'd41: begin sa <= 36'(s_fire >> 5) - hpc[3]; sb <= KHP_F; hpc[1] <= hpc[1] + sq; hsum <= hsum + vo[1] - (hpc[1] + sq); end
            7'd42: begin hpc[2] <= hpc[2] + sq; hsum <= hsum + vo[2] - (hpc[2] + sq); end
            7'd43: begin hpc[3] <= hpc[3] + sq; hfire <= 36'(s_fire >> 5) - (hpc[3] + sq); end
            // resistor mixer (Millman over the connected inputs), then C46
            7'd44: begin sa <= 36'(s_b0) <<< 15; sb <= mk(s_vol, 3'd0); end
            7'd45: begin sa <= 36'(s_b2) <<< 15; sb <= mk(s_vol, 3'd1); end
            7'd46: begin o <= sq; sa <= 36'(s_b3) <<< 15; sb <= mk(s_vol, 3'd2); end
            7'd47: begin o <= o + sq; sa <= hsum; sb <= mk(s_vol, 3'd3); end
            7'd48: begin o <= o + sq; sa <= hfire; sb <= mk(s_vol, 3'd4); end
            7'd49: o <= o + sq;
            7'd50: o <= o + sq;
            7'd51: begin sa <= o - amp_cap; sb <= KAMP; end
            7'd53: begin : out_step
                reg signed [35:0] a, r;
                a = amp_cap + sq;
                amp_cap <= a;
                r = (o - a) >>> 5;
                out_new <= r > 36'sd32767 ? 16'sd32767 : r < -36'sd32768 ? -16'sd32768 : 16'(r);
            end
            default: ;
        endcase
    end
end

endmodule
