//============================================================================
//
//  i8255.sv — Intel 8255 PPI (modes 0, 1 and 2, port C bit set / reset)
//  Copyright (C) 2026 Rodimus
//  SPDX-License-Identifier: BSD-3-Clause
//  Ported from MAME src/devices/machine/i8255.cpp (license:BSD-3-Clause, copyright-holders: Curt Coder)
//
//  Ported from MAME devices/machine/i8255.cpp (i8255_device). Each MAME call is one clocked event here: set_mode,
//  set_pc_bit, write_mode0/1/2, the read side effects of read_mode1 / read_mode2 (IBF, INTR and the input latch
//  cleared at the END of the read cycle, so the CPU samples the latched byte), and the handshake pins pc2_w (port B
//  STB / ACK), pc4_w (port A STB), pc6_w (port A ACK), which act on a falling edge (held pending until a clock
//  without a bus event, so an edge that meets a CPU access is not lost). Port C pins are MAME output_pc,
//  the port C read is read_pc. Port A / B pins hold the last value MAME's out_pa / out_pb callbacks were given;
//  an input port drives the TRI_* level (MAME tri_pX_callback: what the board sees from the floating TTL inputs).
//  Reset = set_mode(9B) as MAME device_reset. MAME quirk kept: setting a mode with port A output sets IBF A.
//
//============================================================================

module i8255 #(
    parameter [7:0] TRI_PA = 8'hFF,
    parameter [7:0] TRI_PB = 8'hFF,
    parameter [7:0] TRI_PC = 8'hFF
)(
    input             clk,
    input             reset,

    input             cs,
    input             rd,             // read cycle (level)
    input             wr,             // one clock per write cycle
    input       [1:0] a,
    input       [7:0] din,
    output reg  [7:0] dout,

    input       [7:0] pa_in,
    input       [7:0] pb_in,
    input       [7:0] pc_in,
    input             stb_a_n,        // PC4 (port A strobe, modes 1 in / 2)
    input             ack_a_n,        // PC6 (port A acknowledge, modes 1 out / 2)
    input             pc2_n,          // PC2 (port B strobe / acknowledge, mode 1)
    output reg  [7:0] pa_out = 8'hFF,
    output reg  [7:0] pb_out = 8'hFF,
    output reg  [7:0] pc_out
);

    reg  [7:0] ctrl = 8'h9B;
    reg  [7:0] out_a = 8'h00, out_b = 8'h00, out_c = 8'h00, in_a = 8'h00, in_b = 8'h00;
    reg        ibf_a = 1'b0, ibf_b = 1'b0, obf_a = 1'b1, obf_b = 1'b1;
    reg        inte_a = 1'b0, inte_b = 1'b0, inte1 = 1'b0, inte2 = 1'b0, intr_a = 1'b0, intr_b = 1'b0;

    // MAME group_mode / port_mode / port_c_*_mode
    wire [1:0] gm_a  = (ctrl[6:5] == 2'd0) ? 2'd0 : (ctrl[6:5] == 2'd1) ? 2'd1 : 2'd2;
    wire       gm_b  = ctrl[2];
    wire       a_in  = ctrl[4];
    wire       b_in  = ctrl[1];
    wire       cu_in = ctrl[3];
    wire       cl_in = ctrl[0];

    // ------------------------------------------------------------ port C pins (output_pc) and read (read_pc)
    always_comb begin : pc_pins
        reg [7:0] d, m, bm;
        d = 8'h00; m = 8'h00; bm = 8'h0F;
        case (gm_a)
            2'd0: if (!cu_in) m = m | 8'hF0; else d = d | (TRI_PC & 8'hF0);
            2'd1: begin
                d = d | {4'd0, intr_a, 3'd0};
                if (!a_in) begin d = d | {obf_a, 7'd0}; m = m | 8'h30; end
                else       begin d = d | {2'd0, ibf_a, 5'd0}; m = m | 8'hC0; end
            end
            default: begin
                bm = 8'h07;
                d = d | {obf_a, 1'b0, ibf_a, 1'b0, intr_a, 3'd0};
            end
        endcase
        if (!gm_b) begin
            if (!cl_in) m = m | bm; else d = d | (TRI_PC & bm);
        end
        else d = d | {6'd0, b_in ? ibf_b : obf_b, intr_b};
        pc_out = d | (out_c & m);
    end

    reg [7:0] pc_rd;
    always_comb begin : pc_read
        reg [7:0] d, m, bm;
        d = 8'h00; m = 8'h00; bm = 8'h0F;
        case (gm_a)
            2'd0: if (!cu_in) d = d | (out_c & 8'hF0); else m = m | 8'hF0;
            2'd1: begin
                d = d | {4'd0, intr_a, 3'd0};
                if (!a_in) begin d = d | {obf_a, inte_a, 6'd0}; m = m | 8'h30; end
                else       begin d = d | {2'd0, ibf_a, inte_a, 4'd0}; m = m | 8'hC0; end
                if (!cu_in) begin d = d | (out_c & m); m = 8'h00; end
            end
            default: begin
                bm = 8'h07;
                d = d | {obf_a, inte1, ibf_a, inte2, intr_a, 3'd0};
            end
        endcase
        if (!gm_b) begin
            if (!cl_in) d = d | (out_c & bm); else m = m | bm;
        end
        else d = d | {5'd0, inte_b, b_in ? ibf_b : obf_b, intr_b};
        pc_rd = d | (pc_in & m);
    end

    // ------------------------------------------------------------ read data (read)
    always_comb begin
        case (a)
            2'd0:    dout = (gm_a == 2'd0) ? (a_in ? pa_in : out_a) : (gm_a == 2'd1 && !a_in) ? out_a : in_a;
            2'd1:    dout = !gm_b ? (b_in ? pb_in : out_b) : (!b_in ? out_b : in_b);
            2'd2:    dout = pc_rd;
            default: dout = ctrl;
        endcase
    end

    // MAME check_interrupt (mode 1: INTE && IBF / OBF; mode 2: INTE1 && OBF || INTE2 && IBF; mode 0: unchanged)
    function automatic logic int_a(input logic [1:0] g, input logic ain, input logic ie, input logic ie1,
                                   input logic ie2, input logic ib, input logic ob, input logic cur);
        int_a = (g == 2'd1) ? (ain ? (ie && ib) : (ie && ob)) : (g == 2'd2) ? ((ie1 && ob) || (ie2 && ib)) : cur;
    endfunction
    function automatic logic int_b(input logic g, input logic bin, input logic ie, input logic ib, input logic ob,
                                   input logic cur);
        int_b = g ? (bin ? (ie && ib) : (ie && ob)) : cur;
    endfunction

    // ------------------------------------------------------------ events
    reg       rd_q = 1'b0;
    reg [1:0] a_q = 2'd0;
    reg       stb_a_d = 1'b1, ack_a_d = 1'b1, pc2_d = 1'b1;
    reg       ack_p = 1'b0, stb_p = 1'b0, pc2_p = 1'b0;    // handshake edge seen, handled on a clock with no bus event
    wire      rd_end = rd_q && !(cs && rd);
    wire      bus_ev = (cs && wr) || rd_end;

    always @(posedge clk) begin
        rd_q <= cs && rd;
        if (cs && rd) a_q <= a;
        stb_a_d <= stb_a_n; ack_a_d <= ack_a_n; pc2_d <= pc2_n;
        if (!bus_ev) begin                                  // the pending edge handled below this clock
            if (ack_p) ack_p <= 1'b0;
            else if (stb_p) stb_p <= 1'b0;
            else if (pc2_p) pc2_p <= 1'b0;
        end
        if (ack_a_d && !ack_a_n) ack_p <= 1'b1;            // after the clear: a new edge always wins
        if (stb_a_d && !stb_a_n) stb_p <= 1'b1;
        if (pc2_d && !pc2_n) pc2_p <= 1'b1;

        if (reset) begin
            // set_mode(9B): every port an input
            ctrl <= 8'h9B;
            out_a <= 8'h00; in_a <= 8'h00; ibf_a <= 1'b0; obf_a <= 1'b1; inte_a <= 1'b0; inte1 <= 1'b0; inte2 <= 1'b0;
            out_b <= 8'h00; in_b <= 8'h00; ibf_b <= 1'b0; obf_b <= 1'b1; inte_b <= 1'b0;
            out_c <= 8'h00;
            intr_a <= 1'b0; intr_b <= 1'b0;
            pa_out <= TRI_PA; pb_out <= TRI_PB;
            ack_p <= 1'b0; stb_p <= 1'b0; pc2_p <= 1'b0;
        end
        else begin
            if (cs && wr) begin
                case (a)
                    2'd0: begin                                             // write_mode0 / 1 / 2
                        if (gm_a == 2'd2 || !a_in) begin
                            out_a <= din; pa_out <= din;
                            if (gm_a != 2'd0) begin obf_a <= 1'b0; intr_a <= 1'b0; end
                        end
                    end
                    2'd1: begin
                        if (!b_in) begin
                            out_b <= din; pb_out <= din;
                            if (gm_b) begin obf_b <= 1'b0; intr_b <= 1'b0; end
                        end
                    end
                    2'd2: out_c <= din;
                    default: begin
                        if (din[7]) begin                                   // set_mode
                            ctrl <= din;
                            out_a <= 8'h00; in_a <= 8'h00; obf_a <= 1'b1; inte_a <= 1'b0; inte1 <= 1'b0; inte2 <= 1'b0;
                            ibf_a <= !din[4];                               // MAME: "correct?" (SAM Coupe sampler)
                            pa_out <= din[4] ? TRI_PA : 8'h00;
                            out_b <= 8'h00; in_b <= 8'h00; ibf_b <= 1'b0; obf_b <= 1'b1; inte_b <= 1'b0;
                            pb_out <= din[1] ? TRI_PB : 8'h00;
                            out_c <= 8'h00;
                        end
                        else begin : set_pc_bit                             // set_pc_bit
                            reg [7:0] c;
                            reg       s, ia, ib, oa, ob, ea, eb, e1, e2, ra, rb;
                            s = din[0];
                            c = out_c; c[din[3:1]] = s;
                            ia = ibf_a; oa = obf_a; ea = inte_a; e1 = inte1; e2 = inte2; ra = intr_a;
                            ib = ibf_b; ob = obf_b; eb = inte_b; rb = intr_b;
                            case (gm_a)
                                2'd1: if (!a_in) case (din[3:1])
                                          3'd3: ra = s;
                                          3'd6: begin ea = s; ra = int_a(gm_a, a_in, ea, e1, e2, ia, oa, ra); end
                                          3'd7: begin oa = s; ra = int_a(gm_a, a_in, ea, e1, e2, ia, oa, ra); end
                                          default: ;
                                      endcase
                                      else case (din[3:1])
                                          3'd3: ra = s;
                                          3'd4: begin ea = s; ra = int_a(gm_a, a_in, ea, e1, e2, ia, oa, ra); end
                                          3'd5: begin ia = s; ra = int_a(gm_a, a_in, ea, e1, e2, ia, oa, ra); end
                                          default: ;
                                      endcase
                                2'd2: case (din[3:1])
                                          3'd3: ra = s;
                                          3'd4: begin e2 = s; ra = int_a(gm_a, a_in, ea, e1, e2, ia, oa, ra); end
                                          3'd5: begin ia = s; ra = int_a(gm_a, a_in, ea, e1, e2, ia, oa, ra); end
                                          3'd6: begin e1 = s; ra = int_a(gm_a, a_in, ea, e1, e2, ia, oa, ra); end
                                          3'd7: begin oa = s; ra = int_a(gm_a, a_in, ea, e1, e2, ia, oa, ra); end
                                          default: ;
                                      endcase
                                default: ;
                            endcase
                            if (gm_b) case (din[3:1])
                                3'd0: rb = s;
                                3'd1: begin if (!b_in) ob = s; else ib = s; rb = int_b(gm_b, b_in, eb, ib, ob, rb); end
                                3'd2: begin eb = s; rb = int_b(gm_b, b_in, eb, ib, ob, rb); end
                                default: ;
                            endcase
                            out_c <= c;
                            ibf_a <= ia; obf_a <= oa; inte_a <= ea; inte1 <= e1; inte2 <= e2; intr_a <= ra;
                            ibf_b <= ib; obf_b <= ob; inte_b <= eb; intr_b <= rb;
                        end
                    end
                endcase
            end
            // read_mode1 (input) / read_mode2: clear IBF, INTR and the input latch once the CPU has taken the byte
            else if (rd_end) begin
                if (a_q == 2'd0 && (gm_a == 2'd2 || (gm_a == 2'd1 && a_in))) begin
                    ibf_a <= 1'b0; intr_a <= 1'b0; in_a <= 8'h00;
                end
                if (a_q == 2'd1 && gm_b && b_in) begin
                    ibf_b <= 1'b0; intr_b <= 1'b0; in_b <= 8'h00;
                end
            end
            // pc6_w: port A acknowledge (mode 2, or mode 1 output) sets OBF again
            else if (ack_p) begin
                if ((gm_a == 2'd2 || (gm_a == 2'd1 && !a_in)) && !obf_a) obf_a <= 1'b1;
                if ((gm_a == 2'd2 || (gm_a == 2'd1 && !a_in)) && !obf_a)
                    intr_a <= int_a(gm_a, a_in, inte_a, inte1, inte2, ibf_a, 1'b1, intr_a);
            end
            // pc4_w: port A strobe (mode 2, or mode 1 input) latches the port
            else if (stb_p) begin
                if (gm_a == 2'd2 || (gm_a == 2'd1 && a_in)) begin
                    in_a <= pa_in; ibf_a <= 1'b1;
                    intr_a <= int_a(gm_a, a_in, inte_a, inte1, inte2, 1'b1, obf_a, intr_a);
                end
            end
            // pc2_w: port B (mode 1) acknowledge / strobe
            else if (pc2_p && gm_b) begin
                if (!b_in) begin
                    if (!obf_b) begin obf_b <= 1'b1; intr_b <= int_b(gm_b, b_in, inte_b, ibf_b, 1'b1, intr_b); end
                end
                else begin
                    in_b <= pb_in; ibf_b <= 1'b1; intr_b <= int_b(gm_b, b_in, inte_b, 1'b1, obf_b, intr_b);
                end
            end
        end
    end

endmodule
