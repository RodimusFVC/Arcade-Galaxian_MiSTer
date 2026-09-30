//============================================================================
//
//  TMS5110A LPC speech synthesizer
//  Copyright (C) 2026 Rodimus
//
//  Port of MAME devices/sound/tms5110.cpp (BSD-3-Clause; Frank Palazzolo,
//  Jarek Burczynski, Aaron Giles, Jonathan Gevaryahu, Couriersud)
//
//  ce_sample   one output sample (chip clock / 80)
//  m0          advances the VSM address; data_bit is sampled BIT_WAIT clocks later
//  busy        high while a sample or command is in flight (VSM holds its clock)
//
//============================================================================

module tms5110 #(parameter BIT_WAIT = 4)
(
    input                    clk,
    input                    reset,
    input                    ce_sample,
    input              [3:0] ctl,
    input                    pdc,
    output reg               m0,
    input                    data_bit,
    output                   busy,
    output                   talk_status,
    output reg signed [15:0] sample
);

//------------------------------------------------------- TMS5110A tables (MAME tms5110r.hxx) ----------------------------------//

function automatic [7:0] energy_tab(input [3:0] i);        // TI_028X_LATER_ENERGY
    case (i)
        0: energy_tab = 0;   1: energy_tab = 1;   2: energy_tab = 2;   3: energy_tab = 3;
        4: energy_tab = 4;   5: energy_tab = 6;   6: energy_tab = 8;   7: energy_tab = 11;
        8: energy_tab = 16;  9: energy_tab = 23;  10: energy_tab = 33; 11: energy_tab = 47;
        12: energy_tab = 63; 13: energy_tab = 85; 14: energy_tab = 114; default: energy_tab = 0;
    endcase
endfunction

function automatic [7:0] pitch_tab(input [4:0] i);         // TI_5110_PITCH
    case (i)
        0: pitch_tab = 0;    1: pitch_tab = 15;   2: pitch_tab = 16;   3: pitch_tab = 17;
        4: pitch_tab = 19;   5: pitch_tab = 21;   6: pitch_tab = 22;   7: pitch_tab = 25;
        8: pitch_tab = 26;   9: pitch_tab = 29;   10: pitch_tab = 32;  11: pitch_tab = 36;
        12: pitch_tab = 40;  13: pitch_tab = 42;  14: pitch_tab = 46;  15: pitch_tab = 50;
        16: pitch_tab = 55;  17: pitch_tab = 60;  18: pitch_tab = 64;  19: pitch_tab = 68;
        20: pitch_tab = 72;  21: pitch_tab = 76;  22: pitch_tab = 80;  23: pitch_tab = 84;
        24: pitch_tab = 86;  25: pitch_tab = 93;  26: pitch_tab = 101; 27: pitch_tab = 110;
        28: pitch_tab = 120; 29: pitch_tab = 132; 30: pitch_tab = 144; default: pitch_tab = 159;
    endcase
endfunction

function automatic signed [9:0] k_tab(input [3:0] k, input [4:0] i);   // TI_5110_5220_LPC
    case (k)
    0: case (i)
        0: k_tab = -501;  1: k_tab = -498;  2: k_tab = -497;  3: k_tab = -495;
        4: k_tab = -493;  5: k_tab = -491;  6: k_tab = -488;  7: k_tab = -482;
        8: k_tab = -478;  9: k_tab = -474;  10: k_tab = -469; 11: k_tab = -464;
        12: k_tab = -459; 13: k_tab = -452; 14: k_tab = -445; 15: k_tab = -437;
        16: k_tab = -412; 17: k_tab = -380; 18: k_tab = -339; 19: k_tab = -288;
        20: k_tab = -227; 21: k_tab = -158; 22: k_tab = -81;  23: k_tab = -1;
        24: k_tab = 80;   25: k_tab = 157;  26: k_tab = 226;  27: k_tab = 287;
        28: k_tab = 337;  29: k_tab = 379;  30: k_tab = 411;  default: k_tab = 436;
       endcase
    1: case (i)
        0: k_tab = -328;  1: k_tab = -303;  2: k_tab = -274;  3: k_tab = -244;
        4: k_tab = -211;  5: k_tab = -175;  6: k_tab = -138;  7: k_tab = -99;
        8: k_tab = -59;   9: k_tab = -18;   10: k_tab = 24;   11: k_tab = 64;
        12: k_tab = 105;  13: k_tab = 143;  14: k_tab = 180;  15: k_tab = 215;
        16: k_tab = 248;  17: k_tab = 278;  18: k_tab = 306;  19: k_tab = 331;
        20: k_tab = 354;  21: k_tab = 374;  22: k_tab = 392;  23: k_tab = 408;
        24: k_tab = 422;  25: k_tab = 435;  26: k_tab = 445;  27: k_tab = 455;
        28: k_tab = 463;  29: k_tab = 470;  30: k_tab = 476;  default: k_tab = 506;
       endcase
    2: case (i[3:0])
        0: k_tab = -441;  1: k_tab = -387;  2: k_tab = -333;  3: k_tab = -279;
        4: k_tab = -225;  5: k_tab = -171;  6: k_tab = -117;  7: k_tab = -63;
        8: k_tab = -9;    9: k_tab = 45;    10: k_tab = 98;   11: k_tab = 152;
        12: k_tab = 206;  13: k_tab = 260;  14: k_tab = 314;  default: k_tab = 368;
       endcase
    3: case (i[3:0])
        0: k_tab = -328;  1: k_tab = -273;  2: k_tab = -217;  3: k_tab = -161;
        4: k_tab = -106;  5: k_tab = -50;   6: k_tab = 5;     7: k_tab = 61;
        8: k_tab = 116;   9: k_tab = 172;   10: k_tab = 228;  11: k_tab = 283;
        12: k_tab = 339;  13: k_tab = 394;  14: k_tab = 450;  default: k_tab = 506;
       endcase
    4: case (i[3:0])
        0: k_tab = -328;  1: k_tab = -282;  2: k_tab = -235;  3: k_tab = -189;
        4: k_tab = -142;  5: k_tab = -96;   6: k_tab = -50;   7: k_tab = -3;
        8: k_tab = 43;    9: k_tab = 90;    10: k_tab = 136;  11: k_tab = 182;
        12: k_tab = 229;  13: k_tab = 275;  14: k_tab = 322;  default: k_tab = 368;
       endcase
    5: case (i[3:0])
        0: k_tab = -256;  1: k_tab = -212;  2: k_tab = -168;  3: k_tab = -123;
        4: k_tab = -79;   5: k_tab = -35;   6: k_tab = 10;    7: k_tab = 54;
        8: k_tab = 98;    9: k_tab = 143;   10: k_tab = 187;  11: k_tab = 232;
        12: k_tab = 276;  13: k_tab = 320;  14: k_tab = 365;  default: k_tab = 409;
       endcase
    6: case (i[3:0])
        0: k_tab = -308;  1: k_tab = -260;  2: k_tab = -212;  3: k_tab = -164;
        4: k_tab = -117;  5: k_tab = -69;   6: k_tab = -21;   7: k_tab = 27;
        8: k_tab = 75;    9: k_tab = 122;   10: k_tab = 170;  11: k_tab = 218;
        12: k_tab = 266;  13: k_tab = 314;  14: k_tab = 361;  default: k_tab = 409;
       endcase
    7: case (i[2:0])
        0: k_tab = -256;  1: k_tab = -161;  2: k_tab = -66;   3: k_tab = 29;
        4: k_tab = 124;   5: k_tab = 219;   6: k_tab = 314;   default: k_tab = 409;
       endcase
    8: case (i[2:0])
        0: k_tab = -256;  1: k_tab = -176;  2: k_tab = -96;   3: k_tab = -15;
        4: k_tab = 65;    5: k_tab = 146;   6: k_tab = 226;   default: k_tab = 307;
       endcase
    default: case (i[2:0])
        0: k_tab = -205;  1: k_tab = -132;  2: k_tab = -59;   3: k_tab = 14;
        4: k_tab = 87;    5: k_tab = 160;   6: k_tab = 234;   default: k_tab = 307;
       endcase
    endcase
endfunction

function automatic signed [7:0] chirp_tab(input [5:0] i);  // TI_LATER_CHIRP (entries 21-51 are 0)
    case (i)
        0: chirp_tab = 8'h00;  1: chirp_tab = 8'h03;  2: chirp_tab = 8'h0f;  3: chirp_tab = 8'h28;
        4: chirp_tab = 8'h4c;  5: chirp_tab = 8'h6c;  6: chirp_tab = 8'h71;  7: chirp_tab = 8'h50;
        8: chirp_tab = 8'h25;  9: chirp_tab = 8'h26;  10: chirp_tab = 8'h4c; 11: chirp_tab = 8'h44;
        12: chirp_tab = 8'h1a; 13: chirp_tab = 8'h32; 14: chirp_tab = 8'h3b; 15: chirp_tab = 8'h13;
        16: chirp_tab = 8'h37; 17: chirp_tab = 8'h1a; 18: chirp_tab = 8'h25; 19: chirp_tab = 8'h1f;
        20: chirp_tab = 8'h1d; default: chirp_tab = 8'h00;
    endcase
endfunction

function automatic [1:0] interp_shift(input [2:0] ip);     // TI_INTERP {0,3,3,3,2,2,1,1}
    case (ip)
        0: interp_shift = 0; 1, 2, 3: interp_shift = 3; 4, 5: interp_shift = 2; default: interp_shift = 1;
    endcase
endfunction

function automatic [3:0] field_bits(input [3:0] f);        // E, repeat, P, K1..K10
    case (f)
        0: field_bits = 4; 1: field_bits = 1; 2, 3, 4: field_bits = 5;
        5, 6, 7, 8, 9: field_bits = 4; default: field_bits = 3;
    endcase
endfunction

// 20 LFSR steps per sample (one per T cycle)
function automatic [12:0] rng_step20(input [12:0] r);
    reg [12:0] t;
    integer n;
    begin
        t = r;
        for (n = 0; n < 20; n = n + 1) t = {t[11:0], t[12] ^ t[3] ^ t[2] ^ t[0]};
        rng_step20 = t;
    end
endfunction

//------------------------------------------------------- State ----------------------------------------------------------------//

localparam CMD_RESET = 3'd0, CMD_LOAD_ADDRESS = 3'd1, CMD_OUTPUT = 3'd2, CMD_SPKSLOW = 3'd3,
           CMD_READ_BIT = 3'd4, CMD_SPEAK = 3'd5, CMD_READ_BRANCH = 3'd6, CMD_TEST_TALK = 3'd7;

localparam CTL_INPUT = 3'd0, CTL_TTALK = 3'd1, CTL_NEXT_TTALK = 3'd2, CTL_OUTPUT = 3'd3, CTL_NEXT_OUTPUT = 3'd4;

reg        SPEN, TALK, TALKD;
reg  [2:0] ctl_state;
reg        next_is_address, schedule_dummy_read;
reg  [3:0] ctl_buffer;
reg  [3:0] cmd_ctl;

reg        OLDE, OLDP;
reg  [3:0] new_e;
reg  [4:0] new_p;
(* ramstyle = "logic" *) reg [4:0] new_k [0:9];

reg  [7:0] cur_e, cur_p, prev_e;
(* ramstyle = "logic" *) reg signed [9:0] cur_k [0:9];

reg  [1:0] subcycle;
reg        subc_reload;
reg  [3:0] PC;
reg  [2:0] IP;
reg        inhibit, uv_zpar, zpar, pitch_zero;
reg  [8:0] pitch_count;

(* ramstyle = "logic" *) reg signed [14:0] u [0:9];
(* ramstyle = "logic" *) reg signed [14:0] x [0:9];
reg  [12:0] RNG;
reg signed [7:0] excitation;

assign talk_status = SPEN | TALKD;

wire new_stop     = new_e == 4'd15;
wire new_silence  = new_e == 4'd0;
wire new_unvoiced = new_p == 5'd0;

// lattice: one multiplier, a wrapped to 10 bits, b to 15 bits, (a*b)>>9 (MAME matrix_multiply)
reg signed [9:0]  mm_a;
reg signed [14:0] mm_b;
wire signed [24:0] mm_prod = mm_a * mm_b;
wire signed [14:0] mm_res  = mm_prod[23:9];

//------------------------------------------------------- Sequencer ------------------------------------------------------------//

localparam S_IDLE = 4'd0, S_START = 4'd1, S_BIT = 4'd2, S_BITWAIT = 4'd3, S_PARSED = 4'd4, S_INTERP = 4'd5,
           S_EXC = 4'd6, S_LAT_OP = 4'd7, S_LAT_ACC = 4'd8, S_OUT = 4'd9, S_CMD = 4'd10, S_CMD_WAIT = 4'd11;

reg  [3:0] st;
reg        sample_pend, cmd_pend, pdc_d;
reg  [3:0] field, nbits;
reg  [4:0] acc;
reg        rep;
reg  [3:0] wait_cnt;
reg        bit_for_cmd;          // bit read belongs to a command (dummy read / READ_BIT) rather than a frame
reg        discard_bit;          // dummy read: bit is not shifted into the READ BIT buffer
reg  [4:0] lstep;
reg signed [14:0] uacc;

assign busy = (st != S_IDLE) | sample_pend | cmd_pend;

wire [3:0] kpc = PC - 4'd2;

// interpolation targets for the current PC
wire        [4:0]  k_idx   = new_k[kpc];
wire signed [9:0]  tgt_k   = k_tab(kpc, k_idx);
wire               inh_st  = inhibit & (IP != 3'd0);
wire [1:0]         sh      = interp_shift(IP);
wire signed [10:0] d_e     = inh_st ? 11'sd0 : ($signed({3'b0, energy_tab(new_e)}) - $signed({3'b0, cur_e}));
wire signed [10:0] d_p     = inh_st ? 11'sd0 : ($signed({3'b0, pitch_tab(new_p)}) - $signed({3'b0, cur_p}));
wire signed [10:0] d_k     = inh_st ? 11'sd0 : (tgt_k - cur_k[kpc]);
wire signed [10:0] n_e     = $signed({3'b0, cur_e}) + (d_e >>> sh);
wire signed [10:0] n_p     = $signed({3'b0, cur_p}) + (d_p >>> sh);
wire signed [10:0] n_k     = cur_k[kpc] + (d_k >>> sh);

// analog clip (MAME clip_analog): 12-bit clamp, low nibble dropped, range-extended to 16 bits
function automatic signed [15:0] clip_analog(input signed [14:0] s);
    reg signed [11:0] c;
    begin
        c = (s > 15'sd2047) ? 12'sd2047 : (s < -15'sd2048) ? -12'sd2048 : s[11:0];
        clip_analog = {c[11:4], c[10:4], c[10]};
    end
endfunction

task automatic chip_reset;
    integer n;
    begin
        SPEN <= 0; TALK <= 0; TALKD <= 0;
        RNG <= 13'h1FFF; ctl_buffer <= 0;
        new_e <= 0; cur_e <= 0; prev_e <= 0; new_p <= 0; cur_p <= 0;
        zpar <= 0; uv_zpar <= 0;
        for (n = 0; n < 10; n = n + 1) begin new_k[n] <= 0; cur_k[n] <= 0; u[n] <= 0; x[n] <= 0; end
        inhibit <= 1; subcycle <= 0; pitch_count <= 0; pitch_zero <= 0; PC <= 0;
        subc_reload <= 1; OLDE <= 1; OLDP <= 1; IP <= 0;
        schedule_dummy_read <= 0; next_is_address <= 0;
    end
endtask

task automatic start_speak(input slow);
    begin
        SPEN <= 1; TALK <= 1;                       // TALK at once (MAME FAST_START_HACK)
        zpar <= 1; uv_zpar <= 1; OLDE <= 1; OLDP <= 1;
        subc_reload <= ~slow;
    end
endtask

// counters after each sample (RESETF3 / RESETL4)
task automatic advance_counters(input talking);
    reg pz_now;
    begin
        pz_now = pitch_zero | (talking && subcycle + 2'd1 == 2'd2 && PC == 4'd12 && IP == 3'd7 && inhibit);
        if (subcycle + 2'd1 == 2'd2 && PC == 4'd12) begin
            if (talking && IP == 3'd7 && inhibit) pitch_zero <= 1;   // also seen by this sample's pitch counter (pz_now)
            if (IP == 3'd7) begin
                if (talking) begin OLDE <= new_silence; OLDP <= new_unvoiced; end
                TALKD <= TALK;
                if (!TALK && SPEN) TALK <= 1;
            end
            subcycle <= {1'b0, subc_reload};
            PC <= 0;
            IP <= IP + 3'd1;
        end else if (subcycle + 2'd1 == 2'd3) begin
            subcycle <= {1'b0, subc_reload};
            PC <= PC + 4'd1;
        end else
            subcycle <= subcycle + 2'd1;
        if (talking) begin
            if (({1'b0, pitch_count} + 10'd1 >= {2'b0, cur_p}) || pz_now) pitch_count <= 0;
            else pitch_count <= pitch_count + 9'd1;
        end
    end
endtask

always_ff @(posedge clk) begin
    m0 <= 0;
    pdc_d <= pdc;

    if (reset) begin
        chip_reset();
        ctl_state <= CTL_INPUT;
        st <= S_IDLE; sample_pend <= 0; cmd_pend <= 0; pdc_d <= 0;
        sample <= -16'sd1;
    end else case (st)

    S_IDLE:
        if (sample_pend) begin
            sample_pend <= 0;
            st <= S_START;
        end else if (cmd_pend) begin
            cmd_pend <= 0;
            st <= S_CMD;
        end

    //------------------------------------------------ one sample (MAME process, size 1)
    S_START:
        if (!TALKD) begin
            advance_counters(0);
            sample <= -16'sd1;
            st <= S_IDLE;
        end else if (IP == 3'd0 && PC == 4'd12 && subcycle == 2'd1) begin
            zpar <= 0; uv_zpar <= 0;
            field <= 0; nbits <= 4'd4; acc <= 0; bit_for_cmd <= 0;
            st <= S_BIT;
        end else
            st <= S_INTERP;

    S_BIT: begin
        m0 <= 1;                                   // falling M0 edge advances the VSM address, then data is read
        wait_cnt <= BIT_WAIT[3:0];
        st <= S_BITWAIT;
    end

    S_BITWAIT:
        if (wait_cnt != 0) wait_cnt <= wait_cnt - 4'd1;
        else if (bit_for_cmd) begin
            if (!discard_bit) ctl_buffer <= {data_bit, ctl_buffer[3:1]};
            st <= S_CMD_WAIT;
        end else begin
            acc <= {acc[3:0], data_bit};
            if (nbits != 4'd1) begin
                nbits <= nbits - 4'd1;
                st <= S_BIT;
            end else begin
                // field complete
                case (field)
                    4'd0: new_e <= {acc[2:0], data_bit};
                    4'd1: rep   <= data_bit;
                    4'd2: new_p <= {acc[3:0], data_bit};
                    default: new_k[field - 4'd3] <= {acc[3:0], data_bit};
                endcase
                acc <= 0;
                if ((field == 4'd0 && ({acc[2:0], data_bit} == 4'd0 || {acc[2:0], data_bit} == 4'd15)) ||
                    (field == 4'd2 && rep) || (field == 4'd6 && new_p == 5'd0) || field == 4'd12)
                    st <= S_PARSED;
                else begin
                    field <= field + 4'd1;
                    nbits <= field_bits(field + 4'd1);
                    st <= S_BIT;
                end
                if (field == 4'd2) uv_zpar <= ({acc[3:0], data_bit} == 5'd0);
            end
        end

    S_PARSED: begin
        if (new_stop) begin TALK <= 0; SPEN <= 0; end
        inhibit <= (!OLDP && new_unvoiced) || (OLDP && !new_unvoiced) || (OLDE && !new_silence);
        st <= S_EXC;
    end

    S_INTERP: begin
        if (subcycle == 2'd2) begin
            case (PC)
                4'd0: begin
                    if (IP == 3'd0) pitch_zero <= 0;
                    cur_e <= zpar ? 8'd0 : n_e[7:0];
                end
                4'd1: cur_p <= zpar ? 8'd0 : n_p[7:0];
                4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8, 4'd9, 4'd10, 4'd11:
                    cur_k[kpc] <= ((kpc < 4'd4) ? zpar : uv_zpar) ? 10'sd0 : n_k[9:0];
                default: ;
            endcase
        end
        st <= S_EXC;
    end

    S_EXC: begin
        if (OLDP) excitation <= RNG[0] ? -8'sd64 : 8'sd64;
        else      excitation <= (pitch_count >= 9'd51) ? chirp_tab(6'd51) : chirp_tab(pitch_count[5:0]);
        RNG <= rng_step20(RNG);
        lstep <= 0;
        st <= S_LAT_OP;
    end

    // lattice: step 0 = energy*excitation, 1-10 = u9..u0, 11-19 = x9..x1
    S_LAT_OP: begin
        if (lstep == 0) begin
            mm_a <= $signed({2'b00, prev_e});
            mm_b <= {{1{excitation[7]}}, excitation, 6'd0};
        end else if (lstep <= 10) begin
            mm_a <= cur_k[10 - lstep];
            mm_b <= x[10 - lstep];
        end else begin
            mm_a <= cur_k[19 - lstep];
            mm_b <= u[19 - lstep];
        end
        st <= S_LAT_ACC;
    end

    S_LAT_ACC: begin
        if (lstep == 0)
            uacc <= mm_res;
        else if (lstep <= 10) begin
            uacc <= uacc - mm_res;
            u[10 - lstep] <= uacc - mm_res;
        end else
            x[20 - lstep] <= x[19 - lstep] + mm_res;
        if (lstep == 19) st <= S_OUT;
        else begin
            lstep <= lstep + 5'd1;
            st <= S_LAT_OP;
        end
    end

    S_OUT: begin
        x[0] <= u[0];
        prev_e <= cur_e;
        sample <= clip_analog(u[0]);
        advance_counters(1);
        st <= S_IDLE;
    end

    //------------------------------------------------ PDC falling edge (MAME PDC_set)
    S_CMD: begin
        st <= S_IDLE;
        case (ctl_state)
            CTL_NEXT_TTALK:  ctl_state <= CTL_TTALK;
            CTL_TTALK:       ctl_state <= CTL_INPUT;
            CTL_NEXT_OUTPUT: ctl_state <= CTL_OUTPUT;
            CTL_OUTPUT:      ctl_state <= CTL_INPUT;
            default:
                if (next_is_address) begin
                    next_is_address <= 0;
                    schedule_dummy_read <= 1;
                end else case (cmd_ctl[3:1])
                    CMD_RESET, CMD_SPEAK, CMD_SPKSLOW:
                        if (schedule_dummy_read) begin
                            schedule_dummy_read <= 0;
                            bit_for_cmd <= 1; discard_bit <= 1;
                            st <= S_BIT;
                        end else
                            st <= S_CMD_WAIT;
                    CMD_LOAD_ADDRESS: next_is_address <= 1;
                    CMD_OUTPUT:       ctl_state <= CTL_NEXT_OUTPUT;
                    CMD_READ_BIT: begin
                        bit_for_cmd <= 1;
                        discard_bit <= schedule_dummy_read;
                        schedule_dummy_read <= 0;
                        st <= S_BIT;
                    end
                    CMD_READ_BRANCH: begin
                        schedule_dummy_read <= 0;
                        m0 <= 1;
                    end
                    CMD_TEST_TALK:    ctl_state <= CTL_NEXT_TTALK;
                endcase
        endcase
    end

    // command tail after any dummy read
    S_CMD_WAIT: begin
        st <= S_IDLE;
        bit_for_cmd <= 0;
        case (cmd_ctl[3:1])
            CMD_RESET:   chip_reset();
            CMD_SPEAK:   start_speak(0);
            CMD_SPKSLOW: start_speak(1);
            default: ;
        endcase
    end

    default: st <= S_IDLE;
    endcase

    // after the case so a request in the same clock as its clear is not lost
    if (!reset) begin
        if (ce_sample) sample_pend <= 1;
        if (pdc_d && !pdc) begin cmd_pend <= 1; cmd_ctl <= ctl; end
    end
end

endmodule
