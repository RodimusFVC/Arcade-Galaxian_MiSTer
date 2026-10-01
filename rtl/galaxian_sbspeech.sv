//============================================================================
//
//  Space Battle (Hoei) speech board, per MAME galaxian.cpp sbhoei_state: an
//  8039 at 4 MHz with a 2K program ROM, an SP0250 at 3.12 MHz.
//    main CPU write:  P1 bits 6-0 = D6-D0, INT asserted while D7 is set
//    main CPU read:   the 8039's P1 output latch
//    P1 bit 7 in:     the 8039's own P1 bit 7
//    P2 out:          bank {P2.5, P2.2-0} of the 4K data ROM (256 bytes each,
//                     read by MOVX); bit 7 rising resets the SP0250
//    T1:              SP0250 DRQ
//    BUS writes:      SP0250 data (latched as WR rises, as the Sega board)
//  8039 core, bus capture and SP0250 port from the Sega G80 core's
//  segaspeech.sv (T48 by Arnim Laeuger, SP0250 port of MAME sp0250.cpp).
//
//============================================================================

module galaxian_sbspeech
(
    input                clk,           // 49.152 MHz
    input                reset,
    input                pause,

    input                cmd_we,
    input          [7:0] cmd,
    output         [7:0] p1_out,

    input         [11:0] rom_addr,
    input          [7:0] rom_data,
    input                prog_we,       // 2K program ROM
    input                data_we,       // 4K data ROM

    output signed [15:0] audio
);

// 4 MHz = 49.152 MHz x 625 / 7680, 3.12 MHz = 49.152 MHz x 65 / 1024, ROM clock = 3.12 MHz / 2
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
wire [7:0] prog_q, data_q;
wire       drq;
assign p1_out = p1_o;

// bus address latched as ALE falls; MOVX reads return the banked data ROM
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

dpram_dc #(.widthad_a(11)) prog
(
    .clock_a(clk), .address_a(rom_addr[10:0]), .data_a(rom_data), .wren_a(prog_we),
    .clock_b(clk), .address_b(pmem_addr[10:0]), .q_b(prog_q)
);

dpram_dc #(.widthad_a(12)) data
(
    .clock_a(clk), .address_a(rom_addr), .data_a(rom_data), .wren_a(data_we),
    .clock_b(clk), .address_b({p2_o[5], p2_o[2:0], bus_a}), .q_b(data_q)
);

t8039_notri_extrom #(
    .gate_port_input_g (0),
    .ram_addr_width_g  (7)                  // 8039 = 128 bytes internal RAM
) cpu (
    .xtal_i        (clk),
    .xtal_en_i     (ce_4m),
    .reset_n_i     (~reset),
    .t0_i          (1'b0),
    .t0_o          (),
    .t0_dir_o      (),
    .int_n_i       (~latch[7]),
    .ea_i          (1'b0),
    .rd_n_o        (rd_n),
    .psen_n_o      (),
    .wr_n_o        (wr_n),
    .ale_o         (ale),
    .db_i          (data_q),
    .db_o          (db_o),
    .db_dir_o      (),
    .t1_i          (drq),
    .p2_i          (8'hFF),
    .p2_o          (p2_o),
    .p2l_low_imp_o (),
    .p2h_low_imp_o (),
    .p1_i          ({p1_o[7], latch[6:0]}),
    .p1_o          (p1_o),
    .p1_low_imp_o  (),
    .prog_n_o      (),
    .pmem_addr_o   (pmem_addr),
    .pmem_data_i   (prog_q)
);

wire signed [13:0] sp_audio;

sp0250 sp
(
    .clk          (clk),
    .reset_n      (~sp_reset),
    .ce_3_12m     (ce_3m),
    .ce_rom_1_56m (ce_rom),
    .data_in      (db_o),
    .wr           (sp_wr),
    .drq          (drq),
    .audio_out    (sp_audio),
    .audio_valid  ()
);

assign audio = {sp_audio[13], sp_audio, 1'b0};

endmodule
