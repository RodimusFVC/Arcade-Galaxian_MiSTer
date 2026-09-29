//============================================================================
//
//  Galaxian / Moon Cresta discrete sound (Midway schematic page 22)
//
//  Circuit model and values from MAME galaxian_a.cpp (Couriersud). Noise is
//  the star LFSR's N3A latched by 2V (7474 at 2D), as on the schematic; R40
//  at its schematic 2.2k. Bit-exact to verilator/galsnd/galsnd_model.h.
//
//  1.536 MHz: background and fire 555s, fire RC discharge, pitch counter.
//  48 kHz: LFO, hit, filters and mixers, from a snapshot of the fast stage;
//  CV, the fire CV term and the output sample are published mid-period.
//  Voltages Q20, coefficients Q24, band-pass coefficients Q28.
//
//============================================================================

module galaxian_sound
(
    input                    clk,            // 49.152 MHz
    input                    reset,
    input                    mc,             // Moon Cresta final mixer
    input                    pdiv8,          // pitch counter at 1/8 rate (Bongo)
    input                    pause,          // freezes every oscillator; the output holds its last sample
    input                    v2,             // 2V (vcnt[1])
    input                    n3a,            // star LFSR N3A
    input              [3:0] lfo,            // 6004-6007
    input              [2:0] fs,             // 6800-6802
    input                    hit,            // 6803
    input                    fire,           // 6805
    input              [1:0] vol,            // 6806-6807
    input              [7:0] pitch,          // 7800
    output reg signed [15:0] out = 16'sd0
);

localparam signed [35:0] LFO_DV0   = 36'sd206;
localparam signed [35:0] LFO_DV1   = 36'sd196;
localparam signed [35:0] LFO_DV2   = 36'sd185;
localparam signed [35:0] LFO_DV3   = 36'sd175;
localparam signed [35:0] LFO_DV4   = 36'sd160;
localparam signed [35:0] LFO_DV5   = 36'sd150;
localparam signed [35:0] LFO_DV6   = 36'sd139;
localparam signed [35:0] LFO_DV7   = 36'sd129;
localparam signed [35:0] LFO_DV8   = 36'sd106;
localparam signed [35:0] LFO_DV9   = 36'sd96;
localparam signed [35:0] LFO_DV10  = 36'sd85;
localparam signed [35:0] LFO_DV11  = 36'sd75;
localparam signed [35:0] LFO_DV12  = 36'sd60;
localparam signed [35:0] LFO_DV13  = 36'sd50;
localparam signed [35:0] LFO_DV14  = 36'sd39;
localparam signed [35:0] LFO_DV15  = 36'sd29;
localparam signed [35:0] LFO_LIM0  = 36'sd4254456;
localparam signed [35:0] LFO_LIM1  = 36'sd4302463;
localparam signed [35:0] LFO_LIM2  = 36'sd4356597;
localparam signed [35:0] LFO_LIM3  = 36'sd4404603;
localparam signed [35:0] LFO_LIM4  = 36'sd4472666;
localparam signed [35:0] LFO_LIM5  = 36'sd4520673;
localparam signed [35:0] LFO_LIM6  = 36'sd4574807;
localparam signed [35:0] LFO_LIM7  = 36'sd4622813;
localparam signed [35:0] LFO_LIM8  = 36'sd4734518;
localparam signed [35:0] LFO_LIM9  = 36'sd4782524;
localparam signed [35:0] LFO_LIM10 = 36'sd4836659;
localparam signed [35:0] LFO_LIM11 = 36'sd4884665;
localparam signed [35:0] LFO_LIM12 = 36'sd4952728;
localparam signed [35:0] LFO_LIM13 = 36'sd5000734;
localparam signed [35:0] LFO_LIM14 = 36'sd5054869;
localparam signed [35:0] LFO_LIM15 = 36'sd5102875;
localparam signed [35:0] LFO_TH    = 36'sd3495253;
localparam signed [35:0] LFO_STEP  = 36'sd1747626;
localparam signed [35:0] MA_G      = 36'sd5979114;
localparam signed [35:0] MA_O      = -36'sd1115506;
localparam signed [35:0] BG_KC0    = 36'sd1916;
localparam signed [35:0] BG_KD0    = 36'sd2324;
localparam signed [35:0] BG_KC1    = 36'sd2540;
localparam signed [35:0] BG_KD1    = 36'sd3310;
localparam signed [35:0] BG_KC2    = 36'sd3413;
localparam signed [35:0] BG_KD2    = 36'sd4964;
localparam signed [35:0] V5        = 36'sd5242880;
localparam signed [35:0] V025      = 36'sd262144;
localparam signed [35:0] BG_KMIX   = 36'sd1016480;
localparam signed [35:0] FIRE_KRC  = 36'sd3380;
localparam signed [35:0] CV_N      = 36'sd756350;
localparam signed [35:0] CV_F      = 36'sd13751816;
localparam signed [35:0] FI_KC     = 36'sd34099;
localparam signed [35:0] FI_KD     = 36'sd49575;
localparam signed [35:0] FI_KDIS   = 36'sd109;
localparam signed [35:0] VU        = 36'sd3460301;
localparam signed [35:0] VTTL      = 36'sd4194304;
localparam signed [35:0] HIT_KDIS  = 36'sd924;
localparam signed [35:0] BP_A      = 36'sd2145923;
localparam signed [35:0] BP_C      = -36'sd1828912;
localparam signed [35:0] BQ_A1     = -36'sd534373228;
localparam signed [35:0] BQ_A2     = 36'sd266066400;
localparam signed [35:0] BQ_B0     = -36'sd14508672;
localparam signed [35:0] VREF      = 36'sd2097152;
localparam signed [35:0] VPMAX     = 36'sd3670016;
localparam signed [35:0] PRE00     = 36'sd1870247;
localparam signed [35:0] PRE01     = 36'sd2805371;
localparam signed [35:0] PRE02     = 36'sd0;
localparam signed [35:0] PRE03     = 36'sd12101598;
localparam signed [35:0] PRE10     = 36'sd1367271;
localparam signed [35:0] PRE11     = 36'sd6562899;
localparam signed [35:0] PRE12     = 36'sd0;
localparam signed [35:0] PRE13     = 36'sd8847046;
localparam signed [35:0] PRE20     = 36'sd1501910;
localparam signed [35:0] PRE21     = 36'sd2252865;
localparam signed [35:0] PRE22     = 36'sd3304202;
localparam signed [35:0] PRE23     = 36'sd9718240;
localparam signed [35:0] PRE30     = 36'sd1159401;
localparam signed [35:0] PRE31     = 36'sd5565125;
localparam signed [35:0] PRE32     = 36'sd2550682;
localparam signed [35:0] PRE33     = 36'sd7502007;
localparam signed [35:0] PMC00     = 36'sd483493;
localparam signed [35:0] PMC01     = 36'sd725240;
localparam signed [35:0] PMC02     = 36'sd0;
localparam signed [35:0] PMC03     = 36'sd1063685;
localparam signed [35:0] PMC10     = 36'sd441506;
localparam signed [35:0] PMC11     = 36'sd2119227;
localparam signed [35:0] PMC12     = 36'sd0;
localparam signed [35:0] PMC13     = 36'sd971313;
localparam signed [35:0] PMC20     = 36'sd454667;
localparam signed [35:0] PMC21     = 36'sd682001;
localparam signed [35:0] PMC22     = 36'sd1000268;
localparam signed [35:0] PMC23     = 36'sd1000268;
localparam signed [35:0] PMC30     = 36'sd417344;
localparam signed [35:0] PMC31     = 36'sd2003250;
localparam signed [35:0] PMC32     = 36'sd918156;
localparam signed [35:0] PMC33     = 36'sd918156;
localparam signed [35:0] FMC0      = 36'sd7252399;
localparam signed [35:0] FMC1      = 36'sd6622585;
localparam signed [35:0] FMC2      = 36'sd6820007;
localparam signed [35:0] FMC3      = 36'sd6260155;
localparam signed [35:0] FM_KHP_MC = 36'sd10269087;
localparam signed [35:0] K_ONE     = 36'sd16777216;
localparam signed [35:0] FM0       = 36'sd2729617;
localparam signed [35:0] FM1       = 36'sd6327747;
localparam signed [35:0] FM2       = 36'sd6327747;
localparam signed [35:0] FM_KHP    = 36'sd11493029;
localparam signed [35:0] FM_KAMP   = 36'sd34916;

function signed [35:0] lfo_dv(input [3:0] i);
    case (i)
        4'd0: lfo_dv = LFO_DV0;   4'd1: lfo_dv = LFO_DV1;   4'd2: lfo_dv = LFO_DV2;   4'd3: lfo_dv = LFO_DV3;
        4'd4: lfo_dv = LFO_DV4;   4'd5: lfo_dv = LFO_DV5;   4'd6: lfo_dv = LFO_DV6;   4'd7: lfo_dv = LFO_DV7;
        4'd8: lfo_dv = LFO_DV8;   4'd9: lfo_dv = LFO_DV9;   4'd10: lfo_dv = LFO_DV10; 4'd11: lfo_dv = LFO_DV11;
        4'd12: lfo_dv = LFO_DV12; 4'd13: lfo_dv = LFO_DV13; 4'd14: lfo_dv = LFO_DV14; default: lfo_dv = LFO_DV15;
    endcase
endfunction

function signed [35:0] lfo_lim(input [3:0] i);
    case (i)
        4'd0: lfo_lim = LFO_LIM0;   4'd1: lfo_lim = LFO_LIM1;   4'd2: lfo_lim = LFO_LIM2;   4'd3: lfo_lim = LFO_LIM3;
        4'd4: lfo_lim = LFO_LIM4;   4'd5: lfo_lim = LFO_LIM5;   4'd6: lfo_lim = LFO_LIM6;   4'd7: lfo_lim = LFO_LIM7;
        4'd8: lfo_lim = LFO_LIM8;   4'd9: lfo_lim = LFO_LIM9;   4'd10: lfo_lim = LFO_LIM10; 4'd11: lfo_lim = LFO_LIM11;
        4'd12: lfo_lim = LFO_LIM12; 4'd13: lfo_lim = LFO_LIM13; 4'd14: lfo_lim = LFO_LIM14; default: lfo_lim = LFO_LIM15;
    endcase
endfunction

function signed [35:0] pre_k(input [1:0] v, input [1:0] k);
    case ({mc, v, k})
        5'h00: pre_k = PRE00; 5'h01: pre_k = PRE01; 5'h02: pre_k = PRE02; 5'h03: pre_k = PRE03;
        5'h04: pre_k = PRE10; 5'h05: pre_k = PRE11; 5'h06: pre_k = PRE12; 5'h07: pre_k = PRE13;
        5'h08: pre_k = PRE20; 5'h09: pre_k = PRE21; 5'h0A: pre_k = PRE22; 5'h0B: pre_k = PRE23;
        5'h0C: pre_k = PRE30; 5'h0D: pre_k = PRE31; 5'h0E: pre_k = PRE32; 5'h0F: pre_k = PRE33;
        5'h10: pre_k = PMC00; 5'h11: pre_k = PMC01; 5'h12: pre_k = PMC02; 5'h13: pre_k = PMC03;
        5'h14: pre_k = PMC10; 5'h15: pre_k = PMC11; 5'h16: pre_k = PMC12; 5'h17: pre_k = PMC13;
        5'h18: pre_k = PMC20; 5'h19: pre_k = PMC21; 5'h1A: pre_k = PMC22; 5'h1B: pre_k = PMC23;
        5'h1C: pre_k = PMC30; 5'h1D: pre_k = PMC31; 5'h1E: pre_k = PMC32; default: pre_k = PMC33;
    endcase
endfunction

// final mixer weights of the hit and fire inputs
function signed [35:0] fm_k(input [1:0] v, input signed [35:0] gal);
    case ({mc, v})
        3'b100:  fm_k = FMC0;
        3'b101:  fm_k = FMC1;
        3'b110:  fm_k = FMC2;
        3'b111:  fm_k = FMC3;
        default: fm_k = gal;
    endcase
endfunction

function signed [35:0] clamp(input signed [35:0] v, input signed [35:0] lo, input signed [35:0] hi);
    clamp = v < lo ? lo : v > hi ? hi : v;
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

reg  [3:0] lfo_i = 4'd0;
reg  [2:0] fs_i = 3'd0;
reg        hit_i = 1'b0, fire_i = 1'b0;
reg  [1:0] vol_i = 2'd0;
reg  [7:0] pitch_i = 8'hFF;
reg        v2_d = 1'b0, noise = 1'b0;

reg  [7:0] c1 = 8'hFF;
reg  [3:0] c2 = 4'd0;
reg signed [35:0] bg_v[3], fi_v = 36'sd0, fi_cap = 36'sd0;
reg  [2:0] bg_ff = 3'b111, bg_ffp;
reg        fi_ff = 1'b1, fi_ffp, fi_run;
reg  [6:0] acc_bg = 7'd0;
reg  [5:0] acc_b0 = 6'd0, acc_b2 = 6'd0, acc_b3 = 6'd0;
reg [31:0] acc_fire = 32'd0;

// published by the sample stage
reg signed [35:0] cv = 36'sd0, rcf = 36'sd0;

// fast multiplier: operands registered at issue, product registered the next clock, used the clock after
reg signed [35:0] fa, fb;
reg signed [71:0] fp;
always @(posedge clk) fp <= fa * fb;
wire signed [35:0] fq = 36'(fp >>> 24);
// rounded up: the fire capacitor's discharge step never truncates to 0, so it drains fully (a floored step left
// ~0.15 V on C that the free-running fire 555 turned into a permanent hiss after the first shot)
wire signed [35:0] fq_up = 36'((fp + 72'sd16777215) >>> 24);

wire       pstep = ~pdiv8 | ft[2:0] == 3'd0;
wire [3:0] c2_n = (pstep && pitch_i != 8'hFF && c1 == 8'hFF) ? c2 + 4'd1 : c2;
wire signed [35:0] cvf = (noise ? CV_N : 36'sd0) + rcf;
wire signed [35:0] u_fire = fire_i ? VU : 36'sd0;

integer n;
initial for (n = 0; n < 3; n = n + 1) bg_v[n] = 36'sd0;

// one 555 step: pre-check the flip-flop against the thresholds, then charge toward 5 V or discharge
function [0:0] ff_pre(input signed [35:0] v, input ff, input signed [35:0] th);
    ff_pre = (v >= th) ? 1'b0 : (v <= (th >>> 1)) ? 1'b1 : ff;
endfunction

always @(posedge clk) begin
    if (reset) begin
        c1 <= 8'hFF; c2 <= 4'd0; noise <= 1'b0; v2_d <= 1'b0;
        for (n = 0; n < 3; n = n + 1) bg_v[n] <= 36'sd0;
        bg_ff <= 3'b111; fi_v <= 36'sd0; fi_ff <= 1'b1; fi_cap <= 36'sd0;
        acc_bg <= 7'd0; acc_b0 <= 6'd0; acc_b2 <= 6'd0; acc_b3 <= 6'd0; acc_fire <= 32'd0;
    end
    else if (!pause) case (c)
        5'd0: begin
            lfo_i <= lfo; fs_i <= fs; hit_i <= hit; fire_i <= fire; vol_i <= vol; pitch_i <= pitch;
            if (v2 && !v2_d) noise <= n3a;
            v2_d <= v2;
        end
        5'd1: begin
            if (pstep && pitch_i != 8'hFF) begin
                c1 <= (c1 == 8'hFF) ? pitch_i : c1 + 8'd1;
                c2 <= c2_n;
            end
            acc_b0 <= acc_b0 + c2_n[0];
            acc_b2 <= acc_b2 + c2_n[2];
            acc_b3 <= acc_b3 + c2_n[3];
        end
        5'd2, 5'd3, 5'd4: begin : bg_issue
            reg [1:0] k;
            reg f;
            k = c[1:0] - 2'd2;
            f = ff_pre(bg_v[k], bg_ff[k], cv);
            bg_ffp[k] <= f;
            fa <= f ? V5 - bg_v[k] : bg_v[k];
            fb <= f ? (k == 0 ? BG_KC0 : k == 1 ? BG_KC1 : BG_KC2) : (k == 0 ? BG_KD0 : k == 1 ? BG_KD1 : BG_KD2);
        end
        5'd5: begin
            fi_run <= cvf >= V025;
            fi_ffp <= ff_pre(fi_v, fi_ff, cvf);
            fa <= ff_pre(fi_v, fi_ff, cvf) ? V5 - fi_v : fi_v;
            fb <= ff_pre(fi_v, fi_ff, cvf) ? FI_KC : FI_KD;
        end
        default: ;
    endcase

    // completions, two clocks after issue
    if (!reset) begin
        if (c >= 5'd4 && c <= 5'd6) begin : bg_done
            reg [1:0] k;
            reg signed [35:0] vn;
            k = c[1:0];
            if (!fs_i[k]) begin
                bg_v[k] <= 36'sd0; bg_ff[k] <= 1'b1;
            end
            else begin
                vn = bg_ffp[k] ? bg_v[k] + fq : bg_v[k] - fq;
                if (bg_ffp[k] && vn >= cv)               begin bg_v[k] <= cv;       bg_ff[k] <= 1'b0; end
                else if (!bg_ffp[k] && vn <= (cv >>> 1)) begin bg_v[k] <= cv >>> 1; bg_ff[k] <= 1'b1; end
                else                                     begin bg_v[k] <= vn;       bg_ff[k] <= bg_ffp[k]; end
            end
        end
        if (c == 5'd7 && fi_run) begin : fi_done
            reg signed [35:0] vn;
            vn = fi_ffp ? fi_v + fq : fi_v - fq;
            if (fi_ffp && vn >= cvf)               begin fi_v <= cvf;       fi_ff <= 1'b0; end
            else if (!fi_ffp && vn <= (cvf >>> 1)) begin fi_v <= cvf >>> 1; fi_ff <= 1'b1; end
            else                                   begin fi_v <= vn;        fi_ff <= fi_ffp; end
        end
        // fire RCDISC5: the diode charges C25 at once, R41 discharges it; only passed while the 555 is high
        if (c == 5'd8) begin
            fa <= fi_cap - u_fire;
            fb <= FI_KDIS;
        end
        if (c == 5'd10) begin
            if (fi_ff) begin
                if (u_fire > fi_cap) begin fi_cap <= u_fire; acc_fire <= acc_fire + 32'(u_fire); end
                else begin fi_cap <= fi_cap - fq_up; acc_fire <= acc_fire + 32'(fi_cap - fq_up); end
            end
            else if (u_fire > fi_cap) fi_cap <= u_fire;
        end
        if (c == 5'd7) acc_bg <= acc_bg + ((fs_i[0] ? bg_ff[0] : 1'b0) + (fs_i[1] ? bg_ff[1] : 1'b0) + (fs_i[2] ? bg_ff[2] : 1'b0));
        if (c == 5'd12 && ft == 5'd31) begin
            acc_bg <= 7'd0; acc_b0 <= 6'd0; acc_b2 <= 6'd0; acc_b3 <= 6'd0; acc_fire <= 32'd0;
        end
    end
end

//----------------------------------------------------- Sample stage -----------------------------------------------------//

// snapshot after fast tick 31, program runs one step per clock, results published after fast tick 15
reg  [6:0] s_bg;
reg  [5:0] s_b0, s_b2, s_b3;
reg [31:0] s_fire;
reg        s_noise, s_hit, s_fire_l;
reg  [1:0] s_vol;
reg  [3:0] s_lfo;
reg  [5:0] st = 6'd63;

reg signed [35:0] lfo_v = 36'sd0, bgmix = 36'sd0, rc173 = 36'sd0, hit_cap = 36'sd0;
reg signed [35:0] x1 = 36'sd0, x2 = 36'sd0, y1 = 36'sd0, y2 = 36'sd0, hp_cap = 36'sd0, amp_cap = 36'sd0;
reg signed [35:0] cv_new = 36'sd0, rcf_new = 36'sd0, pre, diff, h, x, vo, fr, o;
reg signed [71:0] bq;
reg signed [15:0] out_new = 16'sd0;

reg signed [35:0] sa, sb;
reg signed [71:0] sp;
always @(posedge clk) sp <= sa * sb;
wire signed [35:0] sq = 36'(sp >>> 24);

always @(posedge clk) begin
    if (reset) begin
        st <= 6'd63;
        lfo_v <= 36'sd0; bgmix <= 36'sd0; rc173 <= 36'sd0; hit_cap <= 36'sd0;
        x1 <= 36'sd0; x2 <= 36'sd0; y1 <= 36'sd0; y2 <= 36'sd0; hp_cap <= 36'sd0; amp_cap <= 36'sd0;
        cv_new <= 36'sd0; rcf_new <= 36'sd0; out_new <= 16'sd0;
        cv <= 36'sd0; rcf <= 36'sd0; out <= 16'sd0;
    end
    else begin
        if (ft == 5'd31 && c == 5'd12 && !pause) begin
            s_bg <= acc_bg; s_b0 <= acc_b0; s_b2 <= acc_b2; s_b3 <= acc_b3; s_fire <= acc_fire;
            s_noise <= noise; s_hit <= hit_i; s_fire_l <= fire_i; s_vol <= vol_i; s_lfo <= lfo_i;
            st <= 6'd0;
        end
        else if (st != 6'd63) st <= st + 6'd1;

        if (ft == 5'd15 && c == 5'd13 && !pause) begin
            cv <= cv_new; rcf <= rcf_new; out <= out_new;
        end

        case (st)
            6'd0: begin : lfo_step
                reg signed [35:0] v;
                v = lfo_v + lfo_dv(s_lfo);
                if (v > lfo_lim(s_lfo)) v = lfo_lim(s_lfo);
                if (v >= LFO_TH) v = v - LFO_STEP;
                lfo_v <= v;
                sa <= v; sb <= MA_G;
            end
            6'd1: begin sa <= 36'(s_bg) * 36'sd49152 - bgmix; sb <= BG_KMIX; end
            6'd2: begin cv_new <= clamp((sq <<< 2) + MA_O, 36'sd0, V5); sa <= 36'(s_b0) <<< 15; sb <= pre_k(s_vol, 2'd0); end
            6'd3: begin bgmix <= bgmix + sq; sa <= 36'(s_b2) <<< 15; sb <= pre_k(s_vol, 2'd1); end
            6'd4: begin pre <= sq <<< 2; sa <= 36'(s_b3) <<< 15; sb <= pre_k(s_vol, 2'd2); end
            6'd5: begin pre <= pre + (sq <<< 2); sa <= bgmix; sb <= pre_k(s_vol, 2'd3); end
            6'd6: begin pre <= pre + (sq <<< 2); sa <= (s_fire_l ? 36'sd0 : VTTL) - rc173; sb <= FIRE_KRC; end
            6'd7: begin
                pre <= pre + sq;
                diff <= (s_hit ? VU : 36'sd0) - hit_cap;
                sa <= (s_hit ? VU : 36'sd0) - hit_cap; sb <= HIT_KDIS;
            end
            6'd8: begin rc173 <= rc173 + sq; sa <= rc173 + sq; sb <= CV_F; end
            6'd9: begin : hit_step
                reg signed [35:0] hc;
                if (s_noise) begin
                    hc = hit_cap + (diff < 0 ? sq : diff);
                    hit_cap <= hc;
                end
                else begin
                    hc = 36'sd0;
                    if (diff > 0) hit_cap <= s_hit ? VU : 36'sd0;
                end
                h <= hc;
                sa <= hc - VREF; sb <= BP_A;
            end
            6'd10: rcf_new <= sq;
            6'd11: begin x <= sq + BP_C; sa <= y1; sb <= -BQ_A1; end
            6'd12: begin sa <= y2; sb <= -BQ_A2; end
            6'd13: begin bq <= sp; sa <= x; sb <= BQ_B0; end
            6'd14: begin bq <= bq + sp; sa <= x2; sb <= -BQ_B0; end
            6'd15: bq <= bq + sp;
            6'd16: bq <= bq + sp;
            6'd17: begin : bq_out
                reg signed [35:0] y, v;
                y = 36'(bq >>> 28);
                v = clamp(y + VREF, 36'sd0, VPMAX);
                vo <= v;
                x2 <= x1; x1 <= x; y2 <= y1; y1 <= v - VREF;
                fr <= 36'(s_fire >> 5);
                sa <= 36'(s_fire >> 5) - hp_cap; sb <= mc ? FM_KHP_MC : FM_KHP;
            end
            6'd18: begin sa <= pre; sb <= mc ? K_ONE : FM0; end
            6'd19: begin hp_cap <= hp_cap + sq; sa <= vo; sb <= fm_k(s_vol, FM1); end
            6'd20: begin o <= sq; sa <= fr - hp_cap; sb <= fm_k(s_vol, FM2); end
            6'd21: o <= o + sq;
            6'd22: o <= o + sq;
            6'd23: begin sa <= o - amp_cap; sb <= FM_KAMP; end
            6'd25: begin : out_step
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
