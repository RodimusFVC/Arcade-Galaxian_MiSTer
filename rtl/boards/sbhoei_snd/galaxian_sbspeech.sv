//  Based on MAME galaxian.cpp (Aaron Giles, Couriersud, Stephane Humbert, Robbbert, BSD-3-Clause)

module galaxian_sbspeech
(
    input                clk,
    input                reset,
    input                pause,

    input                cmd_we,
    input          [7:0] cmd,
    output         [7:0] p1_out,

    output        [10:0] prog_a,
    input          [7:0] prog_q,
    output        [11:0] data_a,
    input          [7:0] data_q,

    output chip_pool_pkg::mcs48bus_i_t mcs48bus_0_i,
    input  chip_pool_pkg::mcs48bus_o_t mcs48bus_0_o,
    output chip_pool_pkg::sp0250_i_t   sp0250_0_i,
    input  chip_pool_pkg::sp0250_o_t   sp0250_0_o,

    output signed [15:0] audio
);

reg [12:0] f4 = 13'd0;
reg [10:0] f3 = 11'd0;
reg        ce_4m = 1'b0, ce_3m = 1'b0, ce_rom = 1'b0, half = 1'b0;
always @(posedge clk) begin
    ce_4m  <= 1'b0;
    ce_3m  <= 1'b0;
    ce_rom <= 1'b0;
    if (f4 >= 13'd7055) begin f4 <= f4 - 13'd7055; ce_4m <= ~pause; end
    else                  f4 <= f4 + 13'd625;
    if (f3 >= 11'd959) begin
        f3     <= f3 - 11'd959;
        ce_3m  <= ~pause;
        half   <= ~half;
        ce_rom <= ~pause & half;
    end
    else f3 <= f3 + 11'd65;
end

reg  [7:0] latch = 8'd0;
always @(posedge clk) if (reset) latch <= 8'd0; else if (cmd_we) latch <= cmd;

wire       ale, rd_n, wr_n;
wire [7:0] db_o, p1_o, p2_o;
wire [11:0] pmem_addr;
wire       drq;
assign p1_out = p1_o;

reg  [7:0] bus_a = 8'd0;
reg        ale_d = 1'b0, wr_n_d = 1'b1, p2_7d = 1'b1;
always @(posedge clk) begin
    ale_d  <= ale;
    wr_n_d <= wr_n;
    p2_7d  <= p2_o[7];
    if (ale_d && !ale) bus_a <= db_o;
end
wire sp_wr    = ~wr_n_d & wr_n;
wire sp_reset = reset | (p2_o[7] & ~p2_7d);

assign prog_a = pmem_addr[10:0];
assign data_a = {p2_o[5], p2_o[2:0], bus_a};

assign mcs48bus_0_i.reset_n = ~reset;
assign mcs48bus_0_i.xtal_en = ce_4m;
assign mcs48bus_0_i.int_n   = ~latch[7];
assign mcs48bus_0_i.t1      = drq;
assign mcs48bus_0_i.db      = data_q;
assign mcs48bus_0_i.p1      = {p1_o[7], latch[6:0]};
assign mcs48bus_0_i.pmem_d  = prog_q;
assign rd_n      = mcs48bus_0_o.rd_n;
assign wr_n      = mcs48bus_0_o.wr_n;
assign ale       = mcs48bus_0_o.ale;
assign db_o      = mcs48bus_0_o.db;
assign p1_o      = mcs48bus_0_o.p1;
assign p2_o      = mcs48bus_0_o.p2;
assign pmem_addr = mcs48bus_0_o.pmem_a;

wire signed [13:0] sp_audio;

assign sp0250_0_i.reset_n      = ~sp_reset;
assign sp0250_0_i.ce_3_12m     = ce_3m;
assign sp0250_0_i.ce_rom_1_56m = ce_rom;
assign sp0250_0_i.data_in      = db_o;
assign sp0250_0_i.wr           = sp_wr;
assign drq      = sp0250_0_o.drq;
assign sp_audio = sp0250_0_o.audio;

assign audio = {sp_audio[13], sp_audio, 1'b0};

endmodule
