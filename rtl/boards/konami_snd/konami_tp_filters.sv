//  Copyright (C) 2026 Rodimus

//  Konami sound board channel filters: per AY channel the three Time Pilot first-order low-passes (light / medium /
//  heavy), all running at 49.152 MHz / 220 = 223.4 kHz so a filter-latch change switches without a transient.
//  One shared multiplier, same results as one 1st-order IIR per filter: every 220 clocks
//    s = B * (x0 + x1) - A2 * y        (34-bit, wraps)        y <= {s[33], s[29:15]}    x1 <= x0    x0 <= in
//  with y, x0, x1 as before the step. The three filters of a channel share x0 / x1 (same input). The 36 products
//  are formed in the clocks after a step and committed together at the next step.
//  in: channel k at [16k+15:16k]; out: filter f = 3k + t (t 0 light, 1 medium, 2 heavy) at [16f+15:16f].

module konami_tp_filters
(
    input                clk,
    input                reset,
    input        [95:0]  in,
    output       [287:0] out
);

reg  [7:0] count = 8'd0;
wire       step = count == 8'd219;

reg signed [15:0] x0[6], x1[6];
reg signed [15:0] y[18], res[18];

integer i;
initial for (i = 0; i < 6; i = i + 1) begin x0[i] = 16'sd0; x1[i] = 16'sd0; end
initial for (i = 0; i < 18; i = i + 1) begin y[i] = 16'sd0; res[i] = 16'sd0; end

// job j = 0 .. 35 issued at count j: filter f = j >> 1; even j = B * (x0 + x1), odd j = A2 * y
wire       issue = count < 8'd36;
wire [4:0] jf    = 5'(count[7:1]);
wire [2:0] jc    = 3'(jf / 5'd3);
wire [1:0] jt    = 2'(jf % 5'd3);

function signed [17:0] coef_b(input [1:0] t);
    coef_b = t == 2'd0 ? 18'sd563 : t == 2'd1 ? 18'sd174 : 18'sd135;
endfunction
function signed [17:0] coef_a2(input [1:0] t);
    coef_a2 = t == 2'd0 ? -18'sd31642 : t == 2'd1 ? -18'sd32420 : -18'sd32498;
endfunction

reg signed [17:0] ma = 18'sd0;
reg signed [16:0] mb = 17'sd0;
reg signed [34:0] p = 35'sd0;
reg signed [33:0] acc = 34'sd0;
reg  [5:0] j1 = 6'd63, j2 = 6'd63;                 // job number one / two clocks after issue (63 = none)

always @(posedge clk) begin
    if (reset) begin
        count <= 8'd0; j1 <= 6'd63; j2 <= 6'd63;
        for (i = 0; i < 6; i = i + 1) begin x0[i] <= 16'sd0; x1[i] <= 16'sd0; end
        for (i = 0; i < 18; i = i + 1) y[i] <= 16'sd0;
    end
    else begin
        count <= step ? 8'd0 : count + 8'd1;
        // issue
        if (issue) begin
            ma <= count[0] ? coef_a2(jt) : coef_b(jt);
            mb <= count[0] ? 17'(y[jf]) : 17'(x0[jc]) + 17'(x1[jc]);
        end
        j1 <= issue ? count[5:0] : 6'd63;
        // multiply
        p  <= ma * mb;
        j2 <= j1;
        // accumulate / finish
        if (j2 != 6'd63) begin
            if (!j2[0]) acc <= 34'(p);
            else begin : fin
                reg signed [33:0] s;
                s = acc - 34'(p);
                res[j2[5:1]] <= {s[33], s[29:15]};
            end
        end
        // commit
        if (step) begin
            for (i = 0; i < 18; i = i + 1) y[i] <= res[i];
            for (i = 0; i < 6; i = i + 1) begin x1[i] <= x0[i]; x0[i] <= in[16 * i +: 16]; end
        end
    end
end

genvar g;
generate for (g = 0; g < 18; g = g + 1) begin : o
    assign out[16 * g +: 16] = y[g];
end endgenerate

endmodule
