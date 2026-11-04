//  Based on MAME sp0250.cpp (Olivier Galibert, BSD-3-Clause)

module sp0250 (
    input                clk,
    input                reset_n,

    input                ce_3_12m,
    input                ce_rom_1_56m,

    input        [7:0]   data_in,
    input                wr,

    output               drq,

    output signed [13:0] audio_out,
    output               audio_valid
);

    wire _unused_ce_3_12m = ce_3_12m;

    reg [7:0] fifo [0:14];
    reg [3:0] fifo_pos;
    assign drq = (fifo_pos != 4'd15);

    reg               voiced;
    reg signed [15:0] amp;
    reg        [14:0] lfsr;
    reg        [7:0]  pitch;
    reg        [7:0]  pcount;
    reg        [5:0]  repeat_count;
    reg        [5:0]  rcount;

    reg signed [15:0] filt_F  [0:5];
    reg signed [15:0] filt_B  [0:5];
    reg signed [15:0] filt_z1 [0:5];
    reg signed [15:0] filt_z2 [0:5];

    initial begin
        filt_F[0]  = 16'sd0; filt_F[1]  = 16'sd0; filt_F[2]  = 16'sd0;
        filt_F[3]  = 16'sd0; filt_F[4]  = 16'sd0; filt_F[5]  = 16'sd0;
        filt_B[0]  = 16'sd0; filt_B[1]  = 16'sd0; filt_B[2]  = 16'sd0;
        filt_B[3]  = 16'sd0; filt_B[4]  = 16'sd0; filt_B[5]  = 16'sd0;
        filt_z1[0] = 16'sd0; filt_z1[1] = 16'sd0; filt_z1[2] = 16'sd0;
        filt_z1[3] = 16'sd0; filt_z1[4] = 16'sd0; filt_z1[5] = 16'sd0;
        filt_z2[0] = 16'sd0; filt_z2[1] = 16'sd0; filt_z2[2] = 16'sd0;
        filt_z2[3] = 16'sd0; filt_z2[4] = 16'sd0; filt_z2[5] = 16'sd0;
    end

    reg  [7:0]         coef_addr;
    wire signed [15:0] coef_val;

    sp0250_coef_rom u_coef (
        .clk (clk),
        .idx (coef_addr),
        .val (coef_val)
    );

    reg [3:0] coef_step;
    reg [2:0] clear_idx;
    reg [3:0] coef_widx;

    always @(*) begin
        case (coef_step)
            4'd0:  coef_addr = fifo[0];
            4'd1:  coef_addr = fifo[1];
            4'd2:  coef_addr = fifo[3];
            4'd3:  coef_addr = fifo[4];
            4'd4:  coef_addr = fifo[6];
            4'd5:  coef_addr = fifo[7];
            4'd6:  coef_addr = fifo[9];
            4'd7:  coef_addr = fifo[10];
            4'd8:  coef_addr = fifo[11];
            4'd9:  coef_addr = fifo[12];
            4'd10: coef_addr = fifo[13];
            4'd11: coef_addr = fifo[14];
            default: coef_addr = 8'd0;
        endcase
    end

    wire [4:0] amp_mant  = fifo[2][4:0];
    wire [2:0] amp_shift = fifo[2][7:5];
    wire signed [15:0] ga2 = $signed({11'b0, amp_mant}) << amp_shift;

    reg [7:0] sample_divider;
    wire      sample_tick = ce_rom_1_56m && (sample_divider == 8'd0);

    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_PREP = 4'd1;
    localparam [3:0] ST_ST0  = 4'd2;
    localparam [3:0] ST_ST1  = 4'd3;
    localparam [3:0] ST_ST2  = 4'd4;
    localparam [3:0] ST_ST3  = 4'd5;
    localparam [3:0] ST_ST4  = 4'd6;
    localparam [3:0] ST_ST5  = 4'd7;
    localparam [3:0] ST_DONE      = 4'd8;
    localparam [3:0] ST_COEF_LOAD = 4'd9;
    localparam [3:0] ST_CLEAR_Z   = 4'd10;
    reg [3:0] state;

    reg signed [15:0] reg_z0;

    wire signed [15:0] z0_excite =
        voiced ? ((pcount == 8'd0) ? amp : 16'sd0)
               : (lfsr[0] ? amp : -amp);

    wire [2:0]         stage_idx = state[2:0] - 3'd2;

    reg signed [15:0] F_q, B_q, z1_q, z2_q;
    always @(posedge clk) begin
        F_q  <= filt_F [stage_idx];
        B_q  <= filt_B [stage_idx];
        z1_q <= filt_z1[stage_idx];
        z2_q <= filt_z2[stage_idx];
    end

    reg signed [31:0] mul_f32, mul_b32;
    reg signed [15:0] stage_in_r;
    reg        [1:0]  stage_sub;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mul_f32    <= 32'sd0;
            mul_b32    <= 32'sd0;
            stage_in_r <= 16'sd0;
        end else begin
            if (state == ST_ST0 || state == ST_ST1 || state == ST_ST2 ||
                state == ST_ST3 || state == ST_ST4 || state == ST_ST5) begin
                if (stage_sub == 2'd1) begin
                    mul_f32    <= z1_q * F_q;
                    mul_b32    <= z2_q * B_q;
                    stage_in_r <= (state == ST_ST0) ? z0_excite : reg_z0;
                end
            end
        end
    end

    wire signed [31:0] stage_sum32 =
        {{16{stage_in_r[15]}}, stage_in_r} + (mul_f32 >>> 8) + (mul_b32 >>> 9);

    wire signed [15:0] stage_out = stage_sum32[15:0];

    wire signed [15:0] z_sr6 = reg_z0 >>> 6;
    wire signed [6:0]  dac_clamped =
        (z_sr6 < -16'sd64) ? -8'sd64 :
        (z_sr6 >  16'sd63) ?  8'sd63 :
                              z_sr6[6:0];
    wire signed [13:0] audio_next = {dac_clamped, 7'b0};

    reg signed [13:0] audio_reg;
    reg               audio_valid_reg;
    assign audio_out   = audio_reg;
    assign audio_valid = audio_valid_reg;

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fifo_pos        <= 4'd0;
            voiced          <= 1'b0;
            amp             <= 16'sd0;
            lfsr            <= 15'h7FFF;
            pitch           <= 8'd0;
            pcount          <= 8'd0;
            repeat_count    <= 6'd0;
            rcount          <= 6'd0;
            sample_divider  <= 8'd155;
            state           <= ST_IDLE;
            coef_step       <= 4'd0;
            clear_idx       <= 3'd0;
            coef_widx       <= 4'd0;
            stage_sub       <= 2'd0;
            reg_z0          <= 16'sd0;
            audio_reg       <= 14'sd0;
            audio_valid_reg <= 1'b0;
            for (i = 0; i < 15; i = i + 1) begin
                fifo[i] <= 8'd0;
            end
        end else begin
            audio_valid_reg <= 1'b0;

            if (sample_tick)           sample_divider <= 8'd155;
            else if (ce_rom_1_56m)     sample_divider <= sample_divider - 8'd1;

            if (wr && fifo_pos != 4'd15) begin
                fifo[fifo_pos] <= data_in;
                fifo_pos       <= fifo_pos + 4'd1;
            end

            case (state)
                ST_IDLE: begin
                    if (sample_tick) state <= ST_PREP;
                end

                ST_PREP: begin
                    if (rcount >= repeat_count) begin
                        if (fifo_pos == 4'd15) begin
                            amp          <= ga2;
                            pitch        <= fifo[5];
                            repeat_count <= fifo[8][5:0];
                            voiced       <= fifo[8][6];
                            pcount       <= 8'd0;
                            rcount       <= 6'd0;
                            clear_idx    <= 3'd0;
                            state        <= ST_CLEAR_Z;
                        end else begin
                            repeat_count <= 6'd1;
                            pcount       <= 8'd0;
                            rcount       <= 6'd0;
                            lfsr         <= {lfsr[0] ^ lfsr[1], lfsr[14:1]};
                            stage_sub    <= 2'd0;
                            state        <= ST_ST0;
                        end
                    end else begin
                        lfsr      <= {lfsr[0] ^ lfsr[1], lfsr[14:1]};
                        stage_sub <= 2'd0;
                        state     <= ST_ST0;
                    end
                end

                ST_CLEAR_Z: begin
                    filt_z1[clear_idx] <= 16'sd0;
                    filt_z2[clear_idx] <= 16'sd0;
                    if (clear_idx == 3'd5) begin
                        coef_step <= 4'd0;
                        coef_widx <= 4'd0;
                        state     <= ST_COEF_LOAD;
                    end else begin
                        clear_idx <= clear_idx + 3'd1;
                    end
                end

                ST_COEF_LOAD: begin
                    coef_step <= coef_step + 4'd1;
                    if (coef_step >= 4'd2 && coef_step <= 4'd13) begin
                        if (coef_step[0])
                            filt_F[coef_widx] <= coef_val;
                        else
                            filt_B[coef_widx] <= coef_val;
                        if (coef_step[0])
                            coef_widx <= coef_widx + 4'd1;
                    end
                    if (coef_step == 4'd13) begin
                        fifo_pos  <= 4'd0;
                        lfsr      <= {lfsr[0] ^ lfsr[1], lfsr[14:1]};
                        stage_sub <= 2'd0;
                        state     <= ST_ST0;
                    end
                end

                ST_ST0, ST_ST1, ST_ST2, ST_ST3, ST_ST4, ST_ST5: begin
                    case (stage_sub)
                        2'd0: stage_sub <= 2'd1;
                        2'd1: stage_sub <= 2'd2;
                        2'd2: begin
                            reg_z0             <= stage_out;
                            filt_z2[stage_idx] <= z1_q;
                            filt_z1[stage_idx] <= stage_out;
                            stage_sub          <= 2'd0;
                            state              <= (state == ST_ST5) ? ST_DONE
                                                                    : state + 4'd1;
                        end
                    endcase
                end

                ST_DONE: begin
                    audio_reg       <= audio_next;
                    audio_valid_reg <= 1'b1;
                    if (pcount == pitch) begin
                        pcount <= 8'd0;
                        rcount <= rcount + 6'd1;
                    end else begin
                        pcount <= pcount + 8'd1;
                    end
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
