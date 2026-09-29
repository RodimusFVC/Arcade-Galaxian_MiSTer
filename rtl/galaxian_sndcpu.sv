//============================================================================
//
//  Check Man / Dingo sound board: Z80 at 1.62 MHz, command latch, AY-3-8910
//
//  Memory maps and interrupts per MAME galaxian.cpp (checkman_sound_map,
//  checkmaj_sound_map).
//
//============================================================================

module galaxian_sndcpu
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               mode,           // 0 Check Man (AY on I/O, IRQ at VBLANK), 1 Check Man (Japan) / Dingo
                                        // (AY at A000, IRQ every 8 lines)
    input               pause,

    input               cmd_wr,         // main CPU sound command: latch + NMI
    input         [7:0] cmd,
    input               vblank_irq,     // one clock at the start of VBLANK
    input               line8_irq,      // one clock at the start of every 8th line

    input        [11:0] rom_addr,       // ROM load
    input         [7:0] rom_data,
    input               rom_we,

    output              ay_bdir,
    output              ay_bc1,
    output        [7:0] ay_din,
    input         [7:0] ay_dout,
    output reg    [7:0] latch = 8'd0
);

// 1.62 MHz = 49.152 MHz x 675 / 20480
reg [14:0] frac = 15'd0;
reg        cen = 1'b0;
always @(posedge clk) begin
    if (frac >= 15'd19805) begin frac <= frac - 15'd19805; cen <= 1'b1; end
    else                   begin frac <= frac + 15'd675;   cen <= 1'b0; end
end

wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
wire [15:0] addr;
wire  [7:0] dout;
reg   [7:0] din;
reg         int_n = 1'b1;
reg         nmi_n = 1'b1;
reg   [6:0] nmi_hold = 7'd0;

T80sed cpu
(
    .RESET_n(~reset),
    .CLK_n(clk),
    .CLKEN(cen & ~pause),
    .WAIT_n(1'b1),
    .INT_n(int_n),
    .NMI_n(nmi_n),
    .BUSRQ_n(1'b1),
    .M1_n(m1_n),
    .MREQ_n(mreq_n),
    .IORQ_n(iorq_n),
    .RD_n(rd_n),
    .WR_n(wr_n),
    .RFSH_n(rfsh_n),
    .HALT_n(),
    .BUSAK_n(),
    .A(addr),
    .DI(din),
    .DO(dout)
);

// command: latch, then NMI held low for 128 clocks (a few CPU cycles); IRQ held until acknowledged
always @(posedge clk) begin
    if (cmd_wr) begin
        latch    <= cmd;
        nmi_hold <= 7'd127;
    end
    else if (nmi_hold != 7'd0) nmi_hold <= nmi_hold - 7'd1;
    nmi_n <= nmi_hold == 7'd0;

    if (reset | (~iorq_n & ~m1_n)) int_n <= 1'b1;
    else if (mode ? line8_irq : vblank_irq) int_n <= 1'b0;
end

wire mem = ~mreq_n & rfsh_n;
wire io  = ~iorq_n & m1_n;

// Check Man: ROM 0000-0FFF, RAM 2000-23FF; Japan / Dingo: RAM 8000-83FF, AY A000-A002
wire rom_cs = mem && addr[15:12] == 4'h0;
wire ram_cs = mem && (mode ? addr[15:10] == 6'b100000 : addr[15:10] == 6'b001000);
wire ay_mem = mode && mem && addr[15:2] == 14'h2800;            // A000-A003

wire [7:0] rom_q, ram_q;

dpram_dc #(.widthad_a(12)) rom
(
    .clock_a(clk), .address_a(rom_addr), .data_a(rom_data), .wren_a(rom_we),
    .clock_b(clk), .address_b(addr[11:0]), .q_b(rom_q)
);

dpram_dc #(.widthad_a(10)) ram
(
    .clock_a(clk), .address_a(addr[9:0]), .data_a(dout), .wren_a(ram_cs & ~wr_n), .q_a(ram_q)
);

// AY: Check Man ports 04 address / 05 data / 06 read; Japan / Dingo A000 address / A001 data / A002 read
wire [7:0] port = addr[7:0];
wire ay_addr_w = ~wr_n & (mode ? ay_mem & addr[1:0] == 2'd0 : ~mode & io & port == 8'h04);
wire ay_data_w = ~wr_n & (mode ? ay_mem & addr[1:0] == 2'd1 : ~mode & io & port == 8'h05);
wire ay_rd     = ~rd_n & (mode ? ay_mem & addr[1:0] == 2'd2 : ~mode & io & port == 8'h06);

assign ay_bdir = ay_addr_w | ay_data_w;
assign ay_bc1  = ay_addr_w | ay_rd;
assign ay_din  = dout;

always @(*) begin
    din = 8'hFF;
    if      (rom_cs) din = rom_q;
    else if (ram_cs) din = ram_q;
    else if (ay_rd)  din = ay_dout;
    else if (io && !mode && port == 8'h03) din = latch;
end

endmodule
