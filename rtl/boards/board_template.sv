//============================================================================
//  board_template.sv - @Core@ board template (NOT in files.qip, never compiled).
//  Copyright (C) 2026 Rodimus
//
//  Boards never instantiate a CPU, sound chip, ROM store or board RAM. Drive the pool ports. Copy this file to start a board.
//  Pools: rtl/@core@_dispatcher.sv (chip_pool_pkg slots, Shared ROM blocks, Shared RAM pool rpool).
//  Boards go in rtl/boards/<board>/; replace the board's tie-off in the dispatcher.
//  Add one output chip_pool_pkg::<chip>_i_t <chip>_<n>_i / input chip_pool_pkg::<chip>_o_t <chip>_<n>_o pair per pool slot,
//  widen rom_a / pr_i / pr_o to the dispatcher's ROM_AW / RAM_BLOCKS.
//  CRT Flip is mandatory: crt_flip mirrors the picture 180 degrees inside the board (HDMI follows).
//============================================================================

module board_template
(
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,
    output logic        ce_pix,

    input  logic [47:0] in_ports,

    output logic [11:0] rom_a,
    input  logic  [7:0] rom_d,

    input  logic        crt_flip,
    input  logic  [3:0] h_adj,
    input  logic  [3:0] v_adj,

    output logic  [7:0] video_r,
    output logic  [7:0] video_g,
    output logic  [7:0] video_b,
    output logic        video_hs,
    output logic        video_vs,
    output logic        video_hblank,
    output logic        video_vblank,

    output logic signed [15:0] audio,

    input  logic [15:0] hs_address,
    input  logic  [7:0] hs_data_in,
    output logic  [7:0] hs_data_out,
    input  logic        hs_write,

    output ram_pool_pkg::pram_i_t [0:0] pr_i,
    input  ram_pool_pkg::pram_o_t [0:0] pr_o
);

assign ce_pix       = 1'b0;
assign rom_a        = '0;
assign video_r      = 8'd0;
assign video_g      = 8'd0;
assign video_b      = 8'd0;
assign video_hs     = 1'b0;
assign video_vs     = 1'b0;
assign video_hblank = 1'b1;
assign video_vblank = 1'b1;
assign audio        = 16'sd0;
assign hs_data_out  = 8'd0;
assign pr_i         = '0;

endmodule
