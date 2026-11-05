//  Copyright (C) 2026 Rodimus

//  Galaxian / Moon Cresta sound, digital part (Galaxian.pdf p. 26-27): the 9J / 9K / 8K pitch counter (CK = 2H) and
//  6T 74393, and the NOISE latch (2D 7474, star LFSR N3A on 2V). The analog circuit is a dsnd_engine program
//  (tools/dsnd_galaxian.py), fed once per engine sample:
//    byte 0: [3:0] LFO latch, [6:4] FS1-FS3, [7] HIT     byte 1: [0] FIRE, [2:1] VOL1 / VOL2, [3] NOISE
//    bytes 2 / 3 / 4: 393 QA / QC / QD high count over the sample's 32 fast ticks (1.536 MHz)

module galaxian_sound
(
    input               clk,                // 49.152 MHz
    input               reset,
    input               pdiv8,              // pitch clock / 8 (Bongo)
    input               pause,
    input               sample,             // dsnd_engine sample strobe (every 1024 clocks)
    input               v2,                 // 2V (vcnt[1])
    input               n3a,
    input         [3:0] lfo,
    input         [2:0] fs,
    input               hit,
    input               fire,
    input         [1:0] vol,
    input         [7:0] pitch,
    output reg   [63:0] src = 64'd0
);

reg  [4:0] c = 5'd0, ft = 5'd0;
reg  [7:0] c1 = 8'hFF;
reg  [3:0] c2 = 4'd0;
reg        v2_d = 1'b0, noise = 1'b0;
reg  [5:0] ca = 6'd0, cc = 6'd0, cd = 6'd0;

wire       tk      = c == 5'd31;                                   // one 1.536 MHz tick per 32 clocks
wire       pstep   = tk && pitch != 8'hFF && (~pdiv8 || ft[2:0] == 3'd0);
wire [3:0] c2_n    = (pstep && c1 == 8'hFF) ? c2 + 4'd1 : c2;
wire       noise_n = (tk && v2 && !v2_d) ? n3a : noise;
wire [5:0] ca_n    = ca + (tk ? {5'd0, c2_n[0]} : 6'd0);
wire [5:0] cc_n    = cc + (tk ? {5'd0, c2_n[2]} : 6'd0);
wire [5:0] cd_n    = cd + (tk ? {5'd0, c2_n[3]} : 6'd0);

always @(posedge clk) begin
    if (reset) begin
        c <= 5'd0; ft <= 5'd0; c1 <= 8'hFF; c2 <= 4'd0; v2_d <= 1'b0; noise <= 1'b0;
        ca <= 6'd0; cc <= 6'd0; cd <= 6'd0; src <= 64'd0;
    end
    else if (!pause) begin
        c <= c + 5'd1;
        if (tk) begin
            ft <= ft + 5'd1;
            v2_d <= v2;
            if (pstep) c1 <= (c1 == 8'hFF) ? pitch : c1 + 8'd1;
        end
        c2 <= c2_n;
        noise <= noise_n;
        if (sample) begin
            src <= {24'd0, 2'd0, cd_n, 2'd0, cc_n, 2'd0, ca_n, 4'd0, noise_n, vol, fire, hit, fs, lfo};
            ca <= 6'd0; cc <= 6'd0; cd <= 6'd0;
        end
        else begin
            ca <= ca_n; cc <= cc_n; cd <= cd_n;
        end
    end
end

endmodule
