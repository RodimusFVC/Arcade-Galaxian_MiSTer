//  Copyright (C) 2026 Rodimus

//  Space Battle sound board (Hoei / Sun SB-002U), digital part: the pitch counter (CK = 2H) and its 74393, and the
//  three NOISE latches (star LFSR N3A on 2V, 64H and 4V). The analog circuit is a dsnd_engine program
//  (tools/dsnd_galaxian.py sbhoei()), fed once per engine sample:
//    byte 0: [0] noise 3 enable (A803), [1] noise 1 enable (A000), [2] noise 2 enable (A001),
//            [3] NOISE 2V, [4] NOISE 64H, [5] NOISE 4V, [6] FIRE (A805)       byte 1: [1:0] VOL1 / VOL2
//    bytes 2 / 3 / 4: 393 QA / QC / QD high count over the sample's 32 fast ticks (1.536 MHz)

module galaxian_sbsound
(
    input               clk,                // 49.152 MHz
    input               reset,
    input               pause,
    input               sample,             // dsnd_engine sample strobe (every 1024 clocks)
    input               v2,                 // 2V (vcnt[1])
    input               v4,                 // 4V (vcnt[2])
    input               h64,                // 64H (hcnt[6])
    input               n3a,
    input         [2:0] noise_en,           // [2] A803 (noise 3), [1:0] A001 / A000 (noise 2 / 1)
    input               fire,
    input         [1:0] vol,
    input         [7:0] pitch,
    output reg   [63:0] src = 64'd0
);

reg  [4:0] c = 5'd0;
reg  [7:0] c1 = 8'hFF;
reg  [3:0] c2 = 4'd0;
reg        v2_d = 1'b0, v4_d = 1'b0, h64_d = 1'b0;
reg  [2:0] noise = 3'd0;                                           // [0] 2V, [1] 64H, [2] 4V
reg  [5:0] ca = 6'd0, cc = 6'd0, cd = 6'd0;

wire       tk      = c == 5'd31;                                   // one 1.536 MHz tick per 32 clocks
wire       pstep   = tk && pitch != 8'hFF;
wire [3:0] c2_n    = (pstep && c1 == 8'hFF) ? c2 + 4'd1 : c2;
wire [2:0] noise_n = {(tk && v4 && !v4_d) ? n3a : noise[2], (tk && h64 && !h64_d) ? n3a : noise[1],
                      (tk && v2 && !v2_d) ? n3a : noise[0]};
wire [5:0] ca_n    = ca + (tk ? {5'd0, c2_n[0]} : 6'd0);
wire [5:0] cc_n    = cc + (tk ? {5'd0, c2_n[2]} : 6'd0);
wire [5:0] cd_n    = cd + (tk ? {5'd0, c2_n[3]} : 6'd0);

always @(posedge clk) begin
    if (reset) begin
        c <= 5'd0; c1 <= 8'hFF; c2 <= 4'd0; v2_d <= 1'b0; v4_d <= 1'b0; h64_d <= 1'b0; noise <= 3'd0;
        ca <= 6'd0; cc <= 6'd0; cd <= 6'd0; src <= 64'd0;
    end
    else if (!pause) begin
        c <= c + 5'd1;
        if (tk) begin
            v2_d <= v2; v4_d <= v4; h64_d <= h64;
            if (pstep) c1 <= (c1 == 8'hFF) ? pitch : c1 + 8'd1;
        end
        c2 <= c2_n;
        noise <= noise_n;
        if (sample) begin
            src <= {24'd0, 2'd0, cd_n, 2'd0, cc_n, 2'd0, ca_n, 6'd0, vol, 1'b0, fire, noise_n[2], noise_n[1], noise_n[0],
                    noise_en[1], noise_en[0], noise_en[2]};
            ca <= 6'd0; cc <= 6'd0; cd <= 6'd0;
        end
        else begin
            ca <= ca_n; cc <= cc_n; cd <= cd_n;
        end
    end
end

endmodule
