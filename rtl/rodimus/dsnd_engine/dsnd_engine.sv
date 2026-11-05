//============================================================================
//
//  Discrete sound engine: one small fixed-point processor that runs a per-game circuit program (MRA index 5,
//  assembled by RodimusCoresMaster_MiSTer/tools/dsnd.py) once per sample, so each discrete sound board costs a
//  program, not logic. TICK = clocks per sample (at least 832); out_r / sample are optional (unconnected for mono).
//  How it works: README.md of this chip folder.
//  Copyright (C) 2026 Rodimus
//
//  SPDX-License-Identifier: BSD-3-Clause
//  Own work; license terms in the LICENSE file of this chip folder.
//
//============================================================================

// Instruction (64 bits, little endian in the MRA; up to 1024): [63:56] op, [55:48] a, [47:40] b, [31:0] imm. Values are Q24
// (1.0 = 1 << 24), the accumulator and the 256-word state memory M are 32 bits and wrap. 2 clocks per instruction,
// at most 410 instructions per sample (up to 824 clocks); the sample ends at END. Output = mix >> 9, saturated
// (1.0 = full scale). Bit-exact with verify/dsnd_model.h.
//   0 END              1 LD a: acc = M[a]          2 LDI: acc = imm            3 ADD a: acc += M[a]
//   4 SUB a: acc -= M[a]  5 ADDI: acc += imm       6 MULI: acc = acc * imm >> 24   7 MUL a: acc = acc * M[a] >> 24
//   8 ST a: M[a] = acc  9 STF a: if F           10 LDIF: if F acc = imm
//  11 RC a: M[a] += (acc - M[a]) * imm >> 24, acc = M[a]   12 RCM a, b: the same with the coefficient M[b]
//  13 CMP a: F = acc >= M[a]   14 CMPI: F = acc >= imm   15 MAXI   16 MINI
//  17 BIT b: F = source bit (a[0] inverts)   18 NOT: F = !F   19 NOISE b: step LFSR b[1:0], F = its new bit
//     (b[2] = SN76477 lock-up guard: the new bit is 1 while bits 28 and 4:0 are all 0)
//  20 OUT: mix += acc   21 LDF a: if F acc = M[a]   22 SKF: if F skip imm   23 SKNF: if !F skip imm
//  24 LDL b: acc = source byte << 16   25 ABS   26 FAND b: F &= bit   27 FOR b: F |= bit   28 STNF a: if !F
//  29 LDLM b: acc = (source byte & imm[7:0]) << imm[12:8]   30 MACI a: acc += M[a] * imm >> 24
//  33 OUTR: mix_r += acc (out_r = mix_r if any OUTR ran in the sample, else out)
//  31 EXP: acc = 2^acc (degree-5 polynomial in Q28 on the fraction, then a shift; >= 7.0 -> 7FFFFFFF, < -24.0 -> 0)
//  32 RCP: acc = 1 / acc (normalise, linear seed, 3 Newton-Raphson steps in Q24; 0 -> 7FFFFFFF, saturated)
// Budget units: 1 per instruction, EXP 4 (8 clocks), RCP 5 (10 clocks); a sample stops after the instruction that
// reaches 410 units.
// Sources (b[5:3]): 0-5 board sources (the core's tools/dsnd_boards.py), 6 / 7 Game Audio settings; b[2:0] = bit.

module dsnd_engine #(parameter int TICK = 832)
(
    input  logic        clk,            // TICK x sample rate (Exidy 22.578 MHz / 832; Phoenix 44 MHz / 917)
    input  logic        reset,
    input  logic        pause,
    input  logic        prog_wr,        // MRA index 5 byte
    input  logic [12:0] prog_addr,
    input  logic  [7:0] prog_data,
    input  logic [63:0] src,            // sources 7..0, one byte each
    output logic signed [15:0] out,
    output logic signed [15:0] out_r,
    output logic        sample          // one clk at the start of each sample period (sources are read after it)
);

// Two clocks per instruction: E1 reads M[a] / M[b] (addressed from the program word in the previous E2), registers
// the multiplier operands and starts the next program fetch; E2 multiplies, writes back and addresses the next M
// reads. A write in E2 lands on the same edge as the next instruction's M read, so that read is forwarded.
typedef enum logic [2:0] { S_IDLE, S_LOAD, S_E1, S_E2, S_PUB, S_CLR, S_X } state_t;
state_t st = S_CLR;

logic  [9:0] pc = 10'd0, pa;
logic [63:0] pq;
dpram_dc #(.widthad_a(10), .width_a(64)) u_prog
(
    .clock_a(clk),
    .address_a(prog_wr ? prog_addr[12:3] : pa),
    .data_a({8{prog_data}}),
    .wren_a(prog_wr),
    .byteena_a(8'd1 << prog_addr[2:0]),
    .q_a(pq),

    .clock_b(clk),
    .address_b(10'd0),
    .data_b(64'd0),
    .wren_b(1'b0),
    .byteena_b(8'hFF),
    .q_b()
);

// state memory, two copies (read M[a] / M[b]) sharing the write port
logic  [7:0] wa;
logic [31:0] wd;
logic        we;
logic [31:0] mqa, mqb;
wire   [7:0] ra = pq[55:48], rb = pq[47:40];
dpram_dc #(.widthad_a(8), .width_a(32)) u_ma
(
    .clock_a(clk), .address_a(ra), .data_a(32'd0), .wren_a(1'b0), .byteena_a(4'hF), .q_a(mqa),
    .clock_b(clk), .address_b(wa), .data_b(wd),    .wren_b(we),    .byteena_b(4'hF), .q_b()
);
dpram_dc #(.widthad_a(8), .width_a(32)) u_mb
(
    .clock_a(clk), .address_a(rb), .data_a(32'd0), .wren_a(1'b0), .byteena_a(4'hF), .q_a(mqb),
    .clock_b(clk), .address_b(wa), .data_b(wd),    .wren_b(we),    .byteena_b(4'hF), .q_b()
);

// sample timing
logic [9:0] tick = 10'd0;
wire        go = tick == 10'(TICK - 1);
always_ff @(posedge clk) if (reset) tick <= 10'd0; else if (!pause) tick <= go ? 10'd0 : tick + 10'd1;
assign sample = go & ~pause;

logic [63:0] ir = 64'd0;
logic signed [31:0] acc = 32'sd0, mix = 32'sd0, mix_r = 32'sd0;
logic        used_r = 1'b0;
logic        f = 1'b0;
logic [30:0] lfsr[4] = '{31'd1, 31'd1, 31'd1, 31'd1};
logic  [8:0] icnt = 9'd0;
logic signed [32:0] mul_a = 33'sd0;
logic signed [31:0] mul_b = 32'sd0;
logic signed [31:0] ma_r = 32'sd0;              // M[a] as E1 saw it
logic        fwd_a = 1'b0, fwd_b = 1'b0;
logic [31:0] fwd_d = 32'd0;
logic  [7:0] clr = 8'd0;

wire  [7:0] op  = ir[63:56];
wire  [7:0] fa  = ir[55:48];
wire  [7:0] fb  = ir[47:40];
wire signed [31:0] imm = ir[31:0];
wire signed [31:0] m_a = fwd_a ? fwd_d : mqa;   // E1: M[a] / M[b] with the previous write forwarded
wire signed [31:0] m_b = fwd_b ? fwd_d : mqb;
wire  [2:0] ssel = fb[5:3];
wire  [7:0] sbyte = src[ssel*8 +: 8];
wire        sbit = sbyte[fb[2:0]] ^ fa[0];
wire signed [64:0] prod  = mul_a * mul_b;
wire signed [31:0] mul_q = 32'(prod >>> 24);

// EXP / RCP micro-sequence (S_X), on the same multiplier
localparam logic signed [31:0] EXP_C0 = 32'sd268435436, EXP_C1 = 32'sd186066863, EXP_C2 = 32'sd64465738,
                               EXP_C3 = 32'sd14985772,  EXP_C4 = 32'sd2413057,   EXP_C5 = 32'sd504005;     // Q28
localparam logic signed [31:0] RCP_K48 = 32'sd47370962, RCP_K32 = -32'sd31580641;                         // 48/17, -32/17
logic  [3:0] xk = 4'd0;
logic        xbig = 1'b0, xsmall = 1'b0, xneg = 1'b0;
logic signed [7:0]  xsh = 8'sd0;
logic signed [32:0] xp = 33'sd0;                 // EXP: polynomial value (Q28); RCP: Newton estimate Y (Q24)
logic signed [31:0] xd = 32'sd0;                 // RCP: normalised divisor D (Q24, 0.5 .. 1)
logic signed [31:0] xres = 32'sd0;
wire  [7:0]  cost = op == 8'd31 ? 8'd4 : op == 8'd32 ? 8'd5 : 8'd1;
function automatic [4:0] lzc32(input [31:0] v);
    lzc32 = 5'd0;
    for (int i = 0; i < 32; i++) if (v[i]) lzc32 = 5'(31 - i);
endfunction
wire [31:0] rcp_m0 = acc[31] ? 32'(-acc) : acc;
wire  [4:0] rcp_z  = lzc32(rcp_m0);
wire [31:0] rcp_mn = rcp_m0 << rcp_z;
wire signed [63:0] xshl = 64'(xp) <<< xsh;       // final shifts
wire signed [32:0] xshr = xp >>> (-xsh);
wire signed [31:0] xl32 = 32'(xshl), xr32 = 32'(xshr);   // (Quartus 17: no unary minus on a size cast)

function automatic logic signed [15:0] sat16(input logic signed [31:0] m);
    sat16 = (m >>> 9) > 32'sd32767 ? 16'sd32767 : (m >>> 9) < -32'sd32768 ? -16'sd32768 : 16'(m >>> 9);
endfunction

// E2 results
logic signed [31:0] acc_n, wd_n;
logic        f_n, we_n;
always_comb begin
    acc_n = acc; f_n = f; we_n = 1'b0; wd_n = acc;
    case (op)
        8'd1:  acc_n = ma_r;
        8'd2:  acc_n = imm;
        8'd3:  acc_n = acc + ma_r;
        8'd4:  acc_n = acc - ma_r;
        8'd5:  acc_n = acc + imm;
        8'd6, 8'd7: acc_n = mul_q;
        8'd30: acc_n = acc + mul_q;
        8'd8:  we_n = 1'b1;
        8'd9:  we_n = f;
        8'd28: we_n = ~f;
        8'd10: if (f) acc_n = imm;
        8'd11, 8'd12: begin acc_n = ma_r + mul_q; wd_n = ma_r + mul_q; we_n = 1'b1; end
        8'd13: f_n = acc >= ma_r;
        8'd14: f_n = acc >= imm;
        8'd15: if (acc < imm) acc_n = imm;
        8'd16: if (acc > imm) acc_n = imm;
        8'd17: f_n = sbit;
        8'd18: f_n = ~f;
        8'd21: if (f) acc_n = ma_r;
        8'd24: acc_n = {8'd0, sbyte, 16'd0};
        8'd29: acc_n = {24'd0, sbyte & imm[7:0]} << imm[12:8];
        8'd25: if (acc < 0) acc_n = -acc;
        8'd26: f_n = f & sbit;
        8'd27: f_n = f | sbit;
        8'd31, 8'd32: acc_n = xres;
        default: ;
    endcase
end

// program address: the next instruction is fetched in E1 (skips decided by F, which is settled by then)
wire [9:0] pc_next = pc + 10'd1 + (((op == 8'd22 && f) || (op == 8'd23 && !f)) ? 10'(imm) : 10'd0);
assign pa = (st == S_E1) ? pc_next : pc;

// writes: E2 results, or clearing after reset
assign wa = (st == S_CLR) ? clr : fa;
assign wd = (st == S_CLR) ? 32'd0 : wd_n;
assign we = (st == S_CLR) | (st == S_E2 & we_n);

always_ff @(posedge clk) begin
    if (reset) begin
        st  <= S_CLR;
        clr <= 8'd0;
        out <= 16'sd0;
        out_r <= 16'sd0;
    end else case (st)
        S_CLR: begin                                    // clear the state memory after reset
            clr <= clr + 8'd1;
            if (clr == 8'd255) st <= S_IDLE;
        end
        S_IDLE: if (go) begin
            pc   <= 10'd0;
            mix  <= 32'sd0;
            mix_r <= 32'sd0;
            used_r <= 1'b0;
            icnt <= 9'd0;
            st   <= S_LOAD;
        end
        S_LOAD: begin                                   // program word 0 being read (pa = pc = 0)
            ir    <= 64'd0;
            fwd_a <= 1'b0;
            fwd_b <= 1'b0;
            st    <= S_E2;                              // a NOP E2 addresses the first instruction's M reads
            icnt  <= 9'd0;
        end
        S_E1: begin
            ma_r <= m_a;
            case (op)
                8'd6:  begin mul_a <= 33'(acc); mul_b <= imm; end
                8'd7:  begin mul_a <= 33'(acc); mul_b <= m_a; end
                8'd30: begin mul_a <= 33'(m_a); mul_b <= imm; end
                8'd11: begin mul_a <= 33'(acc) - 33'(m_a); mul_b <= imm; end
                8'd12: begin mul_a <= 33'(acc) - 33'(m_a); mul_b <= m_b; end
                8'd31: begin                            // EXP: Horner on the fraction, shift by the integer part - 4
                    mul_a <= 33'(EXP_C5); mul_b <= {8'd0, acc[23:0]};
                    xsh <= acc[31:24] - 8'sd4;
                    xbig <= acc >= 32'sh07000000; xsmall <= acc < -32'sh18000000;
                end
                8'd32: begin                            // RCP: D = |acc| normalised to 0.5 .. 1, seed 48/17 - 32/17 D
                    mul_a <= 33'(rcp_mn[31:8]); mul_b <= RCP_K32; xd <= 32'(rcp_mn[31:8]);
                    xsh <= 8'(rcp_z) - 8'sd8; xneg <= acc[31]; xbig <= acc == 32'sd0;
                end
                default: ;
            endcase
            xk <= 4'd0;
            pc <= pc_next;
            st <= (op == 8'd31 || op == 8'd32) ? S_X : S_E2;
        end
        S_X: begin
            xk <= xk + 4'd1;
            if (op == 8'd31) begin
                case (xk)
                    4'd0: begin xp <= 33'(EXP_C4 + mul_q); mul_a <= 33'(EXP_C4 + mul_q); end
                    4'd1: begin xp <= 33'(EXP_C3 + mul_q); mul_a <= 33'(EXP_C3 + mul_q); end
                    4'd2: begin xp <= 33'(EXP_C2 + mul_q); mul_a <= 33'(EXP_C2 + mul_q); end
                    4'd3: begin xp <= 33'(EXP_C1 + mul_q); mul_a <= 33'(EXP_C1 + mul_q); end
                    4'd4: xp <= 33'(EXP_C0 + mul_q);
                    default: begin                     // 2^ip x p (Q28 -> Q24: shift ip - 4)
                        xres <= xbig ? 32'sh7FFFFFFF : xsmall ? 32'sd0 : (xsh >= 0) ? xl32 : xr32;
                        st <= S_E2;
                    end
                endcase
            end else begin
                case (xk)
                    4'd0, 4'd2, 4'd4: begin            // Y (seed, or Y x (2 - e)) -> e = D x Y next
                        xp <= 33'((xk == 4'd0 ? RCP_K48 : 32'sd0) + mul_q);
                        mul_a <= 33'(xd); mul_b <= (xk == 4'd0 ? RCP_K48 : 32'sd0) + mul_q;
                    end
                    4'd1, 4'd3, 4'd5: begin            // e -> Y x (2 - e)
                        mul_a <= xp; mul_b <= 32'sh02000000 - mul_q;
                    end
                    4'd6: xp <= 33'(mul_q);
                    default: begin
                        if (xbig) xres <= 32'sh7FFFFFFF;
                        else if (xsh >= 0)
                            xres <= (xshl > 64'sh7FFFFFFF) ? (xneg ? -32'sh7FFFFFFF : 32'sh7FFFFFFF)
                                                          : (xneg ? -xl32 : xl32);
                        else xres <= xneg ? -xr32 : xr32;
                        st <= S_E2;
                    end
                endcase
            end
        end
        S_E2: begin
            acc <= acc_n;
            f   <= f_n;
            if (op == 8'd19) begin : noise
                logic nb;
                nb = lfsr[fb[1:0]][28] ^ lfsr[fb[1:0]][0];      // SN76477 / discrete 31-bit noise taps
                if (fb[2] && lfsr[fb[1:0]][28] == 1'b0 && lfsr[fb[1:0]][4:0] == 5'd0) nb = 1'b1;   // SN76477 lock-up guard
                lfsr[fb[1:0]] <= {nb, lfsr[fb[1:0]][30:1]};
                f <= nb;
            end
            if (op == 8'd20) mix <= mix + acc;
            if (op == 8'd33) begin mix_r <= mix_r + acc; used_r <= 1'b1; end
            // the next instruction: its word is on pq now; its M reads are addressed this edge
            ir    <= pq;
            fwd_a <= we_n && pq[55:48] == fa && icnt != 9'd0;
            fwd_b <= we_n && pq[47:40] == fa && icnt != 9'd0;
            fwd_d <= wd_n;
            icnt  <= icnt + 9'(cost);
            st    <= S_E1;
            if (icnt != 9'd0 && (op == 8'd0 || icnt + 9'(cost) - 9'd1 >= 9'd410)) st <= S_PUB;   // END, or the 410-unit budget
        end
        S_PUB: begin                                    // publish the sample (1.0 = full scale)
            out <= sat16(mix);
            out_r <= sat16(used_r ? mix_r : mix);
            st  <= S_IDLE;
        end
        default: st <= S_IDLE;
    endcase
end

endmodule
