// ---------------------------------------------------------------- t48sv_core.sv
// ============================================================================
// t48sv - MCS-48 / UPI-41 / MCS-21/22 family core in SystemVerilog
//
// Derived from the T48 uController core by Arnim Laeuger (opencores.org/
// github.com/devsaurus/t48), cycle-for-cycle equivalent to:
//   - T48 r295 (2009-04-01), as run by the MiSTer fleet through
//     t8039_notri_extrom (fleet derivation of Laeuger's t8039_notri) and t48_core
//   - the T48 2023+ release (UPI-41 / 8021 / 8022 / 8243 support), REV2023 = 1
// Written for the MiSTer fleet (Cyclone V, Quartus 17.0).
//
// Original T48 notice (retained as its licence requires):
//
// Copyright (c) 2004, 2005, Arnim Laeuger (arniml@opencores.org)
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
// ============================================================================

// ============================================================================
// t48sv_core: one parameterised core for the whole family
//   VARIANT VAR_MCS48 (8035/39/40/48/49/50, 87xx), VAR_UPI41 (8041/41A/42),
//           VAR_MCS21 (8021), VAR_MCS22 (8022)
//   REV2023 0: T48 r295 behaviour (MiSTer fleet), 1: T48 2023+ release
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

module t48sv_core #(
  parameter int VARIANT           = 0,  // 0 MCS-48, 1 UPI-41, 2 MCS-21, 3 MCS-22
  parameter int UPI_TYPE_A        = 0,
  parameter int REV2023           = 0,
  parameter int UPI_IBF_ACK       = 1,
  parameter int XTAL_DIV_3        = 1,
  parameter int REGISTER_MNEMONIC = 1,
  parameter int INCLUDE_PORT1     = 1,
  parameter int INCLUDE_PORT2     = 1,
  parameter int INCLUDE_BUS       = 1,
  parameter int INCLUDE_TIMER     = 1,
  parameter int SAMPLE_T1_STATE   = 4
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_i,
  input  logic        t0_i,
  output logic        t0_o,
  output logic        t0_dir_o,
  input  logic        int_n_i,
  input  logic        ea_i,
  output logic        rd_n_o,
  output logic        psen_n_o,
  output logic        wr_n_o,
  output logic        ale_o,
  input  logic [7:0]  db_i,
  output logic [7:0]  db_o,
  output logic        db_dir_o,
  input  logic        t1_i,
  input  logic [7:0]  p2_i,
  output logic [7:0]  p2_o,
  output logic        p2l_low_imp_o,
  output logic        p2h_low_imp_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  output logic        p1_low_imp_o,
  input  logic [7:0]  p0_i,
  output logic [7:0]  p0_o,
  output logic        prog_n_o,
  input  logic        clk_i,
  input  logic        en_clk_i,
  output logic        xtal3_o,
  output logic [7:0]  dmem_addr_o,
  output logic        dmem_we_o,
  input  logic [7:0]  dmem_data_i,
  output logic [7:0]  dmem_data_o,
  output logic [11:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i,
  // UPI-41 host interface
  input  logic        cs_n_i,
  input  logic        rd_n_i,
  input  logic        wr_n_i,
  input  logic        a0_i,
  output logic [7:0]  sts_o,
  // 8022 A/D converter
  output logic        adc_sel_an_o,
  output logic        adc_sh_o,
  output logic [7:0]  adc_sar_o,
  input  logic        adc_comp_i
);

  localparam int VAR_MCS48 = 0, VAR_UPI41 = 1, VAR_MCS21 = 2, VAR_MCS22 = 3;

  localparam bit IS_UPI   = VARIANT == VAR_UPI41;
  localparam bit IS_MCS2X = VARIANT == VAR_MCS21 || VARIANT == VAR_MCS22;
  localparam bit IS_MCS48 = VARIANT == VAR_MCS48;
  localparam bit IS_MCS22 = VARIANT == VAR_MCS22;
  localparam bit HAS_BUS  = IS_MCS48 && INCLUDE_BUS == 1;
  localparam bit HAS_TIM  = !IS_MCS48 || INCLUDE_TIMER == 1;
  localparam bit HAS_P1   = !IS_MCS48 || INCLUDE_PORT1 == 1;
  localparam bit HAS_P2   = !IS_MCS48 || INCLUDE_PORT2 == 1;

  logic [7:0]  t48_data;
  logic        xtal_en_s, t0_s, t1_s, en_clk;
  // module data outputs (0xFF when idle, AND-ed onto the internal bus)
  logic [7:0]  alu_data, bus_data, dec_data, dm_data, pm_data, p0_data, p1_data, p2_data;
  logic [7:0]  psw_data, tim_data, adc_data;
  // control
  logic        alu_write_accu, alu_write_shadow, alu_write_temp_reg, alu_read_alu;
  logic        alu_carry, alu_aux_carry, alu_use_carry, alu_da_high, alu_da_overflow;
  logic        alu_accu_low, alu_p06, alu_p60, alu_add_inc, alu_add_dec;
  logic [3:0]  alu_op;
  logic [7:0]  accu;
  logic        bus_write_bus, bus_read_bus, bus_output_pcl, bus_bidir_bus;
  logic        bus_ibf, bus_obf, bus_int_n, bus_set_f1, bus_clear_f1, bus_ibf_int;
  logic        bus_en_dma, bus_en_flags, bus_write_sts, bus_mint_ibf_n, bus_mint_obf;
  logic        bus_dma, bus_drq;
  logic        clk_multi_cycle, clk_assert_psen, clk_assert_prog, clk_assert_rd, clk_assert_wr;
  logic [2:0]  clk_mstate;
  logic        clk_second_cycle, psen_s, prog_s, rd_s, wr_s, ale_s, xtal3_s;
  logic        cnd_compute_take, cnd_take_branch, cnd_f1, cnd_tf;
  logic [3:0]  cnd_branch_cond;
  logic [2:0]  cnd_comp_value;
  logic        dm_write_dmem_addr, dm_write_dmem, dm_read_dmem;
  logic [1:0]  dm_addr_type;
  logic        p0_write_p0, p0_read_p0;
  logic        p1_write_p1, p1_read_p1, p1_read_reg;
  logic        p2_write_p2, p2_write_exp, p2_read_p2, p2_read_reg, p2_read_exp, p2_output_pch;
  logic [7:0]  p2_core_in, p2_core_out;
  logic        pm_write_pcl, pm_read_pcl, pm_write_pch, pm_read_pch, pm_read_pmem, pm_inc_pc;
  logic        pm_write_pmem_addr;
  logic [1:0]  pm_addr_type;
  logic [11:0] pmem_addr_s, pc;
  logic        psw_read_psw, psw_read_sp, psw_write_psw, psw_write_sp, psw_special_data;
  logic        psw_carry, psw_aux_carry, psw_f0, psw_bs;
  logic        psw_inc_stackp, psw_dec_stackp, psw_write_carry, psw_write_aux_carry;
  logic        psw_write_f0, psw_write_bs;
  logic [2:0]  sp;
  logic        tim_overflow, tim_read_timer, tim_write_timer, tim_start_t, tim_start_cnt;
  logic        tim_stop_tcnt;
  logic        adc_sel_an0, adc_sel_an1, adc_read_adc;
  logic        dec_int_n, cnd_int_n, mb, istrobe;

  assign en_clk = en_clk_i;

  // 8021 / 8022: one extra XTAL/2 stage
  generate
    if (IS_MCS2X) begin : g_xtal2
      logic xtal_mcs2x_q;
      always_ff @(posedge xtal_i or negedge reset_i)
        if (!reset_i)       xtal_mcs2x_q <= 1'b0;
        else if (xtal_en_i) xtal_mcs2x_q <= ~xtal_mcs2x_q;
      assign xtal_en_s = xtal_en_i & xtal_mcs2x_q;
    end else begin : g_xtal1
      assign xtal_en_s = xtal_en_i;
    end
  endgenerate

  assign t0_s      = (VARIANT == VAR_MCS21) ? 1'b0 : t0_i;
  assign t1_s      = t1_i;
  assign cnd_int_n = IS_UPI ? bus_int_n : IS_MCS2X ? 1'b1 : int_n_i;
  assign dec_int_n = IS_UPI ? bus_int_n : (VARIANT == VAR_MCS21) ? 1'b1 : IS_MCS22 ? t0_s : int_n_i;

  assign t48_data = alu_data & bus_data & dec_data & dm_data & pm_data & p0_data & p1_data &
                    p2_data & psw_data & tim_data & adc_data;

  t48sv_alu alu_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(alu_data),
    .write_accu_i(alu_write_accu), .write_shadow_i(alu_write_shadow),
    .write_temp_reg_i(alu_write_temp_reg), .read_alu_i(alu_read_alu), .carry_i(psw_carry),
    .carry_o(alu_carry), .aux_carry_o(alu_aux_carry), .alu_op_i(alu_op),
    .use_carry_i(alu_use_carry), .add_inc_i(alu_add_inc), .add_dec_i(alu_add_dec),
    .da_high_i(alu_da_high), .da_overflow_o(alu_da_overflow),
    .accu_low_i(alu_accu_low), .p06_temp_reg_i(alu_p06), .p60_temp_reg_i(alu_p60), .accu_o(accu)
  );

  t48sv_clock_ctrl #(.XTAL_DIV_3(XTAL_DIV_3)) clock_ctrl_b (
    .clk_i(clk_i), .xtal_i(xtal_i), .xtal_en_i(xtal_en_s), .res_n_i(reset_i), .en_clk_i(en_clk),
    .xtal3_o(xtal3_s), .t0_o(t0_o), .multi_cycle_i(clk_multi_cycle),
    .assert_psen_i(clk_assert_psen), .assert_prog_i(clk_assert_prog),
    .assert_rd_i(clk_assert_rd), .assert_wr_i(clk_assert_wr), .mstate_o(clk_mstate),
    .second_cycle_o(clk_second_cycle), .ale_o(ale_s), .psen_o(psen_s), .prog_o(prog_s),
    .rd_o(rd_s), .wr_o(wr_s)
  );

  t48sv_cond_branch cond_branch_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .compute_take_i(cnd_compute_take),
    .branch_cond_i(cnd_branch_cond), .take_branch_o(cnd_take_branch), .accu_i(alu_data),
    .t0_i(t0_s), .t1_i(t1_s), .int_n_i(cnd_int_n), .f0_i(psw_f0), .f1_i(cnd_f1), .tf_i(cnd_tf),
    .carry_i(psw_carry), .ibf_i(IS_UPI ? bus_ibf : 1'b0), .obf_i(IS_UPI ? bus_obf : 1'b0),
    .comp_value_i(cnd_comp_value)
  );

  generate
    if (IS_UPI) begin : g_upi_bus
      t48sv_upi_db_bus #(.TYPE_A(1), .IBF_ACK(UPI_IBF_ACK)) db_bus_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(bus_data),
        .write_bus_i(bus_write_bus), .read_bus_i(bus_read_bus), .write_sts_i(bus_write_sts),
        .set_f1_o(bus_set_f1), .clear_f1_o(bus_clear_f1), .f0_i(psw_f0), .f1_i(cnd_f1),
        .ibf_o(bus_ibf), .obf_o(bus_obf), .int_n_o(bus_int_n), .ibf_int_i(bus_ibf_int),
        .en_dma_i(bus_en_dma), .en_flags_i(bus_en_flags), .write_p2_i(p2_write_p2),
        .mint_ibf_n_o(bus_mint_ibf_n), .mint_obf_o(bus_mint_obf), .dma_o(bus_dma), .drq_o(bus_drq),
        .dack_n_i(p2_i[7]), .a0_i(a0_i), .cs_n_i(cs_n_i), .rd_n_i(rd_n_i), .wr_n_i(wr_n_i),
        .db_i(db_i), .db_o(db_o), .sts_o(sts_o), .db_dir_o(db_dir_o)
      );
    end else begin : g_no_upi_bus
      assign {bus_ibf, bus_obf, bus_set_f1, bus_clear_f1, bus_mint_obf, bus_dma, bus_drq} = '0;
      assign bus_int_n      = 1'b1;
      assign bus_mint_ibf_n = 1'b1;
      assign sts_o          = 8'h00;
      if (HAS_BUS) begin : g_bus
        t48sv_db_bus db_bus_b (
          .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .ea_i(ea_i), .data_i(t48_data),
          .data_o(bus_data), .write_bus_i(bus_write_bus), .read_bus_i(bus_read_bus),
          .output_pcl_i(bus_output_pcl), .bidir_bus_i(bus_bidir_bus), .pcl_i(pmem_addr_s[7:0]),
          .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o)
        );
      end else begin : g_no_bus
        assign bus_data = 8'hFF;
        assign db_o     = 8'h00;
        assign db_dir_o = 1'b0;
      end
    end
  endgenerate

  t48sv_decoder #(
    .REGISTER_MNEMONIC(REGISTER_MNEMONIC), .VARIANT(VARIANT), .UPI_TYPE_A(UPI_TYPE_A),
    .REV2023(REV2023)
  ) decoder_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .xtal_i(xtal_i), .xtal_en_i(xtal_en_s),
    .ea_i(IS_MCS48 ? ea_i : 1'b0), .ale_i(ale_s), .int_n_i(dec_int_n), .t0_dir_o(t0_dir_o),
    .data_i(t48_data), .data_o(dec_data),
    .alu_write_accu_o(alu_write_accu), .alu_write_shadow_o(alu_write_shadow),
    .alu_write_temp_reg_o(alu_write_temp_reg), .alu_read_alu_o(alu_read_alu),
    .bus_write_bus_o(bus_write_bus), .bus_read_bus_o(bus_read_bus),
    .bus_set_f1_i(bus_set_f1), .bus_clear_f1_i(bus_clear_f1), .bus_ibf_int_o(bus_ibf_int),
    .bus_en_dma_o(bus_en_dma), .bus_en_flags_o(bus_en_flags), .bus_write_sts_o(bus_write_sts),
    .dm_write_dmem_addr_o(dm_write_dmem_addr), .dm_write_dmem_o(dm_write_dmem),
    .dm_read_dmem_o(dm_read_dmem), .p0_write_p0_o(p0_write_p0), .p0_read_p0_o(p0_read_p0),
    .p1_write_p1_o(p1_write_p1), .p1_read_p1_o(p1_read_p1), .p2_write_p2_o(p2_write_p2),
    .p2_write_exp_o(p2_write_exp), .p2_read_p2_o(p2_read_p2), .p2_read_exp_o(p2_read_exp),
    .pm_write_pcl_o(pm_write_pcl), .pm_read_pcl_o(pm_read_pcl), .pm_write_pch_o(pm_write_pch),
    .pm_read_pch_o(pm_read_pch), .pm_read_pmem_o(pm_read_pmem),
    .psw_read_psw_o(psw_read_psw), .psw_read_sp_o(psw_read_sp), .psw_write_psw_o(psw_write_psw),
    .psw_write_sp_o(psw_write_sp), .alu_carry_i(alu_carry), .alu_op_o(alu_op),
    .alu_use_carry_o(alu_use_carry), .alu_add_inc_o(alu_add_inc), .alu_add_dec_o(alu_add_dec), .alu_da_high_o(alu_da_high), .alu_accu_low_o(alu_accu_low),
    .alu_p06_temp_reg_o(alu_p06), .alu_p60_temp_reg_o(alu_p60),
    .alu_da_overflow_i(alu_da_overflow), .bus_output_pcl_o(bus_output_pcl),
    .bus_bidir_bus_o(bus_bidir_bus), .clk_multi_cycle_o(clk_multi_cycle),
    .clk_assert_psen_o(clk_assert_psen), .clk_assert_prog_o(clk_assert_prog),
    .clk_assert_rd_o(clk_assert_rd), .clk_assert_wr_o(clk_assert_wr),
    .clk_mstate_i(clk_mstate), .clk_second_cycle_i(clk_second_cycle),
    .cnd_compute_take_o(cnd_compute_take), .cnd_branch_cond_o(cnd_branch_cond),
    .cnd_take_branch_i(cnd_take_branch), .cnd_comp_value_o(cnd_comp_value), .cnd_f1_o(cnd_f1),
    .cnd_tf_o(cnd_tf), .dm_addr_type_o(dm_addr_type), .p1_read_reg_o(p1_read_reg),
    .p2_read_reg_o(p2_read_reg), .p2_output_pch_o(p2_output_pch), .pm_inc_pc_o(pm_inc_pc),
    .pm_write_pmem_addr_o(pm_write_pmem_addr), .pm_addr_type_o(pm_addr_type),
    .psw_special_data_o(psw_special_data), .psw_carry_i(psw_carry),
    .psw_aux_carry_i(psw_aux_carry), .psw_f0_i(psw_f0), .psw_inc_stackp_o(psw_inc_stackp),
    .psw_dec_stackp_o(psw_dec_stackp), .psw_write_carry_o(psw_write_carry),
    .psw_write_aux_carry_o(psw_write_aux_carry), .psw_write_f0_o(psw_write_f0),
    .psw_write_bs_o(psw_write_bs), .tim_read_timer_o(tim_read_timer),
    .tim_write_timer_o(tim_write_timer), .tim_start_t_o(tim_start_t),
    .tim_start_cnt_o(tim_start_cnt), .tim_stop_tcnt_o(tim_stop_tcnt),
    .tim_overflow_i(tim_overflow), .adc_sel_an0_o(adc_sel_an0), .adc_sel_an1_o(adc_sel_an1),
    .adc_read_adc_o(adc_read_adc), .mb_o(mb), .istrobe_o(istrobe)
  );

  t48sv_dmem_ctrl dmem_ctrl_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data),
    .write_dmem_addr_i(dm_write_dmem_addr), .write_dmem_i(dm_write_dmem),
    .read_dmem_i(dm_read_dmem), .addr_type_i(dm_addr_type), .bank_select_i(psw_bs),
    .data_o(dm_data), .dmem_data_i(dmem_data_i), .dmem_addr_o(dmem_addr_o),
    .dmem_we_o(dmem_we_o), .dmem_data_o(dmem_data_o)
  );

  generate
    if (HAS_TIM) begin : g_timer
      t48sv_timer #(.SAMPLE_T1_STATE(SAMPLE_T1_STATE)) timer_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .t1_i(t1_s), .mstate_i(clk_mstate),
        .data_i(t48_data), .data_o(tim_data), .read_timer_i(tim_read_timer),
        .write_timer_i(tim_write_timer), .start_t_i(tim_start_t), .start_cnt_i(tim_start_cnt),
        .stop_tcnt_i(tim_stop_tcnt), .overflow_o(tim_overflow)
      );
    end else begin : g_no_timer
      assign tim_data     = 8'hFF;
      assign tim_overflow = 1'b0;
    end

    if (IS_MCS2X) begin : g_p0
      t48sv_port p0_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(p0_data),
        .write_i(p0_write_p0), .read_i(p0_read_p0), .read_reg_i(1'b0), .port_i(p0_i),
        .port_o(p0_o), .low_imp_o()
      );
    end else begin : g_no_p0
      assign p0_data = 8'hFF;
      assign p0_o    = 8'h00;
    end

    if (HAS_P1) begin : g_p1
      t48sv_port p1_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(p1_data),
        .write_i(p1_write_p1), .read_i(p1_read_p1), .read_reg_i(IS_MCS2X ? 1'b0 : p1_read_reg),
        .port_i(p1_i), .port_o(p1_o), .low_imp_o(p1_low_imp_o)
      );
    end else begin : g_no_p1
      assign p1_data      = 8'hFF;
      assign p1_o         = 8'h00;
      assign p1_low_imp_o = 1'b0;
    end

    if (HAS_P2) begin : g_p2
      t48sv_p2 p2_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .xtal_i(xtal_i), .xtal_en_i(xtal_en_s),
        .data_i(t48_data), .data_o(p2_data), .write_p2_i(p2_write_p2), .write_exp_i(p2_write_exp),
        .read_p2_i(p2_read_p2), .read_reg_i(IS_MCS2X ? 1'b0 : p2_read_reg),
        .read_exp_i(p2_read_exp), .output_pch_i(p2_output_pch), .pch_i(pmem_addr_s[11:8]),
        .p2_i(p2_core_in), .p2_o(p2_core_out), .p2l_low_imp_o(p2l_low_imp_o),
        .p2h_low_imp_o(p2h_low_imp_o)
      );
    end else begin : g_no_p2
      assign p2_data       = 8'hFF;
      assign p2_core_out   = 8'h00;
      assign p2l_low_imp_o = 1'b0;
      assign p2h_low_imp_o = 1'b0;
    end

    if (IS_MCS22) begin : g_adc
      t48sv_adc adc_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .ale_i(ale_s), .mstate_i(clk_mstate),
        .sel_an0_i(adc_sel_an0), .sel_an1_i(adc_sel_an1), .read_adc_i(adc_read_adc),
        .data_o(adc_data), .sel_an_o(adc_sel_an_o), .sh_o(adc_sh_o), .sar_o(adc_sar_o),
        .comp_i(adc_comp_i)
      );
    end else begin : g_no_adc
      assign adc_data     = 8'hFF;
      assign adc_sel_an_o = 1'b0;
      assign adc_sh_o     = 1'b0;
      assign adc_sar_o    = 8'h00;
    end
  endgenerate

  // 8021: 4-bit P2; UPI-41A: P24..P27 carry OBF / IBF / DRQ when enabled
  assign p2_core_in = (VARIANT == VAR_MCS21) ? {4'h0, p2_i[3:0]} : p2_i;
  assign p2_o = (VARIANT == VAR_MCS21) ? {4'h0, p2_core_out[3:0]} :
                IS_UPI ? {p2_core_out[7], bus_dma ? bus_drq : p2_core_out[6],
                          p2_core_out[5] & bus_mint_ibf_n, p2_core_out[4] & bus_mint_obf,
                          p2_core_out[3:0]} :
                p2_core_out;

  t48sv_pmem_ctrl pmem_ctrl_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(pm_data),
    .write_pcl_i(pm_write_pcl), .read_pcl_i(pm_read_pcl), .write_pch_i(pm_write_pch),
    .read_pch_i(pm_read_pch), .inc_pc_i(pm_inc_pc), .write_pmem_addr_i(pm_write_pmem_addr),
    .addr_type_i(pm_addr_type), .read_pmem_i(pm_read_pmem), .pmem_addr_o(pmem_addr_s), .pc_o(pc),
    .pmem_data_i(pmem_data_i)
  );

  t48sv_psw psw_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(psw_data),
    .read_psw_i(psw_read_psw), .read_sp_i(psw_read_sp), .write_psw_i(psw_write_psw),
    .write_sp_i(psw_write_sp), .special_data_i(psw_special_data), .inc_stackp_i(psw_inc_stackp),
    .dec_stackp_i(psw_dec_stackp), .write_carry_i(psw_write_carry),
    .write_aux_carry_i(psw_write_aux_carry), .write_f0_i(psw_write_f0), .write_bs_i(psw_write_bs),
    .carry_o(psw_carry), .aux_carry_i(alu_aux_carry), .aux_carry_o(psw_aux_carry), .f0_o(psw_f0),
    .bs_o(psw_bs), .sp_o(sp)
  );

  assign ale_o       = ale_s;
  assign psen_n_o    = (IS_MCS48) ? ~psen_s : 1'b1;
  assign prog_n_o    = ~prog_s;
  assign rd_n_o      = (IS_MCS48) ? ~rd_s : 1'b1;
  assign wr_n_o      = (IS_MCS48) ? ~wr_s : 1'b1;
  assign xtal3_o     = xtal3_s;
  assign pmem_addr_o = pmem_addr_s;

endmodule

// ---------------------------------------------------------------- t48sv_blocks.sv
// ============================================================================
// t48sv datapath blocks (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// All registers: asynchronous active-low reset, as in T48.
// ============================================================================

// ----------------------------------------------------------------------------
// Clock control: XTAL/3 divider, machine states, ALE / PSEN / PROG / RD / WR
// ----------------------------------------------------------------------------
module t48sv_clock_ctrl #(
  parameter int XTAL_DIV_3 = 1
) (
  input  logic       clk_i,
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  output logic       xtal3_o,
  output logic       t0_o,
  input  logic       multi_cycle_i,
  input  logic       assert_psen_i,
  input  logic       assert_prog_i,
  input  logic       assert_rd_i,
  input  logic       assert_wr_i,
  output logic [2:0] mstate_o,
  output logic       second_cycle_o,
  output logic       ale_o,
  output logic       psen_o,
  output logic       prog_o,
  output logic       rd_o,
  output logic       wr_o
);

  localparam logic [2:0] M1 = 3'd0, M2 = 3'd1, M3 = 3'd2, M4 = 3'd3, M5 = 3'd4;

  logic       x2_s, x3_s;
  logic [2:0] mstate_q;
  logic       ale_q, psen_q, prog_q, rd_q, wr_q;
  logic       second_cycle_q, multi_cycle_q;

  generate
    if (XTAL_DIV_3 == 1) begin : g_div3
      logic [1:0] xtal_q;
      logic       t0_q;
      always_ff @(posedge xtal_i or negedge res_n_i)
        if (!res_n_i) begin
          xtal_q <= 2'd0;
          t0_q   <= 1'b0;
        end else if (xtal_en_i) begin
          xtal_q <= (xtal_q < 2'd2) ? xtal_q + 2'd1 : 2'd0;
          t0_q   <= x3_s;
        end
      assign x2_s = xtal_en_i & (xtal_q == 2'd1);
      assign x3_s = xtal_en_i & (xtal_q == 2'd2);
      assign t0_o = t0_q;
    end else begin : g_nodiv
      assign x2_s = xtal_en_i;
      assign x3_s = xtal_en_i;
      assign t0_o = xtal_i;
    end
  endgenerate

  always_ff @(posedge xtal_i or negedge res_n_i)
    if (!res_n_i) begin
      ale_q  <= 1'b0;
      psen_q <= 1'b0;
      prog_q <= 1'b0;
      rd_q   <= 1'b0;
      wr_q   <= 1'b0;
    end else begin
      case (mstate_q)
        M5: if (x2_s && !second_cycle_q) begin
              if (assert_rd_i) rd_q <= 1'b1;
              if (assert_wr_i) wr_q <= 1'b1;
            end
        M1: if (x3_s) psen_q <= 1'b0;
        M2: if (x3_s) begin
              rd_q   <= 1'b0;
              wr_q   <= 1'b0;
              prog_q <= 1'b0;
            end
        M3: if (x3_s) ale_q <= 1'b1;
        M4: begin
              if (x3_s && assert_psen_i) psen_q <= 1'b1;
              if (x3_s && multi_cycle_q && !second_cycle_q && assert_prog_i) prog_q <= 1'b1;
              if (x2_s) ale_q <= 1'b0;
            end
        default: begin
              ale_q  <= 1'b0;
              psen_q <= 1'b0;
              prog_q <= 1'b0;
              rd_q   <= 1'b0;
              wr_q   <= 1'b0;
            end
      endcase
    end

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i)
      mstate_q <= M3;
    else if (en_clk_i)
      mstate_q <= (mstate_q == M5 || mstate_q > M5) ? M1 : mstate_q + 3'd1;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      multi_cycle_q  <= 1'b0;
      second_cycle_q <= 1'b0;
    end else if (en_clk_i) begin
      if (mstate_q == M5 && multi_cycle_q && second_cycle_q) begin
        multi_cycle_q  <= 1'b0;
        second_cycle_q <= 1'b0;
      end else begin
        if (mstate_q == M2 && multi_cycle_i) multi_cycle_q  <= 1'b1;
        if (mstate_q == M5 && multi_cycle_q) second_cycle_q <= 1'b1;
      end
    end

  assign xtal3_o        = x3_s;
  assign mstate_o       = mstate_q;
  assign second_cycle_o = second_cycle_q;
  assign ale_o          = ale_q;
  assign psen_o         = psen_q;
  assign prog_o         = prog_q;
  assign rd_o           = rd_q;
  assign wr_o           = wr_q;

endmodule


// ----------------------------------------------------------------------------
// ALU: accumulator, shadow and temp registers
// ----------------------------------------------------------------------------
module t48sv_alu (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       write_accu_i,
  input  logic       write_shadow_i,
  input  logic       write_temp_reg_i,
  input  logic       read_alu_i,
  input  logic       carry_i,
  output logic       carry_o,
  output logic       aux_carry_o,
  input  logic [3:0] alu_op_i,
  input  logic       use_carry_i,
  input  logic       add_inc_i,
  input  logic       add_dec_i,
  input  logic       da_high_i,
  output logic       da_overflow_o,
  input  logic       accu_low_i,
  input  logic       p06_temp_reg_i,
  input  logic       p60_temp_reg_i,
  output logic [7:0] accu_o
);

  localparam logic [3:0] ALU_AND = 4'd0, ALU_OR = 4'd1, ALU_XOR = 4'd2, ALU_CPL = 4'd3,
                         ALU_CLR = 4'd4, ALU_RL = 4'd5, ALU_RR = 4'd6, ALU_SWAP = 4'd7,
                         ALU_DEC = 4'd8, ALU_INC = 4'd9, ALU_ADD = 4'd10, ALU_CONCAT = 4'd11,
                         ALU_NOP = 4'd12;

  logic [7:0] accu_q, shadow_q, temp_q;
  logic [7:0] in_a, in_b, data_s;
  logic [8:0] add_b, add_r;
  logic [3:0] da_nib;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      accu_q   <= 8'h00;
      shadow_q <= 8'h00;
      temp_q   <= 8'h00;
    end else if (en_clk_i) begin
      if (write_accu_i) begin
        if (accu_low_i) accu_q[3:0] <= data_i[3:0];
        else            accu_q      <= data_i;
      end
      shadow_q <= write_shadow_i ? data_i : accu_q;
      if (p06_temp_reg_i)        temp_q <= 8'h06;
      else if (p60_temp_reg_i)   temp_q <= 8'h60;
      else if (write_temp_reg_i) temp_q <= data_i;
    end

  assign in_a = shadow_q;
  assign in_b = temp_q;

  always_comb begin
    add_b = add_inc_i ? 9'h001 : add_dec_i ? 9'h1FF : {1'b0, in_b};
    add_r = {1'b0, in_a} + add_b + {8'h00, use_carry_i & carry_i};
  end
  assign aux_carry_o = add_r[4] ^ in_a[4] ^ in_b[4];

  always_comb begin
    data_s  = 8'h00;
    carry_o = 1'b0;
    case (alu_op_i)
      ALU_AND:    data_s = in_a & in_b;
      ALU_OR:     data_s = in_a | in_b;
      ALU_XOR:    data_s = in_a ^ in_b;
      ALU_ADD:    begin data_s = add_r[7:0]; carry_o = add_r[8]; end
      ALU_CPL:    data_s = ~in_a;
      ALU_CLR:    data_s = 8'h00;
      ALU_RL:     begin data_s = {in_a[6:0], use_carry_i ? carry_i : in_a[7]}; carry_o = in_a[7]; end
      ALU_RR:     begin data_s = {use_carry_i ? carry_i : in_a[0], in_a[7:1]}; carry_o = in_a[0]; end
      ALU_SWAP:   data_s = {in_a[3:0], in_a[7:4]};
      ALU_DEC,
      ALU_INC:    data_s = add_r[7:0];
      ALU_CONCAT: data_s = {in_b[7:4], in_a[3:0]};
      ALU_NOP:    data_s = in_a;
      default:    data_s = 8'h00;
    endcase
  end

  assign da_nib        = da_high_i ? shadow_q[7:4] : shadow_q[3:0];
  assign da_overflow_o = da_nib > 4'd9;
  assign data_o        = read_alu_i ? data_s : 8'hFF;
  assign accu_o        = accu_q;

endmodule


// ----------------------------------------------------------------------------
// Conditional branch decision
// ----------------------------------------------------------------------------
module t48sv_cond_branch (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       compute_take_i,
  input  logic [3:0] branch_cond_i,
  output logic       take_branch_o,
  input  logic [7:0] accu_i,
  input  logic       t0_i,
  input  logic       t1_i,
  input  logic       int_n_i,
  input  logic       f0_i,
  input  logic       f1_i,
  input  logic       tf_i,
  input  logic       carry_i,
  input  logic       ibf_i,
  input  logic       obf_i,
  input  logic [2:0] comp_value_i
);

  localparam logic [3:0] COND_ON_BIT = 4'd0, COND_Z = 4'd1, COND_C = 4'd2, COND_F0 = 4'd3,
                         COND_F1 = 4'd4, COND_INT = 4'd5, COND_T0 = 4'd6, COND_T1 = 4'd7,
                         COND_TF = 4'd8, COND_NIBF = 4'd9, COND_OBF = 4'd10;

  logic take_s, take_q;

  always_comb
    case (branch_cond_i)
      COND_ON_BIT: take_s = accu_i[comp_value_i];
      COND_Z:      take_s = (|accu_i) == ~comp_value_i[0];
      COND_C:      take_s = carry_i == comp_value_i[0];
      COND_F0:     take_s = f0_i;
      COND_F1:     take_s = f1_i;
      COND_INT:    take_s = ~int_n_i;
      COND_T0:     take_s = t0_i == comp_value_i[0];
      COND_T1:     take_s = t1_i == comp_value_i[0];
      COND_TF:     take_s = tf_i;
      COND_NIBF:   take_s = ~ibf_i;
      COND_OBF:    take_s = obf_i;
      default:     take_s = 1'b0;
    endcase

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i)                       take_q <= 1'b0;
    else if (en_clk_i && compute_take_i) take_q <= take_s;

  assign take_branch_o = take_q;

endmodule


// ----------------------------------------------------------------------------
// MCS-48 BUS port
// ----------------------------------------------------------------------------
module t48sv_db_bus (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       ea_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       write_bus_i,
  input  logic       read_bus_i,
  input  logic       output_pcl_i,
  input  logic       bidir_bus_i,
  input  logic [7:0] pcl_i,
  input  logic [7:0] db_i,
  output logic [7:0] db_o,
  output logic       db_dir_o
);

  logic [7:0] bus_q;
  logic       dir_q, dir_qq;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      bus_q  <= 8'h00;
      dir_q  <= 1'b0;
      dir_qq <= 1'b0;
    end else if (en_clk_i) begin
      dir_qq <= write_bus_i | dir_q;
      if (write_bus_i) begin
        bus_q <= data_i;
        dir_q <= 1'b1;
      end else if (ea_i || bidir_bus_i)
        dir_q <= 1'b0;
    end

  assign db_o     = output_pcl_i ? pcl_i : bus_q;
  assign db_dir_o = dir_qq | output_pcl_i;
  assign data_o   = read_bus_i ? db_i : 8'hFF;

endmodule


// ----------------------------------------------------------------------------
// UPI-41 data bus buffer (DBBIN / DBBOUT / STATUS), host side synchronous
// IBF_ACK = 1: IN A,DBB also releases the IBF interrupt (fleet DECO edit)
// ----------------------------------------------------------------------------
module t48sv_upi_db_bus #(
  parameter int TYPE_A  = 1,
  parameter int IBF_ACK = 1
) (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       write_bus_i,
  input  logic       read_bus_i,
  input  logic       write_sts_i,
  output logic       set_f1_o,
  output logic       clear_f1_o,
  input  logic       f0_i,
  input  logic       f1_i,
  output logic       ibf_o,
  output logic       obf_o,
  output logic       int_n_o,
  input  logic       ibf_int_i,
  input  logic       en_dma_i,
  input  logic       en_flags_i,
  input  logic       write_p2_i,
  output logic       mint_ibf_n_o,
  output logic       mint_obf_o,
  output logic       dma_o,
  output logic       drq_o,
  input  logic       dack_n_i,
  input  logic       a0_i,
  input  logic       cs_n_i,
  input  logic       rd_n_i,
  input  logic       wr_n_i,
  input  logic [7:0] db_i,
  output logic [7:0] db_o,
  output logic [7:0] sts_o,
  output logic       db_dir_o
);

  logic       read_s, write_s, read_q, write_q, read_pulse_s, write_pulse_s;
  logic       dack_s, ext_acc_s;
  logic       a0_q, ibf_q, obf_q, int_n_q, drq_q;
  logic [7:0] dbbin_q, dbbout_q, status_q;
  logic [3:0] sts_q;
  logic       dma_q, flags_q;

  assign dack_s    = ~dack_n_i & dma_q;
  assign ext_acc_s = ~cs_n_i | dack_s;
  assign read_s    = ext_acc_s & ~rd_n_i;
  assign write_s   = ext_acc_s & ~wr_n_i;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      read_q   <= 1'b0;
      write_q  <= 1'b0;
      a0_q     <= 1'b0;
      status_q <= 8'h00;
    end else begin
      read_q  <= read_s;
      write_q <= write_s;
      if (dack_s)                a0_q <= 1'b0;
      else if (read_s || write_s) a0_q <= a0_i;
      if (!read_s) status_q <= {(TYPE_A == 1) ? sts_q : 4'b0000, f1_i, f0_i, ibf_q, obf_q};
    end

  assign read_pulse_s  = read_q & ~read_s;
  assign write_pulse_s = write_q & ~write_s;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      dbbin_q  <= 8'h00;
      dbbout_q <= 8'h00;
      sts_q    <= 4'h0;
      ibf_q    <= 1'b0;
      obf_q    <= 1'b0;
      int_n_q  <= 1'b1;
      dma_q    <= 1'b0;
      drq_q    <= 1'b0;
      flags_q  <= 1'b0;
    end else begin
      if (read_pulse_s && !a0_q)
        obf_q <= 1'b0;
      else if (write_pulse_s) begin
        dbbin_q <= db_i;
        ibf_q   <= 1'b1;
        int_n_q <= 1'b0;
      end
      if (dack_s && (read_s || write_s)) drq_q <= 1'b0;
      if (en_clk_i) begin
        if (write_bus_i) begin
          dbbout_q <= data_i;
          obf_q    <= 1'b1;
        end else if (read_bus_i) begin
          ibf_q <= 1'b0;
          if (IBF_ACK == 1) int_n_q <= 1'b1;
        end else if (write_sts_i)
          sts_q <= data_i[7:4];
        if (ibf_int_i) int_n_q <= 1'b1;
        if (TYPE_A == 1) begin
          if (en_dma_i) begin
            dma_q <= 1'b1;
            drq_q <= 1'b0;
          end
          if (en_flags_i) flags_q <= 1'b1;
          if (dma_q && write_p2_i && data_i[6]) drq_q <= 1'b1;
        end
      end
    end

  assign set_f1_o     = write_pulse_s & a0_q;
  assign clear_f1_o   = write_pulse_s & ~a0_q;
  assign ibf_o        = ibf_q;
  assign obf_o        = obf_q;
  assign int_n_o      = int_n_q;
  assign drq_o        = drq_q;
  assign db_o         = (~a0_i | (dack_s & dma_q)) ? dbbout_q : status_q;
  assign sts_o        = status_q;
  assign db_dir_o     = read_s;
  assign data_o       = read_bus_i ? dbbin_q : 8'hFF;
  assign mint_ibf_n_o = ~(flags_q & ibf_q);
  assign mint_obf_o   = ~(flags_q & ~obf_q);
  assign dma_o        = dma_q;

endmodule


// ----------------------------------------------------------------------------
// Data memory address control
// ----------------------------------------------------------------------------
module t48sv_dmem_ctrl (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic [7:0] data_i,
  input  logic       write_dmem_addr_i,
  input  logic       write_dmem_i,
  input  logic       read_dmem_i,
  input  logic [1:0] addr_type_i,
  input  logic       bank_select_i,
  output logic [7:0] data_o,
  input  logic [7:0] dmem_data_i,
  output logic [7:0] dmem_addr_o,
  output logic       dmem_we_o,
  output logic [7:0] dmem_data_o
);

  localparam logic [1:0] DM_PLAIN = 2'd0, DM_REG = 2'd1, DM_STACK = 2'd2;

  logic [7:0] addr_s, addr_q;
  logic [5:0] stack_v;

  assign stack_v = {2'b00, data_i[2:0], 1'b0} + 6'd8;

  always_comb
    case (addr_type_i)
      DM_PLAIN: addr_s = data_i;
      DM_REG:   addr_s = {3'b000, {2{bank_select_i}}, data_i[2:0]};
      DM_STACK: addr_s = {2'b00, stack_v};
      default:  addr_s = {addr_q[7:1], 1'b1};
    endcase

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i)                           addr_q <= 8'h00;
    else if (en_clk_i && write_dmem_addr_i) addr_q <= addr_s;

  assign dmem_addr_o = (write_dmem_addr_i && en_clk_i) ? addr_s : addr_q;
  assign dmem_data_o = data_i;
  assign data_o      = read_dmem_i ? dmem_data_i : 8'hFF;
  assign dmem_we_o   = write_dmem_i;

endmodule


// ----------------------------------------------------------------------------
// Program counter and program memory address
// ----------------------------------------------------------------------------
module t48sv_pmem_ctrl (
  input  logic        clk_i,
  input  logic        res_n_i,
  input  logic        en_clk_i,
  input  logic [7:0]  data_i,
  output logic [7:0]  data_o,
  input  logic        write_pcl_i,
  input  logic        read_pcl_i,
  input  logic        write_pch_i,
  input  logic        read_pch_i,
  input  logic        inc_pc_i,
  input  logic        write_pmem_addr_i,
  input  logic [1:0]  addr_type_i,
  input  logic        read_pmem_i,
  output logic [11:0] pmem_addr_o,
  output logic [11:0] pc_o,
  input  logic [7:0]  pmem_data_i
);

  localparam logic [1:0] PM_PAGE = 2'd1, PM_PAGE3 = 2'd2;

  logic [11:0] pc_q, addr_s, addr_q;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      pc_q   <= 12'h000;
      addr_q <= 12'h000;
    end else if (en_clk_i) begin
      if (write_pcl_i)      pc_q[7:0]  <= data_i;
      else if (write_pch_i) pc_q[11:8] <= data_i[3:0];
      else if (inc_pc_i)    pc_q[10:0] <= pc_q[10:0] + 11'd1;
      if (write_pmem_addr_i) addr_q <= addr_s;
    end

  always_comb
    case (addr_type_i)
      PM_PAGE:  addr_s = {pc_q[11:8], data_i};
      PM_PAGE3: addr_s = {4'b0011, data_i};
      default:  addr_s = pc_q;
    endcase

  always_comb
    if (read_pmem_i)     data_o = pmem_data_i;
    else if (read_pcl_i) data_o = pc_q[7:0];
    else if (read_pch_i) data_o = {4'hF, pc_q[11:8]};
    else                 data_o = 8'hFF;

  assign pmem_addr_o = addr_q;
  assign pc_o        = pc_q;

endmodule


// ----------------------------------------------------------------------------
// PSW: CY AC F0 BS + stack pointer
// ----------------------------------------------------------------------------
module t48sv_psw (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       read_psw_i,
  input  logic       read_sp_i,
  input  logic       write_psw_i,
  input  logic       write_sp_i,
  input  logic       special_data_i,
  input  logic       inc_stackp_i,
  input  logic       dec_stackp_i,
  input  logic       write_carry_i,
  input  logic       write_aux_carry_i,
  input  logic       write_f0_i,
  input  logic       write_bs_i,
  output logic       carry_o,
  input  logic       aux_carry_i,
  output logic       aux_carry_o,
  output logic       f0_o,
  output logic       bs_o,
  output logic [2:0] sp_o
);

  logic [3:0] psw_q;   // CY AC F0 BS
  logic [2:0] sp_q;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      psw_q <= 4'h0;
      sp_q  <= 3'd0;
    end else if (en_clk_i) begin
      if (write_psw_i) psw_q <= data_i[7:4];
      if (dec_stackp_i)      sp_q <= sp_q - 3'd1;
      else if (inc_stackp_i) sp_q <= sp_q + 3'd1;
      else if (write_sp_i)   sp_q <= data_i[2:0];
      if (write_carry_i)     psw_q[3] <= special_data_i;
      if (write_aux_carry_i) psw_q[2] <= aux_carry_i;
      if (write_f0_i)        psw_q[1] <= special_data_i;
      if (write_bs_i)        psw_q[0] <= special_data_i;
    end

  assign data_o      = {read_psw_i ? psw_q : 4'hF, read_sp_i ? {1'b1, sp_q} : 4'hF};
  assign carry_o     = psw_q[3];
  assign aux_carry_o = psw_q[2];
  assign f0_o        = psw_q[1];
  assign bs_o        = psw_q[0];
  assign sp_o        = sp_q;

endmodule


// ----------------------------------------------------------------------------
// Timer / event counter with /32 prescaler
// ----------------------------------------------------------------------------
module t48sv_timer #(
  parameter int SAMPLE_T1_STATE = 4
) (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       t1_i,
  input  logic [2:0] mstate_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       read_timer_i,
  input  logic       write_timer_i,
  input  logic       start_t_i,
  input  logic       start_cnt_i,
  input  logic       stop_tcnt_i,
  output logic       overflow_o
);

  localparam logic [2:0] M3 = 3'd2, M4 = 3'd3;

  logic [7:0] counter_q;
  logic       overflow_q, t1_q;
  logic [4:0] prescaler_q;
  logic [1:0] inc_sel_q;     // 0 none, 1 timer, 2 counter
  logic       sample_s, increment_s;

  assign sample_s    = mstate_i == ((SAMPLE_T1_STATE == 3) ? M3 : M4);
  assign increment_s = (inc_sel_q == 2'd1) ? (mstate_i == M4 && prescaler_q == 5'd31) :
                       (inc_sel_q == 2'd2) ? (sample_s && t1_q && !t1_i) : 1'b0;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      overflow_q  <= 1'b0;
      t1_q        <= 1'b0;
      prescaler_q <= 5'd0;
      inc_sel_q   <= 2'd0;
      counter_q   <= 8'h00;
    end else if (en_clk_i) begin
      overflow_q <= 1'b0;
      if (write_timer_i)
        counter_q <= data_i;
      else if (increment_s) begin
        counter_q <= counter_q + 8'd1;
        if (counter_q == 8'hFF) overflow_q <= 1'b1;
      end
      if (sample_s) t1_q <= t1_i;
      if (start_t_i)          prescaler_q <= 5'd0;
      else if (mstate_i == M3) prescaler_q <= prescaler_q + 5'd1;
      if (start_t_i)        inc_sel_q <= 2'd1;
      else if (start_cnt_i) inc_sel_q <= 2'd2;
      else if (stop_tcnt_i) inc_sel_q <= 2'd0;
    end

  assign data_o     = read_timer_i ? counter_q : 8'hFF;
  assign overflow_o = overflow_q;

endmodule


// ----------------------------------------------------------------------------
// Quasi-bidirectional port (P1, and P0 of the 8021/8022)
// ----------------------------------------------------------------------------
module t48sv_port (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       write_i,
  input  logic       read_i,
  input  logic       read_reg_i,
  input  logic [7:0] port_i,
  output logic [7:0] port_o,
  output logic       low_imp_o
);

  logic [7:0] port_q;
  logic       low_imp_q;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      port_q    <= 8'hFF;
      low_imp_q <= 1'b0;
    end else if (en_clk_i) begin
      if (write_i) port_q <= data_i;
      low_imp_q <= write_i;
    end

  assign data_o    = !read_i ? 8'hFF : read_reg_i ? port_q : port_i;
  assign port_o    = port_q;
  assign low_imp_o = low_imp_q;

endmodule


// ----------------------------------------------------------------------------
// Port 2: quasi-bidirectional, PCH output during external fetch, 8243 nibble
// ----------------------------------------------------------------------------
module t48sv_p2 (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       write_p2_i,
  input  logic       write_exp_i,
  input  logic       read_p2_i,
  input  logic       read_reg_i,
  input  logic       read_exp_i,
  input  logic       output_pch_i,
  input  logic [3:0] pch_i,
  input  logic [7:0] p2_i,
  output logic [7:0] p2_o,
  output logic       p2l_low_imp_o,
  output logic       p2h_low_imp_o
);

  logic [7:0] p2_q, p2_out_q;
  logic       l_low_imp_q, h_low_imp_q, l_del_q, h_del_q, en_clk_q, output_pch_q;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      p2_q        <= 8'hFF;
      l_low_imp_q <= 1'b0;
      h_low_imp_q <= 1'b0;
    end else if (en_clk_i) begin
      l_low_imp_q <= write_p2_i | write_exp_i;
      h_low_imp_q <= write_p2_i;
      if (write_p2_i)       p2_q      <= data_i;
      else if (write_exp_i) p2_q[3:0] <= data_i[3:0];
    end

  always_ff @(posedge xtal_i or negedge res_n_i)
    if (!res_n_i) begin
      p2_out_q     <= 8'hFF;
      l_del_q      <= 1'b0;
      h_del_q      <= 1'b0;
      output_pch_q <= 1'b0;
      en_clk_q     <= 1'b0;
    end else if (xtal_en_i) begin
      en_clk_q     <= en_clk_i;
      p2_out_q     <= {p2_q[7:4], output_pch_i ? pch_i : p2_q[3:0]};
      output_pch_q <= output_pch_i;
      l_del_q      <= en_clk_q & ((output_pch_q ^ output_pch_i) | l_low_imp_q);
      h_del_q      <= en_clk_q & h_low_imp_q;
    end

  assign data_o        = !read_p2_i ? 8'hFF : read_reg_i ? p2_q :
                         read_exp_i ? {4'h0, p2_i[3:0]} : p2_i;
  assign p2_o          = p2_out_q;
  assign p2l_low_imp_o = l_del_q;
  assign p2h_low_imp_o = h_del_q;

endmodule


// ----------------------------------------------------------------------------
// 8022 A/D converter sequencer (successive approximation, comparator external)
// ----------------------------------------------------------------------------
module t48sv_adc (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       ale_i,
  input  logic [2:0] mstate_i,
  input  logic       sel_an0_i,
  input  logic       sel_an1_i,
  input  logic       read_adc_i,
  output logic [7:0] data_o,
  output logic       sel_an_o,
  output logic       sh_o,
  output logic [7:0] sar_o,
  input  logic       comp_i
);

  localparam logic [2:0] M1 = 3'd0, M3 = 3'd2;

  // 0 = sample/hold, 1..8 = converting bit 7..0
  logic [3:0] state_q;
  logic       ale_q, sel_an_q;
  logic [7:0] sar_q, crr_q;
  logic [7:0] bit_s;     // SAR bit under test

  assign bit_s = 8'h80 >> (state_q - 4'd1);

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      ale_q    <= 1'b0;
      sar_q    <= 8'h00;
      crr_q    <= 8'h00;
      sel_an_q <= 1'b0;
      state_q  <= 4'd0;
    end else begin
      if (ale_i)         ale_q <= 1'b1;
      else if (en_clk_i) ale_q <= ale_i;
      if (en_clk_i) begin
        if (sel_an0_i)      sel_an_q <= 1'b0;
        else if (sel_an1_i) sel_an_q <= 1'b1;
        if (state_q == 4'd0) begin
          if (ale_q) begin
            state_q <= 4'd1;
            sar_q   <= 8'h80;
          end
        end else if (state_q > 4'd8)
          state_q <= 4'd0;
        else if (mstate_i == (state_q[0] ? M1 : M3)) begin
          sar_q <= sar_q & ~bit_s | (comp_i ? bit_s : 8'h00) | (bit_s >> 1);
          if (state_q == 4'd8) crr_q <= {sar_q[7:1], comp_i};
          state_q <= (state_q == 4'd8) ? 4'd0 : state_q + 4'd1;
        end
        if (sel_an0_i || sel_an1_i) state_q <= 4'd0;
      end
    end

  assign sh_o     = (state_q == 4'd0) & ale_q & en_clk_i;
  assign sar_o    = sar_q;
  assign sel_an_o = sel_an_q;
  assign data_o   = read_adc_i ? crr_q : 8'hFF;

endmodule

// ---------------------------------------------------------------- t48sv_decoder.sv
// ============================================================================
// t48sv instruction decoder, machine-cycle control and interrupt controller
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

module t48sv_decoder #(
  parameter int REGISTER_MNEMONIC = 1,
  parameter int VARIANT           = 0,  // 0 MCS-48, 1 UPI-41, 2 MCS-21, 3 MCS-22
  parameter int UPI_TYPE_A        = 0,
  parameter int REV2023           = 0
) (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       ea_i,
  input  logic       ale_i,
  input  logic       int_n_i,
  output logic       t0_dir_o,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  output logic       alu_write_accu_o,
  output logic       alu_write_shadow_o,
  output logic       alu_write_temp_reg_o,
  output logic       alu_read_alu_o,
  output logic       bus_write_bus_o,
  output logic       bus_read_bus_o,
  input  logic       bus_set_f1_i,
  input  logic       bus_clear_f1_i,
  output logic       bus_ibf_int_o,
  output logic       bus_en_dma_o,
  output logic       bus_en_flags_o,
  output logic       bus_write_sts_o,
  output logic       dm_write_dmem_addr_o,
  output logic       dm_write_dmem_o,
  output logic       dm_read_dmem_o,
  output logic       p0_write_p0_o,
  output logic       p0_read_p0_o,
  output logic       p1_write_p1_o,
  output logic       p1_read_p1_o,
  output logic       p2_write_p2_o,
  output logic       p2_write_exp_o,
  output logic       p2_read_p2_o,
  output logic       p2_read_exp_o,
  output logic       pm_write_pcl_o,
  output logic       pm_read_pcl_o,
  output logic       pm_write_pch_o,
  output logic       pm_read_pch_o,
  output logic       pm_read_pmem_o,
  output logic       psw_read_psw_o,
  output logic       psw_read_sp_o,
  output logic       psw_write_psw_o,
  output logic       psw_write_sp_o,
  input  logic       alu_carry_i,
  output logic [3:0] alu_op_o,
  output logic       alu_use_carry_o,
  output logic       alu_add_inc_o,
  output logic       alu_add_dec_o,
  output logic       alu_da_high_o,
  output logic       alu_accu_low_o,
  output logic       alu_p06_temp_reg_o,
  output logic       alu_p60_temp_reg_o,
  input  logic       alu_da_overflow_i,
  output logic       bus_output_pcl_o,
  output logic       bus_bidir_bus_o,
  output logic       clk_multi_cycle_o,
  output logic       clk_assert_psen_o,
  output logic       clk_assert_prog_o,
  output logic       clk_assert_rd_o,
  output logic       clk_assert_wr_o,
  input  logic [2:0] clk_mstate_i,
  input  logic       clk_second_cycle_i,
  output logic       cnd_compute_take_o,
  output logic [3:0] cnd_branch_cond_o,
  input  logic       cnd_take_branch_i,
  output logic [2:0] cnd_comp_value_o,
  output logic       cnd_f1_o,
  output logic       cnd_tf_o,
  output logic [1:0] dm_addr_type_o,
  output logic       p1_read_reg_o,
  output logic       p2_read_reg_o,
  output logic       p2_output_pch_o,
  output logic       pm_inc_pc_o,
  output logic       pm_write_pmem_addr_o,
  output logic [1:0] pm_addr_type_o,
  output logic       psw_special_data_o,
  input  logic       psw_carry_i,
  input  logic       psw_aux_carry_i,
  input  logic       psw_f0_i,
  output logic       psw_inc_stackp_o,
  output logic       psw_dec_stackp_o,
  output logic       psw_write_carry_o,
  output logic       psw_write_aux_carry_o,
  output logic       psw_write_f0_o,
  output logic       psw_write_bs_o,
  output logic       tim_read_timer_o,
  output logic       tim_write_timer_o,
  output logic       tim_start_t_o,
  output logic       tim_start_cnt_o,
  output logic       tim_stop_tcnt_o,
  input  logic       tim_overflow_i,
  output logic       adc_sel_an0_o,
  output logic       adc_sel_an1_o,
  output logic       adc_read_adc_o,
  output logic       mb_o,
  output logic       istrobe_o
);

  localparam logic [2:0] M1 = 3'd0, M2 = 3'd1, M3 = 3'd2, M4 = 3'd3, M5 = 3'd4;
  localparam int VAR_MCS48 = 0, VAR_UPI41 = 1, VAR_MCS21 = 2, VAR_MCS22 = 3;
  localparam logic [3:0] ALU_AND = 4'd0, ALU_OR = 4'd1, ALU_XOR = 4'd2, ALU_CPL = 4'd3,
                         ALU_CLR = 4'd4, ALU_RL = 4'd5, ALU_RR = 4'd6, ALU_SWAP = 4'd7,
                         ALU_DEC = 4'd8, ALU_INC = 4'd9, ALU_ADD = 4'd10, ALU_CONCAT = 4'd11,
                         ALU_NOP = 4'd12, COND_ON_BIT = 4'd0, COND_Z = 4'd1, COND_C = 4'd2,
                         COND_F0 = 4'd3, COND_F1 = 4'd4, COND_INT = 4'd5, COND_T0 = 4'd6,
                         COND_T1 = 4'd7, COND_TF = 4'd8, COND_NIBF = 4'd9, COND_OBF = 4'd10;
  localparam logic [1:0] DM_PLAIN = 2'd0, DM_REG = 2'd1, DM_STACK = 2'd2, DM_STACK_HIGH = 2'd3,
                         PM_PC = 2'd0, PM_PAGE = 2'd1, PM_PAGE3 = 2'd2;

  localparam bit IS_UPI   = VARIANT == VAR_UPI41;
  localparam bit IS_MCS2X = VARIANT == VAR_MCS21 || VARIANT == VAR_MCS22;
  localparam bit IS_MCS22 = VARIANT == VAR_MCS22;

  // mnemonics
  localparam logic [6:0]
    MN_ADD = 7'd1, MN_ADD_A_DATA = 7'd2, MN_ANL = 7'd3, MN_ANL_A_DATA = 7'd4, MN_ANL_EXT = 7'd5,
    MN_CALL = 7'd6, MN_CLR_A = 7'd7, MN_CLR_C = 7'd8, MN_CLR_F = 7'd9, MN_CPL_A = 7'd10,
    MN_CPL_C = 7'd11, MN_CPL_F = 7'd12, MN_DA = 7'd13, MN_DEC = 7'd14, MN_DIS_EN_I = 7'd15,
    MN_DIS_EN_TCNTI = 7'd16, MN_DJNZ = 7'd17, MN_ENT0_CLK = 7'd18, MN_IN = 7'd19, MN_INC = 7'd20,
    MN_INS = 7'd21, MN_JBB = 7'd22, MN_JC = 7'd23, MN_JF = 7'd24, MN_JMP = 7'd25, MN_JMPP = 7'd26,
    MN_JNI = 7'd27, MN_JT = 7'd28, MN_JTF = 7'd29, MN_JZ = 7'd30, MN_MOV_A_DATA = 7'd31,
    MN_MOV_A_PSW = 7'd32, MN_MOV_A_RR = 7'd33, MN_MOV_PSW_A = 7'd34, MN_MOV_RR = 7'd35,
    MN_MOV_RR_DATA = 7'd36, MN_MOV_T = 7'd37, MN_MOVD_A_PP = 7'd38, MN_MOVP = 7'd39, MN_MOVX = 7'd40,
    MN_NOP = 7'd41, MN_ORL = 7'd42, MN_ORL_A_DATA = 7'd43, MN_ORL_EXT = 7'd44, MN_OUTD_PP_A = 7'd45,
    MN_OUTL_EXT = 7'd46, MN_RET = 7'd47, MN_RETR = 7'd48, MN_RL = 7'd49, MN_RR = 7'd50,
    MN_SEL_MB = 7'd51, MN_SEL_RB = 7'd52, MN_STOP_TCNT = 7'd53, MN_STRT = 7'd54, MN_SWAP = 7'd55,
    MN_XCH = 7'd56, MN_XRL = 7'd57, MN_XRL_A_DATA = 7'd58, MN_IN_DBB = 7'd59, MN_OUT_DBB = 7'd60,
    MN_JNIBF = 7'd61, MN_JOBF = 7'd62, MN_EN_DMA_FLAGS = 7'd63, MN_MOV_STS = 7'd64,
    MN_IN_P0 = 7'd65, MN_OUTL_P0 = 7'd66, MN_RAD = 7'd67, MN_RETI = 7'd68, MN_SEL_AN = 7'd69;

  localparam bit IS_48    = VARIANT == VAR_MCS48;
  localparam bit IS_48UPI = IS_48 || IS_UPI;
  localparam bit IS_UPIA  = IS_UPI && UPI_TYPE_A == 1;

  // opcode -> {mnemonic, multi_cycle}; one flat table, variant columns fold away
  function automatic logic [7:0] decode(input logic [7:0] op);
    logic [6:0] m;
    logic       c;
    m = MN_NOP;
    c = 1'b0;
    casez (op)
      // ---- all variants
      8'b0110_1???, 8'b0110_000?, 8'b0111_1???, 8'b0111_000?: m = MN_ADD;
      8'h03, 8'h13:                         begin m = MN_ADD_A_DATA; c = 1'b1; end
      8'b0101_1???, 8'b0101_000?:           m = MN_ANL;
      8'h53:                                begin m = MN_ANL_A_DATA; c = 1'b1; end
      8'b???1_0100:                         begin m = MN_CALL; c = 1'b1; end
      8'h27:                                m = MN_CLR_A;
      8'h97:                                m = MN_CLR_C;
      8'h37:                                m = MN_CPL_A;
      8'hA7:                                m = MN_CPL_C;
      8'h57:                                m = MN_DA;
      8'h07:                                m = MN_DEC;
      8'b1110_1???:                         begin m = MN_DJNZ; c = 1'b1; end
      8'h09, 8'h0A:                         begin m = MN_IN; c = 1'b1; end
      8'h17, 8'b0001_1???, 8'b0001_000?:    m = MN_INC;
      8'hF6, 8'hE6:                         begin m = MN_JC; c = 1'b1; end
      8'b???0_0100:                         begin m = MN_JMP; c = 1'b1; end
      8'hB3:                                begin m = MN_JMPP; c = 1'b1; end
      8'h16:                                begin m = MN_JTF; c = 1'b1; end
      8'h96, 8'hC6:                         begin m = MN_JZ; c = 1'b1; end
      8'h23:                                begin m = MN_MOV_A_DATA; c = 1'b1; end
      8'b1111_1???, 8'b1111_000?:           m = MN_MOV_A_RR;
      8'b1010_1???, 8'b1010_000?:           m = MN_MOV_RR;
      8'b1011_1???, 8'b1011_000?:           begin m = MN_MOV_RR_DATA; c = 1'b1; end
      8'h62, 8'h42:                         m = MN_MOV_T;
      8'b0000_11??:                         begin m = MN_MOVD_A_PP; c = 1'b1; end
      8'hA3:                                begin m = MN_MOVP; c = 1'b1; end
      8'b0100_1???, 8'b0100_000?:           m = MN_ORL;
      8'h43:                                begin m = MN_ORL_A_DATA; c = 1'b1; end
      8'b0011_11??, 8'b1001_11??, 8'b1000_11??: begin m = MN_OUTD_PP_A; c = 1'b1; end
      8'h39, 8'h3A:                         begin m = MN_OUTL_EXT; c = 1'b1; end
      8'h83:                                begin m = MN_RET; c = 1'b1; end
      8'hE7, 8'hF7:                         m = MN_RL;
      8'h77, 8'h67:                         m = MN_RR;
      8'h65:                                m = MN_STOP_TCNT;
      8'h45, 8'h55:                         m = MN_STRT;
      8'h47:                                m = MN_SWAP;
      8'b0010_1???, 8'b0010_000?, 8'b0011_000?: m = MN_XCH;
      8'b1101_1???, 8'b1101_000?:           m = MN_XRL;
      8'hD3:                                begin m = MN_XRL_A_DATA; c = 1'b1; end
      // ---- variant specific
      8'h99, 8'h9A, 8'h98:  if (IS_48UPI && (op != 8'h98 || IS_48)) begin m = MN_ANL_EXT; c = 1'b1; end
      8'h89, 8'h8A, 8'h88:  if (IS_48UPI && (op != 8'h88 || IS_48)) begin m = MN_ORL_EXT; c = 1'b1; end
      8'hA5, 8'hB5:         if (IS_48UPI) m = op[4] ? MN_CPL_F : MN_CLR_F;
      8'h85, 8'h95:         if (IS_48UPI) m = op[4] ? MN_CPL_F : MN_CLR_F;
                            else if (IS_MCS22) m = MN_SEL_AN;
      8'b1100_1???:         if (IS_48UPI) m = MN_DEC;
      8'h05, 8'h15:         if (IS_48UPI || IS_MCS22) m = MN_DIS_EN_I;
      8'h25, 8'h35:         if (IS_48UPI || IS_MCS22) m = MN_DIS_EN_TCNTI;
      8'b???1_0010:         if (IS_48UPI) begin m = MN_JBB; c = 1'b1; end
      8'hB6, 8'h76:         if (IS_48UPI) begin m = MN_JF; c = 1'b1; end
      8'h46, 8'h56:         begin m = MN_JT; c = 1'b1; end
      8'h26, 8'h36:         if (IS_48UPI || IS_MCS22) begin m = MN_JT; c = 1'b1; end
      8'hC7:                if (IS_48UPI) m = MN_MOV_A_PSW;
      8'hD7:                if (IS_48UPI) m = MN_MOV_PSW_A;
      8'hE3:                if (IS_48UPI) begin m = MN_MOVP; c = 1'b1; end
      8'h93:                if (IS_48UPI) begin m = MN_RETR; c = 1'b1; end
                            else if (IS_MCS22) begin m = MN_RETI; c = 1'b1; end
      8'hC5, 8'hD5:         if (IS_48UPI) m = MN_SEL_RB;
      8'h75:                if (IS_48) m = MN_ENT0_CLK;
      8'h08:                if (IS_48) begin m = MN_INS; c = 1'b1; end
                            else if (IS_MCS2X) begin m = MN_IN_P0; c = 1'b1; end
      8'h86:                if (IS_48) begin m = MN_JNI; c = 1'b1; end
                            else if (IS_UPI) begin m = MN_JOBF; c = 1'b1; end
      8'h80:                if (IS_48) begin m = MN_MOVX; c = 1'b1; end
                            else if (IS_MCS22) begin m = MN_RAD; c = 1'b1; end
      8'h81, 8'h91:         if (IS_48) begin m = MN_MOVX; c = 1'b1; end
      8'h90:                if (IS_48) begin m = MN_MOVX; c = 1'b1; end
                            else if (IS_UPIA) m = MN_MOV_STS;
                            else if (IS_MCS2X) begin m = MN_OUTL_P0; c = 1'b1; end
      8'h02:                if (IS_48) begin m = MN_OUTL_EXT; c = 1'b1; end
                            else if (IS_UPI) m = MN_OUT_DBB;
      8'hE5, 8'hF5:         if (IS_48) m = MN_SEL_MB;
                            else if (IS_UPIA) m = MN_EN_DMA_FLAGS;
      8'h22:                if (IS_UPI) m = MN_IN_DBB;
      8'hD6:                if (IS_UPI) begin m = MN_JNIBF; c = 1'b1; end
      default: ;
    endcase
    decode = {m, c};
  endfunction

  logic [7:0] opc_opcode_q;
  logic [7:0] mn_rec_s;
  logic [6:0] mnemonic_q, mn;
  logic       opc_multi_cycle_s, opc_read_bus_s, opc_inj_int_s;
  logic       last_cycle_s, assert_psen_s;
  logic       branch_taken_s, branch_taken_q;
  logic       pm_inc_pc_s, pm_write_pmem_addr_s, add_inc_pc_s, add_write_pmem_addr_s;
  logic       clear_f1_s, cpl_f1_s, f1_q;
  logic       clear_mb_s, set_mb_s, mb_q, mb_v;
  logic       ent0_clk_s, t0_dir_q;
  logic [7:0] data_s;
  logic       read_dec_s;
  logic       bus_read_bus_s, add_read_bus_s, dm_write_dmem_s;
  logic       p2_output_exp_s, movx_first_cycle_s;
  logic       jtf_executed_s, en_tcnti_s, dis_tcnti_s, en_i_s, dis_i_s;
  logic       retr_executed_s, int_executed_s;
  logic       injected_int_q, istrobe_res_q, istrobe_q;
  logic       need_address_v;
  // interrupt controller
  logic [1:0] int_state_q, int_state_s;   // 0 idle, 1 pending, 2 int
  logic       timer_flag_q, timer_overflow_q, timer_int_enable_q, int_enable_q;
  logic       int_q, ale_q, int_type_q, int_in_progress_q;
  logic       int_pending_s, int_in_progress_s, tim_int_s;

  assign mn_rec_s = decode(opc_opcode_q);

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      opc_opcode_q <= 8'h00;
      mnemonic_q   <= MN_NOP;
    end else if (en_clk_i) begin
      if (opc_read_bus_s)     opc_opcode_q <= data_i;
      else if (opc_inj_int_s) opc_opcode_q <= 8'h14;
      else                    mnemonic_q   <= mn_rec_s[7:1];
    end

  assign opc_multi_cycle_s = mn_rec_s[0];
  assign mn                = (REGISTER_MNEMONIC == 1) ? mnemonic_q : mn_rec_s[7:1];
  assign last_cycle_s      = ~opc_multi_cycle_s | clk_second_cycle_i;

  // --------------------------------------------------------------------------
  // machine cycle: opcode fetch, PC increment, external program memory
  // --------------------------------------------------------------------------
  always_comb begin
    clk_assert_psen_o    = 1'b0;
    pm_inc_pc_s          = 1'b0;
    pm_write_pmem_addr_s = 1'b0;
    pm_read_pmem_o       = 1'b0;
    bus_output_pcl_o     = 1'b0;
    p2_output_pch_o      = 1'b0;
    opc_read_bus_s       = 1'b0;
    opc_inj_int_s        = 1'b0;
    bus_read_bus_s       = 1'b0;
    need_address_v       = ~clk_second_cycle_i | assert_psen_s;
    case (clk_mstate_i)
      M1: begin
        if (need_address_v) begin
          if (!ea_i) begin
            if (!int_pending_s) pm_read_pmem_o = 1'b1;
          end else begin
            if (!int_pending_s) bus_read_bus_s = 1'b1;
            p2_output_pch_o = 1'b1;
          end
        end
        if (!clk_second_cycle_i) begin
          if (!int_pending_s) opc_read_bus_s = 1'b1;
          else                opc_inj_int_s  = 1'b1;
        end
      end
      M2: if (need_address_v && !branch_taken_q && !int_pending_s) pm_inc_pc_s = 1'b1;
      M3: if (need_address_v) pm_write_pmem_addr_s = 1'b1;
      M4: if (ea_i && ((!clk_second_cycle_i && assert_psen_s) || last_cycle_s)) begin
            clk_assert_psen_o = 1'b1;
            p2_output_pch_o   = 1'b1;
            bus_output_pcl_o  = 1'b1;
          end
      M5: if (ea_i && (need_address_v || last_cycle_s) && !p2_output_exp_s && !movx_first_cycle_s)
            p2_output_pch_o = 1'b1;
      default: ;
    endcase
  end

  // --------------------------------------------------------------------------
  // instruction decode
  // --------------------------------------------------------------------------
  always_comb begin
    data_s                = 8'h00;   // T48: '-', resolved to 0 as GHDL does
    read_dec_s            = 1'b0;
    branch_taken_s        = 1'b0;
    clear_f1_s            = 1'b0;
    cpl_f1_s              = 1'b0;
    clear_mb_s            = 1'b0;
    set_mb_s              = 1'b0;
    add_inc_pc_s          = 1'b0;
    assert_psen_s         = 1'b0;
    alu_write_accu_o      = 1'b0;
    alu_write_shadow_o    = 1'b0;
    alu_write_temp_reg_o  = 1'b0;
    alu_p06_temp_reg_o    = 1'b0;
    alu_p60_temp_reg_o    = 1'b0;
    alu_read_alu_o        = 1'b0;
    bus_write_bus_o       = 1'b0;
    bus_bidir_bus_o       = 1'b0;
    bus_ibf_int_o         = 1'b0;
    bus_en_dma_o          = 1'b0;
    bus_en_flags_o        = 1'b0;
    bus_write_sts_o       = 1'b0;
    dm_write_dmem_addr_o  = 1'b0;
    dm_write_dmem_s       = 1'b0;
    dm_read_dmem_o        = 1'b0;
    pm_write_pcl_o        = 1'b0;
    pm_read_pcl_o         = 1'b0;
    pm_write_pch_o        = 1'b0;
    pm_read_pch_o         = 1'b0;
    pm_addr_type_o        = PM_PC;
    psw_read_psw_o        = 1'b0;
    psw_read_sp_o         = 1'b0;
    psw_write_psw_o       = 1'b0;
    psw_write_sp_o        = 1'b0;
    alu_op_o              = ALU_NOP;
    alu_da_high_o         = 1'b0;
    alu_accu_low_o        = 1'b0;
    clk_assert_prog_o     = 1'b0;
    clk_assert_rd_o       = 1'b0;
    clk_assert_wr_o       = 1'b0;
    cnd_branch_cond_o     = COND_ON_BIT;
    cnd_compute_take_o    = 1'b0;
    cnd_comp_value_o      = opc_opcode_q[7:5];
    dm_addr_type_o        = DM_REG;
    tim_read_timer_o      = 1'b0;
    tim_write_timer_o     = 1'b0;
    tim_start_t_o         = 1'b0;
    tim_start_cnt_o       = 1'b0;
    tim_stop_tcnt_o       = 1'b0;
    p0_write_p0_o         = 1'b0;
    p0_read_p0_o          = 1'b0;
    p1_write_p1_o         = 1'b0;
    p1_read_p1_o          = 1'b0;
    p1_read_reg_o         = 1'b0;
    p2_write_p2_o         = 1'b0;
    p2_write_exp_o        = 1'b0;
    p2_read_p2_o          = 1'b0;
    p2_read_reg_o         = 1'b0;
    p2_read_exp_o         = 1'b0;
    p2_output_exp_s       = 1'b0;
    psw_special_data_o    = 1'b0;
    psw_inc_stackp_o      = 1'b0;
    psw_dec_stackp_o      = 1'b0;
    psw_write_carry_o     = 1'b0;
    psw_write_aux_carry_o = 1'b0;
    psw_write_f0_o        = 1'b0;
    psw_write_bs_o        = 1'b0;
    adc_sel_an0_o         = 1'b0;
    adc_sel_an1_o         = 1'b0;
    adc_read_adc_o        = 1'b0;
    jtf_executed_s        = 1'b0;
    en_tcnti_s            = 1'b0;
    dis_tcnti_s           = 1'b0;
    en_i_s                = 1'b0;
    dis_i_s               = 1'b0;
    retr_executed_s       = 1'b0;
    int_executed_s        = 1'b0;
    add_write_pmem_addr_s = 1'b0;
    ent0_clk_s            = 1'b0;
    add_read_bus_s        = 1'b0;
    movx_first_cycle_s    = 1'b0;

    mb_v = int_in_progress_s ? 1'b0 : mb_q;

    // register address for Rr / @Rr in M2 of every instruction
    if (!clk_second_cycle_i && clk_mstate_i == M2) begin
      data_s               = {5'b00000, opc_opcode_q[3] ? opc_opcode_q[2:1] : 2'b00, opc_opcode_q[0]};
      read_dec_s           = 1'b1;
      dm_write_dmem_addr_o = 1'b1;
      dm_addr_type_o       = DM_REG;
    end

    case (mn)
      // ---------------------------------------------------------- arithmetic
      MN_ADD, MN_ANL, MN_ORL, MN_XRL:
        case (clk_mstate_i)
          M3: if (!opc_opcode_q[3]) begin
                dm_read_dmem_o       = 1'b1;
                dm_write_dmem_addr_o = 1'b1;
                dm_addr_type_o       = DM_PLAIN;
              end
          M4: begin
                dm_read_dmem_o       = 1'b1;
                alu_write_temp_reg_o = 1'b1;
              end
          M5: begin
                alu_op_o         = (mn == MN_ADD) ? ALU_ADD : (mn == MN_ANL) ? ALU_AND :
                                   (mn == MN_ORL) ? ALU_OR : ALU_XOR;
                alu_read_alu_o   = 1'b1;
                alu_write_accu_o = 1'b1;
                if (mn == MN_ADD) begin
                  psw_special_data_o    = alu_carry_i;
                  psw_write_carry_o     = 1'b1;
                  psw_write_aux_carry_o = 1'b1;
                end
              end
          default: ;
        endcase

      MN_ADD_A_DATA, MN_ANL_A_DATA, MN_ORL_A_DATA, MN_XRL_A_DATA: begin
        assert_psen_s = 1'b1;
        if (clk_second_cycle_i)
          case (clk_mstate_i)
            M1: alu_write_temp_reg_o = 1'b1;
            M3: begin
                  alu_op_o         = (mn == MN_ADD_A_DATA) ? ALU_ADD : (mn == MN_ANL_A_DATA) ? ALU_AND :
                                     (mn == MN_ORL_A_DATA) ? ALU_OR : ALU_XOR;
                  alu_read_alu_o   = 1'b1;
                  alu_write_accu_o = 1'b1;
                  if (mn == MN_ADD_A_DATA) begin
                      psw_special_data_o    = alu_carry_i;
                    psw_write_carry_o     = 1'b1;
                    psw_write_aux_carry_o = 1'b1;
                  end
                end
            default: ;
          endcase
      end

      MN_ANL_EXT, MN_ORL_EXT: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i) begin
          if (clk_mstate_i == M5) begin
            if (opc_opcode_q[1:0] == 2'b00) add_read_bus_s = 1'b1;
            else if (!opc_opcode_q[1]) begin
              p1_read_p1_o  = 1'b1;
              p1_read_reg_o = 1'b1;
            end else begin
              p2_read_p2_o  = 1'b1;
              p2_read_reg_o = 1'b1;
            end
            alu_write_temp_reg_o = 1'b1;
          end
        end else
          case (clk_mstate_i)
            M1: alu_write_shadow_o = 1'b1;
            M2: begin
                  alu_read_alu_o     = 1'b1;
                  alu_write_shadow_o = 1'b1;
                end
            M3: begin
                  alu_op_o       = (mn == MN_ANL_EXT) ? ALU_AND : ALU_OR;
                  alu_read_alu_o = 1'b1;
                  if (opc_opcode_q[1:0] == 2'b00) bus_write_bus_o = 1'b1;
                  else if (!opc_opcode_q[1])      p1_write_p1_o   = 1'b1;
                  else                            p2_write_p2_o   = 1'b1;
                end
            default: ;
          endcase
      end

      // -------------------------------------------------------------- CALL
      MN_CALL: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i)
          case (clk_mstate_i)
            M3: begin
                  psw_read_sp_o        = 1'b1;
                  dm_write_dmem_addr_o = 1'b1;
                  dm_addr_type_o       = DM_STACK;
                  if (!int_pending_s && !IS_MCS2X) add_inc_pc_s = 1'b1;
                end
            M4: begin
                  pm_read_pcl_o   = 1'b1;
                  dm_write_dmem_s = 1'b1;
                end
            M5: begin
                  psw_read_psw_o       = 1'b1;
                  pm_read_pch_o        = 1'b1;
                  dm_write_dmem_addr_o = 1'b1;
                  dm_addr_type_o       = DM_STACK_HIGH;
                  dm_write_dmem_s      = 1'b1;
                  psw_inc_stackp_o     = 1'b1;
                end
            default: ;
          endcase
        else
          case (clk_mstate_i)
            M1: begin
                  pm_write_pcl_o = 1'b1;
                  branch_taken_s = 1'b1;
                  if (int_pending_s) begin
                    data_s = {5'b00000, tim_int_s, 2'b11};
                    if (!tim_int_s) bus_ibf_int_o = 1'b1;
                    read_dec_s = 1'b1;
                  end
                end
            M2: begin
                  pm_write_pch_o = 1'b1;
                  read_dec_s     = 1'b1;
                  if (!int_pending_s)
                    data_s = {4'b0000, mb_v, opc_opcode_q[7:5]};
                  else begin
                    data_s         = 8'h00;
                    int_executed_s = 1'b1;
                  end
                end
            default: ;
          endcase
      end

      // ------------------------------------------------- single-cycle misc
      MN_CLR_A:
        if (clk_mstate_i == M3) begin
          alu_op_o         = ALU_CLR;
          alu_read_alu_o   = 1'b1;
          alu_write_accu_o = 1'b1;
        end
      MN_CLR_C:
        if (clk_mstate_i == M3) begin
          psw_special_data_o = 1'b0;
          psw_write_carry_o  = 1'b1;
        end
      MN_CLR_F:
        if (clk_mstate_i == M3) begin
          if (!opc_opcode_q[5]) begin
            psw_special_data_o = 1'b0;
            psw_write_f0_o     = 1'b1;
          end else
            clear_f1_s = 1'b1;
        end
      MN_CPL_A:
        if (clk_mstate_i == M3) begin
          alu_op_o         = ALU_CPL;
          alu_read_alu_o   = 1'b1;
          alu_write_accu_o = 1'b1;
        end
      MN_CPL_C:
        if (clk_mstate_i == M3) begin
          psw_special_data_o = ~psw_carry_i;
          psw_write_carry_o  = 1'b1;
        end
      MN_CPL_F:
        if (clk_mstate_i == M3) begin
          if (!opc_opcode_q[5]) begin
            psw_special_data_o = ~psw_f0_i;
            psw_write_f0_o     = 1'b1;
          end else
            cpl_f1_s = 1'b1;
        end

      MN_DA: begin
        alu_op_o = ALU_ADD;
        case (clk_mstate_i)
          M3: alu_p06_temp_reg_o = 1'b1;
          M4: begin
                if (psw_aux_carry_i || alu_da_overflow_i) begin
                  alu_read_alu_o     = 1'b1;
                  alu_write_shadow_o = 1'b1;
                end
                alu_p60_temp_reg_o = 1'b1;
              end
          M5: begin
                alu_da_high_o = 1'b1;
                if (alu_da_overflow_i)
                  psw_special_data_o = alu_carry_i;
                else begin
                  alu_op_o           = ALU_NOP;
                  psw_special_data_o = 1'b0;
                end
                alu_read_alu_o    = 1'b1;
                alu_write_accu_o  = 1'b1;
                psw_write_carry_o = 1'b1;
              end
          default: ;
        endcase
      end

      MN_DEC:
        case (clk_mstate_i)
          M4: if (opc_opcode_q[6]) begin
                dm_read_dmem_o     = 1'b1;
                alu_write_shadow_o = 1'b1;
              end
          M5: begin
                alu_op_o       = ALU_DEC;
                alu_read_alu_o = 1'b1;
                if (!opc_opcode_q[6]) alu_write_accu_o = 1'b1;
                else                  dm_write_dmem_s  = 1'b1;
              end
          default: ;
        endcase

      MN_DIS_EN_I:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[4]) dis_i_s = 1'b1;
          else                 en_i_s  = 1'b1;
        end
      MN_DIS_EN_TCNTI:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[4]) dis_tcnti_s = 1'b1;
          else                 en_tcnti_s  = 1'b1;
        end

      MN_DJNZ: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i)
          case (clk_mstate_i)
            M4: begin
                  dm_read_dmem_o     = 1'b1;
                  alu_write_shadow_o = 1'b1;
                end
            M5: begin
                  alu_op_o            = ALU_DEC;
                  alu_read_alu_o      = 1'b1;
                  dm_write_dmem_s     = 1'b1;
                  cnd_compute_take_o  = 1'b1;
                  cnd_branch_cond_o   = COND_Z;
                  cnd_comp_value_o[0] = 1'b0;
                end
            default: ;
          endcase
        else if (clk_mstate_i == M1 && cnd_take_branch_i) begin
          pm_write_pcl_o = 1'b1;
          branch_taken_s = 1'b1;
        end
      end

      MN_EN_DMA_FLAGS:
        if (clk_mstate_i == M4) begin
          if (!opc_opcode_q[4]) bus_en_dma_o   = 1'b1;
          else                  bus_en_flags_o = 1'b1;
        end
      MN_ENT0_CLK:
        if (clk_mstate_i == M3) ent0_clk_s = 1'b1;

      // ------------------------------------------------------------ ports
      MN_IN:
        if (clk_second_cycle_i && clk_mstate_i == M2) begin
          alu_write_accu_o = 1'b1;
          if (!opc_opcode_q[1]) p1_read_p1_o = 1'b1;
          else                  p2_read_p2_o = 1'b1;
        end
      MN_IN_DBB:
        if (clk_mstate_i == M4) begin
          alu_write_accu_o = 1'b1;
          add_read_bus_s   = 1'b1;
        end
      MN_IN_P0:
        if (clk_second_cycle_i && clk_mstate_i == M2) begin
          alu_write_accu_o = 1'b1;
          p0_read_p0_o     = 1'b1;
        end
      MN_INS: begin
        clk_assert_rd_o = 1'b1;
        if (clk_second_cycle_i && clk_mstate_i == M2) begin
          alu_write_accu_o = 1'b1;
          add_read_bus_s   = 1'b1;
        end
      end

      MN_INC:
        case (clk_mstate_i)
          M3: if (!opc_opcode_q[3]) begin
                dm_read_dmem_o       = 1'b1;
                dm_write_dmem_addr_o = 1'b1;
                dm_addr_type_o       = DM_PLAIN;
              end
          M4: if (opc_opcode_q[3:2] != 2'b01) begin
                dm_read_dmem_o     = 1'b1;
                alu_write_shadow_o = 1'b1;
              end
          M5: begin
                alu_op_o       = ALU_INC;
                alu_read_alu_o = 1'b1;
                if (opc_opcode_q[3:2] == 2'b01) alu_write_accu_o = 1'b1;
                else                            dm_write_dmem_s  = 1'b1;
              end
          default: ;
        endcase

      // ---------------------------------------------- conditional jumps
      MN_JBB, MN_JC, MN_JF, MN_JNI, MN_JNIBF, MN_JOBF, MN_JT, MN_JTF, MN_JZ: begin
        assert_psen_s = 1'b1;
        case (mn)
          MN_JBB:   cnd_branch_cond_o = COND_ON_BIT;
          MN_JC:    cnd_branch_cond_o = COND_C;
          MN_JNI:   cnd_branch_cond_o = COND_INT;
          MN_JNIBF: cnd_branch_cond_o = COND_NIBF;
          MN_JOBF:  cnd_branch_cond_o = COND_OBF;
          MN_JT:    cnd_branch_cond_o = opc_opcode_q[6] ? COND_T1 : COND_T0;
          MN_JTF:   cnd_branch_cond_o = COND_TF;
          MN_JZ:    cnd_branch_cond_o = COND_Z;
          default:  ;
        endcase
        if (!clk_second_cycle_i) begin
          if (clk_mstate_i == M3) begin
            cnd_compute_take_o = 1'b1;
            case (mn)
              MN_JBB: alu_read_alu_o = 1'b1;
              MN_JC, MN_JT: cnd_comp_value_o[0] = opc_opcode_q[4];
              MN_JF:  cnd_branch_cond_o = opc_opcode_q[7] ? COND_F0 : COND_F1;
              MN_JTF: jtf_executed_s = 1'b1;
              MN_JZ: begin
                alu_read_alu_o      = 1'b1;
                cnd_comp_value_o[0] = opc_opcode_q[6];
              end
              default: ;
            endcase
          end
        end else if (clk_mstate_i == M1 && cnd_take_branch_i) begin
          pm_write_pcl_o = 1'b1;
          branch_taken_s = 1'b1;
        end
      end

      // ---------------------------------------------------------- jumps
      MN_JMP: begin
        assert_psen_s = 1'b1;
        if (clk_second_cycle_i)
          case (clk_mstate_i)
            M1: begin
                  pm_write_pcl_o = 1'b1;
                  branch_taken_s = 1'b1;
                end
            M2: begin
                  data_s         = {4'b0000, mb_v, opc_opcode_q[7:5]};
                  read_dec_s     = 1'b1;
                  pm_write_pch_o = 1'b1;
                end
            default: ;
          endcase
      end
      MN_JMPP: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i) begin
          if (clk_mstate_i == M3) begin
            alu_read_alu_o = 1'b1;
            pm_addr_type_o = PM_PAGE;
          end
        end else if (clk_mstate_i == M1) begin
          pm_write_pcl_o = 1'b1;
          branch_taken_s = 1'b1;
        end
      end

      // ----------------------------------------------------------- moves
      MN_MOV_A_DATA: begin
        assert_psen_s = 1'b1;
        if (clk_second_cycle_i && clk_mstate_i == M1) alu_write_accu_o = 1'b1;
      end
      MN_MOV_A_RR:
        case (clk_mstate_i)
          M3: if (!opc_opcode_q[3]) begin
                dm_read_dmem_o       = 1'b1;
                dm_write_dmem_addr_o = 1'b1;
                dm_addr_type_o       = DM_PLAIN;
              end
          M4: begin
                dm_read_dmem_o       = 1'b1;
                alu_write_temp_reg_o = 1'b1;
                alu_write_accu_o     = 1'b1;
              end
          default: ;
        endcase
      MN_MOV_A_PSW:
        if (clk_mstate_i == M3) begin
          psw_read_psw_o   = 1'b1;
          psw_read_sp_o    = 1'b1;
          alu_write_accu_o = 1'b1;
        end
      MN_MOV_PSW_A:
        if (clk_mstate_i == M3) begin
          alu_read_alu_o  = 1'b1;
          psw_write_psw_o = 1'b1;
          psw_write_sp_o  = 1'b1;
        end
      MN_MOV_RR:
        case (clk_mstate_i)
          M3: if (!opc_opcode_q[3]) begin
                dm_read_dmem_o       = 1'b1;
                dm_write_dmem_addr_o = 1'b1;
                dm_addr_type_o       = DM_PLAIN;
              end
          M5: begin
                alu_read_alu_o  = 1'b1;
                dm_write_dmem_s = 1'b1;
              end
          default: ;
        endcase
      MN_MOV_RR_DATA: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i && clk_mstate_i == M3 && !opc_opcode_q[3]) begin
          dm_read_dmem_o       = 1'b1;
          dm_write_dmem_addr_o = 1'b1;
          dm_addr_type_o       = DM_PLAIN;
        end
        if (clk_second_cycle_i && clk_mstate_i == M1) dm_write_dmem_s = 1'b1;
      end
      MN_MOV_STS:
        if (clk_mstate_i == M4) begin
          alu_read_alu_o  = 1'b1;
          bus_write_sts_o = 1'b1;
        end
      MN_MOV_T:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[5]) begin
            alu_read_alu_o    = 1'b1;
            tim_write_timer_o = 1'b1;
          end else begin
            tim_read_timer_o = 1'b1;
            alu_write_accu_o = 1'b1;
          end
        end

      // ------------------------------------------------- 8243 expander
      MN_OUTD_PP_A: begin
        clk_assert_prog_o = 1'b1;
        if (!clk_second_cycle_i)
          case (clk_mstate_i)
            M3: begin
                  data_s[7:4] = 4'b0000;
                  data_s[1:0] = opc_opcode_q[1:0];
                  case (opc_opcode_q[7:4])
                    4'b1001: data_s[3:2] = 2'b11;
                    4'b1000: data_s[3:2] = 2'b10;
                    4'b0011: data_s[3:2] = 2'b01;
                    default: ;
                  endcase
                  read_dec_s     = 1'b1;
                  p2_write_exp_o = 1'b1;
                end
            M4: begin
                  p2_output_exp_s = 1'b1;
                  alu_read_alu_o  = 1'b1;
                  p2_write_exp_o  = 1'b1;
                end
            M5: p2_output_exp_s = 1'b1;
            default: ;
          endcase
        else if (clk_mstate_i == M1 || clk_mstate_i == M2)
          p2_output_exp_s = 1'b1;
      end
      MN_MOVD_A_PP: begin
        clk_assert_prog_o = 1'b1;
        if (!clk_second_cycle_i)
          case (clk_mstate_i)
            M3: begin
                  data_s         = {6'b000000, opc_opcode_q[1:0]};
                  read_dec_s     = 1'b1;
                  p2_write_exp_o = 1'b1;
                end
            M4: begin
                  p2_output_exp_s = 1'b1;
                  data_s[3:0]     = 4'b1111;
                  read_dec_s      = 1'b1;
                  p2_write_exp_o  = 1'b1;
                end
            M5: p2_output_exp_s = 1'b1;
            default: ;
          endcase
        else
          case (clk_mstate_i)
            M1: p2_output_exp_s = 1'b1;
            M2: begin
                  p2_read_p2_o     = 1'b1;
                  p2_output_exp_s  = 1'b1;
                  p2_read_exp_o    = 1'b1;
                  alu_write_accu_o = 1'b1;
                end
            default: ;
          endcase
      end

      MN_MOVP: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i) begin
          if (clk_mstate_i == M3) begin
            alu_read_alu_o = 1'b1;
            pm_addr_type_o = opc_opcode_q[6] ? PM_PAGE3 : PM_PAGE;
          end
        end else if (clk_mstate_i == M1) begin
          alu_write_accu_o = 1'b1;
          branch_taken_s   = 1'b1;
        end
      end

      MN_MOVX: begin
        bus_bidir_bus_o = 1'b1;
        if (!opc_opcode_q[4]) clk_assert_rd_o = 1'b1;
        else                  clk_assert_wr_o = 1'b1;
        if (!clk_second_cycle_i) begin
          movx_first_cycle_s = 1'b1;
          case (clk_mstate_i)
            M3: begin
                  dm_read_dmem_o  = 1'b1;
                  bus_write_bus_o = 1'b1;
                end
            M5: if (opc_opcode_q[4]) begin
                  alu_read_alu_o  = 1'b1;
                  bus_write_bus_o = 1'b1;
                end
            default: ;
          endcase
        end else if (clk_mstate_i == M2) begin
          if (!opc_opcode_q[4]) begin
            add_read_bus_s   = 1'b1;
            alu_write_accu_o = 1'b1;
          end else begin
            alu_read_alu_o  = 1'b1;
            bus_write_bus_o = 1'b1;
          end
        end
      end

      MN_OUT_DBB:
        if (clk_mstate_i == M4) begin
          alu_read_alu_o  = 1'b1;
          bus_write_bus_o = 1'b1;
        end
      MN_OUTL_EXT: begin
        if (!opc_opcode_q[4]) clk_assert_wr_o = 1'b1;
        if (!clk_second_cycle_i && clk_mstate_i == M4) begin
          alu_read_alu_o = 1'b1;
          if (opc_opcode_q[4]) begin
            if (!opc_opcode_q[1]) p1_write_p1_o = 1'b1;
            else                  p2_write_p2_o = 1'b1;
          end else
            bus_write_bus_o = 1'b1;
        end
      end
      MN_OUTL_P0:
        if (!clk_second_cycle_i && clk_mstate_i == M4) begin
          alu_read_alu_o = 1'b1;
          p0_write_p0_o  = 1'b1;
        end
      MN_RAD:
        if (clk_second_cycle_i && clk_mstate_i == M3) begin
          adc_read_adc_o   = 1'b1;
          alu_write_accu_o = 1'b1;
        end

      // ----------------------------------------------------------- returns
      MN_RET, MN_RETR, MN_RETI: begin
        if (!clk_second_cycle_i)
          case (clk_mstate_i)
            M3: psw_dec_stackp_o = 1'b1;
            M4: begin
                  psw_read_sp_o        = 1'b1;
                  dm_write_dmem_addr_o = 1'b1;
                  dm_addr_type_o       = DM_STACK;
                end
            M5: begin
                  dm_read_dmem_o       = 1'b1;
                  pm_write_pcl_o       = 1'b1;
                  dm_write_dmem_addr_o = 1'b1;
                  dm_addr_type_o       = DM_STACK_HIGH;
                end
            default: ;
          endcase
        else
          case (clk_mstate_i)
            M1: begin
                  dm_read_dmem_o = 1'b1;
                  pm_write_pch_o = 1'b1;
                  if (mn == MN_RETR) begin
                    psw_write_psw_o = 1'b1;
                    retr_executed_s = 1'b1;
                  end else if (mn == MN_RETI)
                    retr_executed_s = 1'b1;
                end
            M2: begin
                  if (IS_MCS2X && mn == MN_RET) add_inc_pc_s = 1'b1;
                  if (REV2023 == 0) add_write_pmem_addr_s = 1'b1;
                end
            M3: if (REV2023 == 1) add_write_pmem_addr_s = 1'b1;
            default: ;
          endcase
      end

      // ------------------------------------------------------- rotates etc
      MN_RL:
        if (clk_mstate_i == M3) begin
          alu_op_o         = ALU_RL;
          alu_read_alu_o   = 1'b1;
          alu_write_accu_o = 1'b1;
          if (opc_opcode_q[4]) begin
            psw_special_data_o = alu_carry_i;
            psw_write_carry_o  = 1'b1;
          end
        end
      MN_RR:
        if (clk_mstate_i == M3) begin
          alu_op_o         = ALU_RR;
          alu_read_alu_o   = 1'b1;
          alu_write_accu_o = 1'b1;
          if (!opc_opcode_q[4]) begin
            psw_special_data_o = alu_carry_i;
            psw_write_carry_o  = 1'b1;
          end
        end
      MN_SEL_AN:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[4]) adc_sel_an0_o = 1'b1;
          else                 adc_sel_an1_o = 1'b1;
        end
      MN_SEL_MB:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[4]) set_mb_s   = 1'b1;
          else                 clear_mb_s = 1'b1;
        end
      MN_SEL_RB:
        if (clk_mstate_i == M3) begin
          psw_special_data_o = opc_opcode_q[4];
          psw_write_bs_o     = 1'b1;
        end
      MN_STOP_TCNT:
        if (clk_mstate_i == M3) tim_stop_tcnt_o = 1'b1;
      MN_STRT:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[4]) tim_start_t_o   = 1'b1;
          else                 tim_start_cnt_o = 1'b1;
        end
      MN_SWAP: begin
        alu_op_o = ALU_SWAP;
        if (clk_mstate_i == M3) begin
          alu_read_alu_o   = 1'b1;
          alu_write_accu_o = 1'b1;
        end
      end
      MN_XCH:
        case (clk_mstate_i)
          M3: if (!opc_opcode_q[3]) begin
                dm_read_dmem_o       = 1'b1;
                dm_write_dmem_addr_o = 1'b1;
                dm_addr_type_o       = DM_PLAIN;
              end
          M4: begin
                dm_read_dmem_o       = 1'b1;
                alu_write_accu_o     = 1'b1;
                alu_write_temp_reg_o = 1'b1;
                if (opc_opcode_q[4]) alu_accu_low_o = 1'b1;
              end
          M5: begin
                dm_write_dmem_s = 1'b1;
                alu_read_alu_o  = 1'b1;
                if (opc_opcode_q[4]) alu_op_o = ALU_CONCAT;
              end
          default: ;
        endcase
      default: ;
    endcase
  end

  // --------------------------------------------------------------------------
  // decoder registers
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      branch_taken_q <= 1'b0;
      f1_q           <= 1'b0;
      mb_q           <= 1'b0;
      t0_dir_q       <= 1'b0;
      istrobe_res_q  <= 1'b1;
      istrobe_q      <= 1'b0;
      injected_int_q <= 1'b0;
    end else begin
      if (IS_UPI) begin
        if (bus_set_f1_i)        f1_q <= 1'b1;
        else if (bus_clear_f1_i) f1_q <= 1'b0;
      end
      if (en_clk_i) begin
        if (branch_taken_s)      branch_taken_q <= 1'b1;
        else if (clk_mstate_i == M5) branch_taken_q <= 1'b0;
        if (clear_f1_s)          f1_q <= 1'b0;
        else if (cpl_f1_s)       f1_q <= ~f1_q;
        if (clear_mb_s)          mb_q <= 1'b0;
        else if (set_mb_s)       mb_q <= 1'b1;
        if (ent0_clk_s)          t0_dir_q <= 1'b1;
        if (opc_inj_int_s)       injected_int_q <= 1'b1;
        else if (clk_mstate_i == M5 && last_cycle_s) injected_int_q <= 1'b0;
        if (clk_mstate_i == M5 && last_cycle_s) istrobe_res_q <= 1'b0;
      end
      istrobe_q <= clk_mstate_i == M5 && last_cycle_s && !injected_int_q && !istrobe_res_q;
    end

  // adder operand / carry-in selection depends on the mnemonic only: it is observed
  // only in the states where the ALU result or its carries are consumed
  assign alu_use_carry_o = (((mn == MN_ADD || mn == MN_ADD_A_DATA) && opc_opcode_q[4]) ||
                            (mn == MN_RL && opc_opcode_q[4]) || (mn == MN_RR && !opc_opcode_q[4]));
  assign alu_add_inc_o   = mn == MN_INC;
  assign alu_add_dec_o   = mn == MN_DEC || mn == MN_DJNZ;
  assign clk_multi_cycle_o    = opc_multi_cycle_s;
  assign cnd_f1_o             = f1_q;
  assign cnd_tf_o             = timer_flag_q;
  assign data_o               = read_dec_s ? data_s : 8'hFF;
  assign dm_write_dmem_o      = dm_write_dmem_s & en_clk_i;
  assign pm_inc_pc_o          = pm_inc_pc_s | add_inc_pc_s;
  assign pm_write_pmem_addr_o = pm_write_pmem_addr_s | add_write_pmem_addr_s;
  assign t0_dir_o             = t0_dir_q;
  assign bus_read_bus_o       = bus_read_bus_s | add_read_bus_s;
  assign mb_o                 = mb_q;
  assign istrobe_o            = istrobe_q;

  // --------------------------------------------------------------------------
  // interrupt controller ("Interrupt Logic", The Single Component MCS-48 System)
  // --------------------------------------------------------------------------
  always_comb begin
    int_state_s = int_state_q;
    case (int_state_q)
      2'd0:    if (int_in_progress_q && last_cycle_s && clk_mstate_i == M5) int_state_s = 2'd1;
      2'd1:    if (int_executed_s)  int_state_s = 2'd2;
      2'd2:    if (retr_executed_s) int_state_s = 2'd0;
      default: int_state_s = 2'd0;
    endcase
  end

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      timer_flag_q       <= 1'b0;
      timer_overflow_q   <= 1'b0;
      timer_int_enable_q <= 1'b0;
      int_enable_q       <= 1'b0;
      int_type_q         <= 1'b0;
      int_state_q        <= 2'd0;
      int_in_progress_q  <= 1'b0;
    end else if (en_clk_i) begin
      int_state_q <= int_state_s;
      if (jtf_executed_s)      timer_flag_q <= 1'b0;
      else if (tim_overflow_i) timer_flag_q <= 1'b1;
      if ((!int_type_q && int_executed_s) || !timer_int_enable_q) timer_overflow_q <= 1'b0;
      else if (tim_overflow_i) timer_overflow_q <= 1'b1;
      if (dis_tcnti_s)     timer_int_enable_q <= 1'b0;
      else if (en_tcnti_s) timer_int_enable_q <= 1'b1;
      if (dis_i_s)     int_enable_q <= 1'b0;
      else if (en_i_s) int_enable_q <= 1'b1;
      if (retr_executed_s)
        int_in_progress_q <= 1'b0;
      else if ((int_q && int_enable_q) || timer_overflow_q) begin
        int_in_progress_q <= 1'b1;
        if (!int_in_progress_q) int_type_q <= int_q & int_enable_q;
      end
    end

  // INT is sampled at an ALE edge of the last cycle: falling (r295) or rising (2023+)
  always_ff @(posedge xtal_i or negedge res_n_i)
    if (!res_n_i) begin
      int_q <= 1'b0;
      ale_q <= 1'b0;
    end else if (xtal_en_i) begin
      ale_q <= ale_i;
      if (last_cycle_s && ((REV2023 == 1) ? (!ale_q && ale_i) : (ale_q && !ale_i)))
        int_q <= ~int_n_i;
    end

  assign tim_int_s         = ~int_type_q;
  assign int_pending_s     = int_state_q == 2'd1;
  assign int_in_progress_s = int_in_progress_q && int_state_q != 2'd0;

endmodule

// ---------------------------------------------------------------- t48sv_cores.sv
// ============================================================================
// Drop-in replacements for the T48 core entities (same ports and generics)
//   t48sv_t48_core    <- t48_core   (r295 by default: REV2023 = 0)
//   t48sv_upi41_core  <- upi41_core (2023+ release incl. fleet sts_o / IBF ack)
//   t48sv_t21_core    <- t21_core
//   t48sv_t22_core    <- t22_core
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

module t48sv_t48_core #(
  parameter int xtal_div_3_g        = 1,
  parameter int register_mnemonic_g = 1,
  parameter int include_port1_g     = 1,
  parameter int include_port2_g     = 1,
  parameter int include_bus_g       = 1,
  parameter int include_timer_g     = 1,
  parameter int sample_t1_state_g   = 4,
  parameter int REV2023             = 0
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_i,
  input  logic        t0_i,
  output logic        t0_o,
  output logic        t0_dir_o,
  input  logic        int_n_i,
  input  logic        ea_i,
  output logic        rd_n_o,
  output logic        psen_n_o,
  output logic        wr_n_o,
  output logic        ale_o,
  input  logic [7:0]  db_i,
  output logic [7:0]  db_o,
  output logic        db_dir_o,
  input  logic        t1_i,
  input  logic [7:0]  p2_i,
  output logic [7:0]  p2_o,
  output logic        p2l_low_imp_o,
  output logic        p2h_low_imp_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  output logic        p1_low_imp_o,
  output logic        prog_n_o,
  input  logic        clk_i,
  input  logic        en_clk_i,
  output logic        xtal3_o,
  output logic [7:0]  dmem_addr_o,
  output logic        dmem_we_o,
  input  logic [7:0]  dmem_data_i,
  output logic [7:0]  dmem_data_o,
  output logic [11:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i
);

  t48sv_core #(
    .VARIANT(0), .REV2023(REV2023), .XTAL_DIV_3(xtal_div_3_g),
    .REGISTER_MNEMONIC(register_mnemonic_g), .INCLUDE_PORT1(include_port1_g),
    .INCLUDE_PORT2(include_port2_g), .INCLUDE_BUS(include_bus_g),
    .INCLUDE_TIMER(include_timer_g), .SAMPLE_T1_STATE(sample_t1_state_g)
  ) core (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_i), .t0_i(t0_i), .t0_o(t0_o),
    .t0_dir_o(t0_dir_o), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o), .t1_i(t1_i),
    .p2_i(p2_i), .p2_o(p2_o), .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o),
    .p1_i(p1_i), .p1_o(p1_o), .p1_low_imp_o(p1_low_imp_o), .p0_i(8'h00), .p0_o(),
    .prog_n_o(prog_n_o), .clk_i(clk_i), .en_clk_i(en_clk_i), .xtal3_o(xtal3_o),
    .dmem_addr_o(dmem_addr_o), .dmem_we_o(dmem_we_o), .dmem_data_i(dmem_data_i),
    .dmem_data_o(dmem_data_o), .pmem_addr_o(pmem_addr_o), .pmem_data_i(pmem_data_i),
    .cs_n_i(1'b1), .rd_n_i(1'b1), .wr_n_i(1'b1), .a0_i(1'b0), .sts_o(),
    .adc_sel_an_o(), .adc_sh_o(), .adc_sar_o(), .adc_comp_i(1'b0)
  );

endmodule


module t48sv_upi41_core #(
  parameter int xtal_div_3_g        = 1,
  parameter int register_mnemonic_g = 1,
  parameter int sample_t1_state_g   = 4,
  parameter int is_upi_type_a_g     = 1,
  parameter int UPI_IBF_ACK         = 1
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_i,
  input  logic        t0_i,
  input  logic        cs_n_i,
  input  logic        rd_n_i,
  input  logic        a0_i,
  input  logic        wr_n_i,
  output logic        sync_o,
  input  logic [7:0]  db_i,
  output logic [7:0]  db_o,
  output logic [7:0]  sts_o,
  output logic        db_dir_o,
  input  logic        t1_i,
  input  logic [7:0]  p2_i,
  output logic [7:0]  p2_o,
  output logic        p2l_low_imp_o,
  output logic        p2h_low_imp_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  output logic        p1_low_imp_o,
  output logic        prog_n_o,
  input  logic        clk_i,
  input  logic        en_clk_i,
  output logic        xtal3_o,
  output logic [7:0]  dmem_addr_o,
  output logic        dmem_we_o,
  input  logic [7:0]  dmem_data_i,
  output logic [7:0]  dmem_data_o,
  output logic [10:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i
);

  logic [11:0] pmem_addr_s;

  t48sv_core #(
    .VARIANT(1), .UPI_TYPE_A(is_upi_type_a_g), .REV2023(1),
    .UPI_IBF_ACK(UPI_IBF_ACK), .XTAL_DIV_3(xtal_div_3_g), .REGISTER_MNEMONIC(register_mnemonic_g),
    .SAMPLE_T1_STATE(sample_t1_state_g)
  ) core (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_i), .t0_i(t0_i), .t0_o(),
    .t0_dir_o(), .int_n_i(1'b1), .ea_i(1'b0), .rd_n_o(), .psen_n_o(), .wr_n_o(), .ale_o(sync_o),
    .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o), .t1_i(t1_i), .p2_i(p2_i), .p2_o(p2_o),
    .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o), .p1_i(p1_i), .p1_o(p1_o),
    .p1_low_imp_o(p1_low_imp_o), .p0_i(8'h00), .p0_o(), .prog_n_o(prog_n_o), .clk_i(clk_i),
    .en_clk_i(en_clk_i), .xtal3_o(xtal3_o), .dmem_addr_o(dmem_addr_o), .dmem_we_o(dmem_we_o),
    .dmem_data_i(dmem_data_i), .dmem_data_o(dmem_data_o), .pmem_addr_o(pmem_addr_s),
    .pmem_data_i(pmem_data_i), .cs_n_i(cs_n_i), .rd_n_i(rd_n_i), .wr_n_i(wr_n_i), .a0_i(a0_i),
    .sts_o(sts_o), .adc_sel_an_o(), .adc_sh_o(), .adc_sar_o(), .adc_comp_i(1'b0)
  );

  assign pmem_addr_o = pmem_addr_s[10:0];

endmodule


module t48sv_t21_core #(
  parameter int xtal_div_3_g        = 1,
  parameter int register_mnemonic_g = 1,
  parameter int sample_t1_state_g   = 4
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_i,
  output logic        ale_o,
  input  logic        t1_i,
  input  logic [3:0]  p2_i,
  output logic [3:0]  p2_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  input  logic [7:0]  p0_i,
  output logic [7:0]  p0_o,
  output logic        prog_n_o,
  input  logic        clk_i,
  input  logic        en_clk_i,
  output logic        xtal3_o,
  output logic [7:0]  dmem_addr_o,
  output logic        dmem_we_o,
  input  logic [7:0]  dmem_data_i,
  output logic [7:0]  dmem_data_o,
  output logic [11:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i
);

  logic [7:0] p2_s;

  t48sv_core #(
    .VARIANT(2), .REV2023(1), .XTAL_DIV_3(xtal_div_3_g),
    .REGISTER_MNEMONIC(register_mnemonic_g), .SAMPLE_T1_STATE(sample_t1_state_g)
  ) core (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_i), .t0_i(1'b0), .t0_o(), .t0_dir_o(),
    .int_n_i(1'b1), .ea_i(1'b0), .rd_n_o(), .psen_n_o(), .wr_n_o(), .ale_o(ale_o), .db_i(8'h00),
    .db_o(), .db_dir_o(), .t1_i(t1_i), .p2_i({4'h0, p2_i}), .p2_o(p2_s), .p2l_low_imp_o(),
    .p2h_low_imp_o(), .p1_i(p1_i), .p1_o(p1_o), .p1_low_imp_o(), .p0_i(p0_i), .p0_o(p0_o),
    .prog_n_o(prog_n_o), .clk_i(clk_i), .en_clk_i(en_clk_i), .xtal3_o(xtal3_o),
    .dmem_addr_o(dmem_addr_o), .dmem_we_o(dmem_we_o), .dmem_data_i(dmem_data_i),
    .dmem_data_o(dmem_data_o), .pmem_addr_o(pmem_addr_o), .pmem_data_i(pmem_data_i),
    .cs_n_i(1'b1), .rd_n_i(1'b1), .wr_n_i(1'b1), .a0_i(1'b0), .sts_o(),
    .adc_sel_an_o(), .adc_sh_o(), .adc_sar_o(), .adc_comp_i(1'b0)
  );

  assign p2_o = p2_s[3:0];

endmodule


module t48sv_t22_core #(
  parameter int xtal_div_3_g        = 1,
  parameter int register_mnemonic_g = 1,
  parameter int sample_t1_state_g   = 4
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_i,
  output logic        ale_o,
  input  logic        t0_i,
  input  logic        t1_i,
  input  logic [7:0]  p2_i,
  output logic [7:0]  p2_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  input  logic [7:0]  p0_i,
  output logic [7:0]  p0_o,
  output logic        prog_n_o,
  output logic        adc_sel_an_o,
  output logic        adc_sh_o,
  output logic [7:0]  adc_sar_o,
  input  logic        adc_comp_i,
  input  logic        clk_i,
  input  logic        en_clk_i,
  output logic        xtal3_o,
  output logic [7:0]  dmem_addr_o,
  output logic        dmem_we_o,
  input  logic [7:0]  dmem_data_i,
  output logic [7:0]  dmem_data_o,
  output logic [11:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i
);

  t48sv_core #(
    .VARIANT(3), .REV2023(1), .XTAL_DIV_3(xtal_div_3_g),
    .REGISTER_MNEMONIC(register_mnemonic_g), .SAMPLE_T1_STATE(sample_t1_state_g)
  ) core (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_i), .t0_i(t0_i), .t0_o(), .t0_dir_o(),
    .int_n_i(1'b1), .ea_i(1'b0), .rd_n_o(), .psen_n_o(), .wr_n_o(), .ale_o(ale_o), .db_i(8'h00),
    .db_o(), .db_dir_o(), .t1_i(t1_i), .p2_i(p2_i), .p2_o(p2_o), .p2l_low_imp_o(),
    .p2h_low_imp_o(), .p1_i(p1_i), .p1_o(p1_o), .p1_low_imp_o(), .p0_i(p0_i), .p0_o(p0_o),
    .prog_n_o(prog_n_o), .clk_i(clk_i), .en_clk_i(en_clk_i), .xtal3_o(xtal3_o),
    .dmem_addr_o(dmem_addr_o), .dmem_we_o(dmem_we_o), .dmem_data_i(dmem_data_i),
    .dmem_data_o(dmem_data_o), .pmem_addr_o(pmem_addr_o), .pmem_data_i(pmem_data_i),
    .cs_n_i(1'b1), .rd_n_i(1'b1), .wr_n_i(1'b1), .a0_i(1'b0), .sts_o(),
    .adc_sel_an_o(adc_sel_an_o), .adc_sh_o(adc_sh_o), .adc_sar_o(adc_sar_o),
    .adc_comp_i(adc_comp_i)
  );

endmodule


// ----------------------------------------------------------------------------
// Internal data RAM: registered address, unregistered read (generic_ram_ena).
// MLAB by default; "logic" for registers, "M10K" for block RAM. Device RAM powers
// up cleared, so no HDL init (an init would block MLAB inference).
// no_rw_check: en_clk pulses are >= 3 XTAL clocks apart and the address register
// reloads every clock, so same-edge read-during-write is never observed.
// ----------------------------------------------------------------------------
module t48sv_ram #(
  parameter int    AW       = 7,
  parameter        RAMSTYLE = "MLAB, no_rw_check"
) (
  input  logic          clk_i,
  input  logic [AW-1:0] a_i,
  input  logic          we_i,
  input  logic [7:0]    d_i,
  output logic [7:0]    d_o
);

  (* ramstyle = RAMSTYLE *) logic [7:0] mem [0:(1<<AW)-1];
  logic [AW-1:0] a_q;

  always_ff @(posedge clk_i) begin
    if (we_i) mem[a_i] <= d_i;
    a_q <= a_i;
  end

  assign d_o = mem[a_q];

endmodule


// ----------------------------------------------------------------------------
// Internal program ROM (t48_rom / t49_rom / syn_rom): registered address
// ----------------------------------------------------------------------------
module t48sv_rom #(
  parameter int    AW        = 10,
  parameter        INIT_FILE = ""
) (
  input  logic          clk_i,
  input  logic [AW-1:0] a_i,
  output logic [7:0]    d_o
);

  logic [7:0]    rom [0:(1<<AW)-1];
  logic [AW-1:0] a_q;

  initial begin
    for (int i = 0; i < (1<<AW); i++) rom[i] = 8'h00;
    if (INIT_FILE != "") $readmemh(INIT_FILE, rom);
  end

  always_ff @(posedge clk_i) a_q <= a_i;

  assign d_o = rom[a_q];

endmodule

// ---------------------------------------------------------------- t48sv_t8039_notri_extrom.sv
// ============================================================================
// t48sv_t8039_notri_extrom: drop-in for the MiSTer fleet's t8039_notri_extrom
// (fleet derivation of Arnim Laeuger's T48 t8039_notri: program ROM external on
// pmem_addr_o / pmem_data_i, internal RAM 2**ram_addr_width_g bytes:
// 7 = 128 B (8039), 6 = 64 B (8035), 8 = 256 B (8040)). T48 r295 behaviour.
// ============================================================================

module t48sv_t8039_notri_extrom #(
  parameter int    gate_port_input_g = 1,
  parameter int    ram_addr_width_g  = 7,
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_n_i,
  input  logic        t0_i,
  output logic        t0_o,
  output logic        t0_dir_o,
  input  logic        int_n_i,
  input  logic        ea_i,
  output logic        rd_n_o,
  output logic        psen_n_o,
  output logic        wr_n_o,
  output logic        ale_o,
  input  logic [7:0]  db_i,
  output logic [7:0]  db_o,
  output logic        db_dir_o,
  input  logic        t1_i,
  input  logic [7:0]  p2_i,
  output logic [7:0]  p2_o,
  output logic        p2l_low_imp_o,
  output logic        p2h_low_imp_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  output logic        p1_low_imp_o,
  output logic        prog_n_o,
  output logic [11:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i
);

  logic       xtal3_s, dmem_we_s;
  logic [7:0] dmem_addr_s, dmem_data_from_s, dmem_data_to_s;
  logic [7:0] p1_out_s, p2_out_s;

  t48sv_t48_core #(
    .xtal_div_3_g(1), .register_mnemonic_g(1), .include_port1_g(1), .include_port2_g(1),
    .include_bus_g(1), .include_timer_g(1), .sample_t1_state_g(4), .REV2023(0)
  ) t48_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_n_i), .t0_i(t0_i), .t0_o(t0_o),
    .t0_dir_o(t0_dir_o), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o), .t1_i(t1_i),
    .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p1_low_imp_o(p1_low_imp_o), .prog_n_o(prog_n_o), .clk_i(xtal_i), .en_clk_i(xtal3_s),
    .xtal3_o(xtal3_s), .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s),
    .dmem_data_i(dmem_data_from_s), .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_o),
    .pmem_data_i(pmem_data_i)
  );

  assign p1_o = p1_out_s;
  assign p2_o = p2_out_s;

  t48sv_ram #(.AW(ram_addr_width_g), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s[ram_addr_width_g-1:0]), .we_i(dmem_we_s),
    .d_i(dmem_data_to_s), .d_o(dmem_data_from_s)
  );

endmodule

// ---------------------------------------------------------------- t48sv_system.sv
// ============================================================================
// Drop-in replacements for the T48 system tops (system/*_notri.vhd, t8050_wb)
// Same ports and generics as the T48 originals, plus:
//   REV2023       1 = T48 2023+ release behaviour (default), 0 = r295 (fleet)
//   ROM_INIT_FILE $readmemh image for the internal program ROM
//   RAMSTYLE      Quartus ramstyle for the internal data RAM
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

// ----------------------------------------------------------------------------
// MCS-48 (8039 / 8048) system: core + RAM (+ ROM), shared by the drop-ins below
// ----------------------------------------------------------------------------
module t48sv_mcs48_system #(
  parameter int    gate_port_input_g = 1,
  parameter int    ROM_AW            = 0,      // 0: no internal ROM
  parameter int    RAM_AW            = 7,
  parameter int    REV2023           = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       reset_n_i,
  input  logic       t0_i,
  output logic       t0_o,
  output logic       t0_dir_o,
  input  logic       int_n_i,
  input  logic       ea_i,
  output logic       rd_n_o,
  output logic       psen_n_o,
  output logic       wr_n_o,
  output logic       ale_o,
  input  logic [7:0] db_i,
  output logic [7:0] db_o,
  output logic       db_dir_o,
  input  logic       t1_i,
  input  logic [7:0] p2_i,
  output logic [7:0] p2_o,
  output logic       p2l_low_imp_o,
  output logic       p2h_low_imp_o,
  input  logic [7:0] p1_i,
  output logic [7:0] p1_o,
  output logic       p1_low_imp_o,
  output logic       prog_n_o
);

  logic        xtal3_s, dmem_we_s, ea_s;
  logic [7:0]  dmem_addr_s, dmem_data_from_s, dmem_data_to_s, pmem_data_s;
  logic [7:0]  p1_out_s, p2_out_s;
  logic [11:0] pmem_addr_s;

  t48sv_t48_core #(.REV2023(REV2023)) t48_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_n_i), .t0_i(t0_i), .t0_o(t0_o),
    .t0_dir_o(t0_dir_o), .int_n_i(int_n_i), .ea_i(ea_s), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o), .t1_i(t1_i),
    .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p1_low_imp_o(p1_low_imp_o), .prog_n_o(prog_n_o), .clk_i(xtal_i), .en_clk_i(xtal3_s),
    .xtal3_o(xtal3_s), .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s),
    .dmem_data_i(dmem_data_from_s), .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_s),
    .pmem_data_i(pmem_data_s)
  );

  assign p1_o = p1_out_s;
  assign p2_o = p2_out_s;

  generate
    if (ROM_AW > 0) begin : g_rom
      // EA is forced high outside the internal ROM
      if (ROM_AW < 12) begin : g_ea
        assign ea_s = ea_i | (pmem_addr_s[11:ROM_AW] != '0);
      end else begin : g_ea4k
        assign ea_s = ea_i;
      end
      t48sv_rom #(.AW(ROM_AW), .INIT_FILE(ROM_INIT_FILE)) rom_b (
        .clk_i(xtal_i), .a_i(pmem_addr_s[ROM_AW-1:0]), .d_o(pmem_data_s)
      );
    end else begin : g_no_rom
      assign ea_s        = ea_i;
      assign pmem_data_s = 8'h00;
    end
  endgenerate

  t48sv_ram #(.AW(RAM_AW), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s[RAM_AW-1:0]), .we_i(dmem_we_s), .d_i(dmem_data_to_s),
    .d_o(dmem_data_from_s)
  );

endmodule


`define T48SV_MCS48_PORTS \
  input  logic       xtal_i,        \
  input  logic       xtal_en_i,     \
  input  logic       reset_n_i,     \
  input  logic       t0_i,          \
  output logic       t0_o,          \
  output logic       t0_dir_o,      \
  input  logic       int_n_i,       \
  input  logic       ea_i,          \
  output logic       rd_n_o,        \
  output logic       psen_n_o,      \
  output logic       wr_n_o,        \
  output logic       ale_o,         \
  input  logic [7:0] db_i,          \
  output logic [7:0] db_o,          \
  output logic       db_dir_o,      \
  input  logic       t1_i,          \
  input  logic [7:0] p2_i,          \
  output logic [7:0] p2_o,          \
  output logic       p2l_low_imp_o, \
  output logic       p2h_low_imp_o, \
  input  logic [7:0] p1_i,          \
  output logic [7:0] p1_o,          \
  output logic       p1_low_imp_o,  \
  output logic       prog_n_o

`define T48SV_MCS48_CONN \
  .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_n_i(reset_n_i), .t0_i(t0_i), .t0_o(t0_o), \
  .t0_dir_o(t0_dir_o), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o), \
  .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o), .t1_i(t1_i), \
  .p2_i(p2_i), .p2_o(p2_o), .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o), \
  .p1_i(p1_i), .p1_o(p1_o), .p1_low_imp_o(p1_low_imp_o), .prog_n_o(prog_n_o)

module t48sv_t8039_notri #(
  parameter int    gate_port_input_g = 1,
  parameter int    REV2023           = 1,
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_MCS48_PORTS);
  t48sv_mcs48_system #(.gate_port_input_g(gate_port_input_g), .ROM_AW(0), .RAM_AW(7),
                       .REV2023(REV2023), .RAMSTYLE(RAMSTYLE)) sys (`T48SV_MCS48_CONN);
endmodule

module t48sv_t8048_notri #(
  parameter int    gate_port_input_g = 1,
  parameter int    REV2023           = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_MCS48_PORTS);
  t48sv_mcs48_system #(.gate_port_input_g(gate_port_input_g), .ROM_AW(10), .RAM_AW(6),
                       .REV2023(REV2023), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_MCS48_CONN);
endmodule

// 8049 / 8050 class parts: 2K / 4K ROM, 128 / 256 B RAM (no T48 top of their own)
module t48sv_t8049_notri #(
  parameter int    gate_port_input_g = 1,
  parameter int    REV2023           = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_MCS48_PORTS);
  t48sv_mcs48_system #(.gate_port_input_g(gate_port_input_g), .ROM_AW(11), .RAM_AW(7),
                       .REV2023(REV2023), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_MCS48_CONN);
endmodule

module t48sv_t8050_notri #(
  parameter int    gate_port_input_g = 1,
  parameter int    REV2023           = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_MCS48_PORTS);
  t48sv_mcs48_system #(.gate_port_input_g(gate_port_input_g), .ROM_AW(12), .RAM_AW(8),
                       .REV2023(REV2023), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_MCS48_CONN);
endmodule


// ----------------------------------------------------------------------------
// UPI-41 systems: 8041 (1K/64B), 8041A (1K/64B), 8042AH (2K/256B) as in T48
// ----------------------------------------------------------------------------
module t48sv_upi41_system #(
  parameter int    gate_port_input_g = 1,
  parameter int    TYPE_A            = 1,
  parameter int    ROM_AW            = 10,
  parameter int    RAM_AW            = 6,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       reset_n_i,
  input  logic       t0_i,
  input  logic       cs_n_i,
  input  logic       rd_n_i,
  input  logic       a0_i,
  input  logic       wr_n_i,
  output logic       sync_o,
  input  logic [7:0] db_i,
  output logic [7:0] db_o,
  output logic       db_dir_o,
  input  logic       t1_i,
  input  logic [7:0] p2_i,
  output logic [7:0] p2_o,
  output logic       p2l_low_imp_o,
  output logic       p2h_low_imp_o,
  input  logic [7:0] p1_i,
  output logic [7:0] p1_o,
  output logic       p1_low_imp_o,
  output logic       prog_n_o
);

  logic        xtal3_s, dmem_we_s;
  logic [7:0]  dmem_addr_s, dmem_data_from_s, dmem_data_to_s, pmem_data_s;
  logic [7:0]  p1_out_s, p2_out_s;
  logic [10:0] pmem_addr_s;

  t48sv_upi41_core #(.is_upi_type_a_g(TYPE_A)) upi41_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_n_i), .t0_i(t0_i), .cs_n_i(cs_n_i),
    .rd_n_i(rd_n_i), .a0_i(a0_i), .wr_n_i(wr_n_i), .sync_o(sync_o), .db_i(db_i), .db_o(db_o),
    .sts_o(), .db_dir_o(db_dir_o), .t1_i(t1_i),
    .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p1_low_imp_o(p1_low_imp_o), .prog_n_o(prog_n_o), .clk_i(xtal_i), .en_clk_i(xtal3_s),
    .xtal3_o(xtal3_s), .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s),
    .dmem_data_i(dmem_data_from_s), .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_s),
    .pmem_data_i(pmem_data_s)
  );

  assign p1_o = p1_out_s;
  assign p2_o = p2_out_s;

  t48sv_rom #(.AW(ROM_AW), .INIT_FILE(ROM_INIT_FILE)) rom_b (
    .clk_i(xtal_i), .a_i(pmem_addr_s[ROM_AW-1:0]), .d_o(pmem_data_s)
  );

  t48sv_ram #(.AW(RAM_AW), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s[RAM_AW-1:0]), .we_i(dmem_we_s), .d_i(dmem_data_to_s),
    .d_o(dmem_data_from_s)
  );

endmodule


`define T48SV_UPI41_PORTS \
  input  logic       xtal_i,        \
  input  logic       xtal_en_i,     \
  input  logic       reset_n_i,     \
  input  logic       t0_i,          \
  input  logic       cs_n_i,        \
  input  logic       rd_n_i,        \
  input  logic       a0_i,          \
  input  logic       wr_n_i,        \
  output logic       sync_o,        \
  input  logic [7:0] db_i,          \
  output logic [7:0] db_o,          \
  output logic       db_dir_o,      \
  input  logic       t1_i,          \
  input  logic [7:0] p2_i,          \
  output logic [7:0] p2_o,          \
  output logic       p2l_low_imp_o, \
  output logic       p2h_low_imp_o, \
  input  logic [7:0] p1_i,          \
  output logic [7:0] p1_o,          \
  output logic       p1_low_imp_o,  \
  output logic       prog_n_o

`define T48SV_UPI41_CONN \
  .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_n_i(reset_n_i), .t0_i(t0_i), .cs_n_i(cs_n_i), \
  .rd_n_i(rd_n_i), .a0_i(a0_i), .wr_n_i(wr_n_i), .sync_o(sync_o), .db_i(db_i), .db_o(db_o), \
  .db_dir_o(db_dir_o), .t1_i(t1_i), .p2_i(p2_i), .p2_o(p2_o), .p2l_low_imp_o(p2l_low_imp_o), \
  .p2h_low_imp_o(p2h_low_imp_o), .p1_i(p1_i), .p1_o(p1_o), .p1_low_imp_o(p1_low_imp_o), \
  .prog_n_o(prog_n_o)

module t48sv_t8041_notri #(
  parameter int    gate_port_input_g = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_UPI41_PORTS);
  t48sv_upi41_system #(.gate_port_input_g(gate_port_input_g), .TYPE_A(0), .ROM_AW(10),
                       .RAM_AW(6), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_UPI41_CONN);
endmodule

module t48sv_t8041a_notri #(
  parameter int    gate_port_input_g = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_UPI41_PORTS);
  t48sv_upi41_system #(.gate_port_input_g(gate_port_input_g), .TYPE_A(1), .ROM_AW(10),
                       .RAM_AW(6), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_UPI41_CONN);
endmodule

module t48sv_t8042ah_notri #(
  parameter int    gate_port_input_g = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_UPI41_PORTS);
  t48sv_upi41_system #(.gate_port_input_g(gate_port_input_g), .TYPE_A(1), .ROM_AW(11),
                       .RAM_AW(8), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_UPI41_CONN);
endmodule


// ----------------------------------------------------------------------------
// 8021 (1K / 64 B, 4-bit P2) and 8022 (2K / 64 B, A/D on AN0 / AN1)
// ----------------------------------------------------------------------------
module t48sv_t8021_notri #(
  parameter int    gate_port_input_g = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       reset_i,
  output logic       ale_o,
  input  logic       t1_i,
  input  logic [3:0] p2_i,
  output logic [3:0] p2_o,
  input  logic [7:0] p1_i,
  output logic [7:0] p1_o,
  input  logic [7:0] p0_i,
  output logic [7:0] p0_o,
  output logic       prog_n_o
);

  logic        xtal3_s, dmem_we_s;
  logic [7:0]  dmem_addr_s, dmem_data_from_s, dmem_data_to_s, pmem_data_s;
  logic [7:0]  p0_out_s, p1_out_s;
  logic [3:0]  p2_out_s;
  logic [11:0] pmem_addr_s;

  // RESET is active high on the 8021 / 8022
  t48sv_t21_core t21_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(~reset_i), .ale_o(ale_o), .t1_i(t1_i),
    .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p0_i((gate_port_input_g == 1) ? (p0_i & p0_out_s) : p0_i), .p0_o(p0_out_s),
    .prog_n_o(prog_n_o), .clk_i(xtal_i), .en_clk_i(xtal3_s), .xtal3_o(xtal3_s),
    .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s), .dmem_data_i(dmem_data_from_s),
    .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_s), .pmem_data_i(pmem_data_s)
  );

  assign p0_o = p0_out_s;
  assign p1_o = p1_out_s;
  assign p2_o = p2_out_s;

  t48sv_rom #(.AW(10), .INIT_FILE(ROM_INIT_FILE)) rom_b (
    .clk_i(xtal_i), .a_i(pmem_addr_s[9:0]), .d_o(pmem_data_s)
  );

  t48sv_ram #(.AW(6), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s[5:0]), .we_i(dmem_we_s), .d_i(dmem_data_to_s),
    .d_o(dmem_data_from_s)
  );

endmodule

module t48sv_t8022_notri #(
  parameter int    gate_port_input_g = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       reset_i,
  input  logic       t0_i,
  output logic       ale_o,
  input  logic       t1_i,
  input  logic [7:0] p2_i,
  output logic [7:0] p2_o,
  input  logic [7:0] p1_i,
  output logic [7:0] p1_o,
  input  logic [7:0] p0_i,
  output logic [7:0] p0_o,
  output logic       prog_n_o,
  input  logic [7:0] an0_i,
  input  logic [7:0] an1_i
);

  logic        xtal3_s, dmem_we_s;
  logic [7:0]  dmem_addr_s, dmem_data_from_s, dmem_data_to_s, pmem_data_s;
  logic [7:0]  p0_out_s, p1_out_s, p2_out_s;
  logic [11:0] pmem_addr_s;
  logic        adc_sel_an_s, adc_sh_s, adc_comp_s;
  logic [7:0]  adc_sar_s, an_q;

  t48sv_t22_core t22_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(~reset_i), .ale_o(ale_o), .t0_i(t0_i),
    .t1_i(t1_i), .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p0_i((gate_port_input_g == 1) ? (p0_i & p0_out_s) : p0_i), .p0_o(p0_out_s),
    .prog_n_o(prog_n_o), .adc_sel_an_o(adc_sel_an_s), .adc_sh_o(adc_sh_s),
    .adc_sar_o(adc_sar_s), .adc_comp_i(adc_comp_s), .clk_i(xtal_i), .en_clk_i(xtal3_s),
    .xtal3_o(xtal3_s), .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s),
    .dmem_data_i(dmem_data_from_s), .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_s),
    .pmem_data_i(pmem_data_s)
  );

  assign p0_o = p0_out_s;
  assign p1_o = p1_out_s;
  assign p2_o = p2_out_s;

  // sample & hold plus comparator of the analog front end (no reset, as in T48)
  always_ff @(posedge xtal_i)
    if (adc_sh_s) an_q <= adc_sel_an_s ? an1_i : an0_i;
  assign adc_comp_s = an_q >= adc_sar_s;

  t48sv_rom #(.AW(11), .INIT_FILE(ROM_INIT_FILE)) rom_b (
    .clk_i(xtal_i), .a_i(pmem_addr_s[10:0]), .d_o(pmem_data_s)
  );

  t48sv_ram #(.AW(6), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s[5:0]), .we_i(dmem_we_s), .d_i(dmem_data_to_s),
    .d_o(dmem_data_from_s)
  );

endmodule


// ----------------------------------------------------------------------------
// t8050_wb: 8050 (4K / 256 B) with a Wishbone master on the BUS port
// ----------------------------------------------------------------------------
module t48sv_t8050_wb #(
  parameter int    gate_port_input_g = 1,
  parameter int    REV2023           = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic        xtal_i,
  input  logic        reset_n_i,
  input  logic        t0_i,
  output logic        t0_o,
  output logic        t0_dir_o,
  input  logic        int_n_i,
  input  logic        ea_i,
  output logic        rd_n_o,
  output logic        psen_n_o,
  output logic        wr_n_o,
  output logic        ale_o,
  input  logic        t1_i,
  input  logic [7:0]  p2_i,
  output logic [7:0]  p2_o,
  output logic        p2l_low_imp_o,
  output logic        p2h_low_imp_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  output logic        p1_low_imp_o,
  output logic        prog_n_o,
  output logic        wb_cyc_o,
  output logic        wb_stb_o,
  output logic        wb_we_o,
  output logic [23:0] wb_adr_o,
  input  logic        wb_ack_i,
  input  logic [7:0]  wb_dat_i,
  output logic [7:0]  wb_dat_o
);

  logic        xtal3_s, dmem_we_s, ale_s, wr_n_s, rd_n_s, xtal_en_s;
  logic [7:0]  dmem_addr_s, dmem_data_from_s, dmem_data_to_s, pmem_data_s;
  logic [7:0]  p1_out_s, p2_out_s, db_to_t48, db_from_t48, wb_dat_q;
  logic [11:0] pmem_addr_s;
  logic [23:0] adr_q;
  logic [1:0]  state_q;     // 0 idle, 1 cycle, 2 wait for RD / WR inactive
  logic        sel_adr1_s, sel_adr2_s, sel_wb_s, wr_s, rd_s;

  t48sv_t48_core #(.REV2023(REV2023)) t48_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_s), .reset_i(reset_n_i), .t0_i(t0_i), .t0_o(t0_o),
    .t0_dir_o(t0_dir_o), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_s), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_s), .ale_o(ale_s), .db_i(db_to_t48), .db_o(db_from_t48), .db_dir_o(),
    .t1_i(t1_i), .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p1_low_imp_o(p1_low_imp_o), .prog_n_o(prog_n_o), .clk_i(xtal_i), .en_clk_i(xtal3_s),
    .xtal3_o(xtal3_s), .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s),
    .dmem_data_i(dmem_data_from_s), .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_s),
    .pmem_data_i(pmem_data_s)
  );

  assign p1_o   = p1_out_s;
  assign p2_o   = p2_out_s;
  assign ale_o  = ale_s;
  assign wr_n_o = wr_n_s;
  assign rd_n_o = rd_n_s;

  // Wishbone master (t48_wb_master): P2.4 = 1 selects the address registers
  assign sel_adr1_s = p2_out_s[4] && adr_q[7:0] == 8'h00;
  assign sel_adr2_s = p2_out_s[4] && adr_q[7:0] == 8'h01;
  assign sel_wb_s   = !p2_out_s[4];
  assign wr_s       = !wr_n_s;
  assign rd_s       = !rd_n_s;

  always_ff @(posedge xtal_i or negedge reset_n_i)
    if (!reset_n_i) begin
      adr_q    <= 24'h000000;
      wb_dat_q <= 8'h00;
      state_q  <= 2'd0;
    end else begin
      if (ale_s)               adr_q[7:0]   <= db_from_t48;
      if (wr_s && sel_adr1_s)  adr_q[15:8]  <= db_from_t48;
      if (wr_s && sel_adr2_s)  adr_q[23:16] <= db_from_t48;
      if (wb_ack_i)            wb_dat_q     <= wb_dat_i;
      case (state_q)
        2'd0:    state_q <= (sel_wb_s && (wr_s || rd_s)) ? 2'd1 : 2'd0;
        2'd1:    state_q <= wb_ack_i ? 2'd2 : 2'd1;
        2'd2:    state_q <= (!wr_s && !rd_s) ? 2'd0 : 2'd2;
        default: state_q <= 2'd0;
      endcase
    end

  assign wb_cyc_o  = state_q == 2'd1;
  assign wb_stb_o  = state_q == 2'd1;
  assign xtal_en_s = state_q != 2'd1;
  assign db_to_t48 = sel_adr1_s ? adr_q[15:8] : sel_adr2_s ? adr_q[23:16] : wb_dat_q;
  assign wb_adr_o  = adr_q;
  assign wb_dat_o  = db_from_t48;
  assign wb_we_o   = wr_s && sel_wb_s;

  t48sv_rom #(.AW(12), .INIT_FILE(ROM_INIT_FILE)) rom_b (
    .clk_i(xtal_i), .a_i(pmem_addr_s), .d_o(pmem_data_s)
  );

  t48sv_ram #(.AW(8), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s), .we_i(dmem_we_s), .d_i(dmem_data_to_s),
    .d_o(dmem_data_from_s)
  );

endmodule

// ---------------------------------------------------------------- t48sv_tri.sv
// ============================================================================
// Pin-level tri-state tops (T48 system/t80xx.vhd): quasi-bidirectional ports
// drive strongly only in the low-impedance phase or when 0, otherwise float to
// the external pull-up; BUS / T0 are driven while their direction bit is set.
// For FPGA-internal use prefer the *_notri tops.
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

// quasi-bidirectional pin: strong while low-impedance or 0, else pulled up
// Quartus 17: module-level generate loops need generate / endgenerate and a literal bound (w = pin width).
`define T48SV_QB(pin, val, limp, lbl, w) \
  generate for (qb = 0; qb < w; qb = qb + 1) begin : lbl \
    assign pin[qb] = (limp || !val[qb]) ? val[qb] : 1'bz; \
  end endgenerate

module t48sv_t8039 (
  input  logic       xtal_i,
  input  logic       reset_n_i,
  inout  wire        t0_b,
  input  logic       int_n_i,
  input  logic       ea_i,
  output logic       rd_n_o,
  output logic       psen_n_o,
  output logic       wr_n_o,
  output logic       ale_o,
  inout  wire  [7:0] db_b,
  input  logic       t1_i,
  inout  wire  [7:0] p2_b,
  inout  wire  [7:0] p1_b,
  output logic       prog_n_o
);
  genvar qb;
  logic       t0_s, t0_dir_s, db_dir_s, p1_limp_s, p2l_limp_s, p2h_limp_s;
  logic [7:0] db_s, p1_s, p2_s;

  t48sv_t8039_notri #(.gate_port_input_g(0)) t8039_notri_b (
    .xtal_i(xtal_i), .xtal_en_i(1'b1), .reset_n_i(reset_n_i), .t0_i(t0_b), .t0_o(t0_s),
    .t0_dir_o(t0_dir_s), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_b), .db_o(db_s), .db_dir_o(db_dir_s), .t1_i(t1_i),
    .p2_i(p2_b), .p2_o(p2_s), .p2l_low_imp_o(p2l_limp_s), .p2h_low_imp_o(p2h_limp_s),
    .p1_i(p1_b), .p1_o(p1_s), .p1_low_imp_o(p1_limp_s), .prog_n_o(prog_n_o)
  );

  assign t0_b = t0_dir_s ? t0_s : 1'bz;
  assign db_b = db_dir_s ? db_s : 8'hzz;
  `T48SV_QB(p1_b, p1_s, p1_limp_s, g_p1_b, 8)
  generate for (qb = 0; qb < 8; qb = qb + 1) begin : g_p2_b
    assign p2_b[qb] = ((qb < 4 ? p2l_limp_s : p2h_limp_s) || !p2_s[qb]) ? p2_s[qb] : 1'bz;
  end endgenerate
endmodule

module t48sv_t8048 #(
  parameter        ROM_INIT_FILE = ""
) (
  input  logic       xtal_i,
  input  logic       reset_n_i,
  inout  wire        t0_b,
  input  logic       int_n_i,
  input  logic       ea_i,
  output logic       rd_n_o,
  output logic       psen_n_o,
  output logic       wr_n_o,
  output logic       ale_o,
  inout  wire  [7:0] db_b,
  input  logic       t1_i,
  inout  wire  [7:0] p2_b,
  inout  wire  [7:0] p1_b,
  output logic       prog_n_o
);
  genvar qb;
  logic       t0_s, t0_dir_s, db_dir_s, p1_limp_s, p2l_limp_s, p2h_limp_s;
  logic [7:0] db_s, p1_s, p2_s;

  t48sv_t8048_notri #(.gate_port_input_g(0), .ROM_INIT_FILE(ROM_INIT_FILE)) t8048_notri_b (
    .xtal_i(xtal_i), .xtal_en_i(1'b1), .reset_n_i(reset_n_i), .t0_i(t0_b), .t0_o(t0_s),
    .t0_dir_o(t0_dir_s), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_b), .db_o(db_s), .db_dir_o(db_dir_s), .t1_i(t1_i),
    .p2_i(p2_b), .p2_o(p2_s), .p2l_low_imp_o(p2l_limp_s), .p2h_low_imp_o(p2h_limp_s),
    .p1_i(p1_b), .p1_o(p1_s), .p1_low_imp_o(p1_limp_s), .prog_n_o(prog_n_o)
  );

  assign t0_b = t0_dir_s ? t0_s : 1'bz;
  assign db_b = db_dir_s ? db_s : 8'hzz;
  `T48SV_QB(p1_b, p1_s, p1_limp_s, g_p1_b, 8)
  generate for (qb = 0; qb < 8; qb = qb + 1) begin : g_p2_b
    assign p2_b[qb] = ((qb < 4 ? p2l_limp_s : p2h_limp_s) || !p2_s[qb]) ? p2_s[qb] : 1'bz;
  end endgenerate
endmodule

// UPI-41 family pin tops: 0 = 8041, 1 = 8041A, 2 = 8042AH
`define T48SV_UPI_TRI(name, notri) \
module name #( \
  parameter        ROM_INIT_FILE = "" \
) ( \
  input  logic       xtal_i, \
  input  logic       reset_n_i, \
  input  logic       t0_i, \
  input  logic       cs_n_i, \
  input  logic       rd_n_i, \
  input  logic       a0_i, \
  input  logic       wr_n_i, \
  output logic       sync_o, \
  inout  wire  [7:0] db_b, \
  input  logic       t1_i, \
  inout  wire  [7:0] p2_b, \
  inout  wire  [7:0] p1_b, \
  output logic       prog_n_o \
); \
  genvar qb; \
  logic       db_dir_s, p1_limp_s, p2l_limp_s, p2h_limp_s; \
  logic [7:0] db_s, p1_s, p2_s; \
  notri #(.gate_port_input_g(0), .ROM_INIT_FILE(ROM_INIT_FILE)) notri_b ( \
    .xtal_i(xtal_i), .xtal_en_i(1'b1), .reset_n_i(reset_n_i), .t0_i(t0_i), .cs_n_i(cs_n_i), \
    .rd_n_i(rd_n_i), .a0_i(a0_i), .wr_n_i(wr_n_i), .sync_o(sync_o), .db_i(db_b), .db_o(db_s), \
    .db_dir_o(db_dir_s), .t1_i(t1_i), .p2_i(p2_b), .p2_o(p2_s), .p2l_low_imp_o(p2l_limp_s), \
    .p2h_low_imp_o(p2h_limp_s), .p1_i(p1_b), .p1_o(p1_s), .p1_low_imp_o(p1_limp_s), \
    .prog_n_o(prog_n_o) \
  ); \
  assign db_b = db_dir_s ? db_s : 8'hzz; \
  `T48SV_QB(p1_b, p1_s, p1_limp_s, g_p1_b, 8) \
  generate for (qb = 0; qb < 8; qb = qb + 1) begin : g_p2_b \
    assign p2_b[qb] = ((qb < 4 ? p2l_limp_s : p2h_limp_s) || !p2_s[qb]) ? p2_s[qb] : 1'bz; \
  end endgenerate \
endmodule

`T48SV_UPI_TRI(t48sv_t8041, t48sv_t8041_notri)
`T48SV_UPI_TRI(t48sv_t8041a, t48sv_t8041a_notri)
`T48SV_UPI_TRI(t48sv_t8042ah, t48sv_t8042ah_notri)

module t48sv_t8021 #(
  parameter        ROM_INIT_FILE = ""
) (
  input  logic       xtal_i,
  input  logic       reset_i,
  output logic       ale_o,
  input  logic       t1_i,
  inout  wire  [3:0] p2_b,
  inout  wire  [7:0] p1_b,
  inout  wire  [7:0] p0_b,
  output logic       prog_n_o
);
  genvar qb;
  logic [3:0] p2_s;
  logic [7:0] p1_s, p0_s;

  t48sv_t8021_notri #(.gate_port_input_g(0), .ROM_INIT_FILE(ROM_INIT_FILE)) t8021_notri_b (
    .xtal_i(xtal_i), .xtal_en_i(1'b1), .reset_i(reset_i), .ale_o(ale_o), .t1_i(t1_i),
    .p2_i(p2_b), .p2_o(p2_s), .p1_i(p1_b), .p1_o(p1_s), .p0_i(p0_b), .p0_o(p0_s),
    .prog_n_o(prog_n_o)
  );

  // T48 drives the 8021 ports open-drain only (no low-impedance phase)
  `T48SV_QB(p2_b, p2_s, 1'b0, g_p2_b, 4)
  `T48SV_QB(p1_b, p1_s, 1'b0, g_p1_b, 8)
  `T48SV_QB(p0_b, p0_s, 1'b0, g_p0_b, 8)
endmodule

module t48sv_t8022 #(
  parameter        ROM_INIT_FILE = ""
) (
  input  logic       xtal_i,
  input  logic       reset_i,
  input  logic       t0_i,
  output logic       ale_o,
  input  logic       t1_i,
  inout  wire  [7:0] p2_b,
  inout  wire  [7:0] p1_b,
  inout  wire  [7:0] p0_b,
  output logic       prog_n_o,
  input  logic [7:0] an0_i,
  input  logic [7:0] an1_i
);
  genvar qb;
  logic [7:0] p2_s, p1_s, p0_s;

  t48sv_t8022_notri #(.gate_port_input_g(0), .ROM_INIT_FILE(ROM_INIT_FILE)) t8022_notri_b (
    .xtal_i(xtal_i), .xtal_en_i(1'b1), .reset_i(reset_i), .t0_i(t0_i), .ale_o(ale_o),
    .t1_i(t1_i), .p2_i(p2_b), .p2_o(p2_s), .p1_i(p1_b), .p1_o(p1_s), .p0_i(p0_b), .p0_o(p0_s),
    .prog_n_o(prog_n_o), .an0_i(an0_i), .an1_i(an1_i)
  );

  `T48SV_QB(p2_b, p2_s, 1'b0, g_p2_b, 8)
  `T48SV_QB(p1_b, p1_s, 1'b0, g_p1_b, 8)
  `T48SV_QB(p0_b, p0_s, 1'b0, g_p0_b, 8)
endmodule

// ---------------------------------------------------------------- t48sv_t8243.sv
// ============================================================================
// t48sv 8243 I/O expander (T48 t8243 by Arnim Laeuger; attribution in t48sv_core.sv)
//   t48sv_t8243_core         generic core, CLK_FALL_LEVEL selects the edge of the
//                            instruction-latch register (1: rising, 0: falling)
//   t48sv_t8243_sync_notri   synchronous version: PROG edges become enables
//   t48sv_t8243_async_notri  PROG itself is the clock (as the real 8243)
//   t48sv_t8243              pin-compatible tri-state version
// T48 leaves P2 / port data undefined ('-') where unselected; t48sv drives 0.
// ============================================================================

module t48sv_t8243_core #(
  parameter int clk_fall_level_g = 0
) (
  input  logic       clk_i,
  input  logic       clk_rise_en_i,
  input  logic       clk_fall_en_i,
  input  logic       reset_n_i,
  input  logic       cs_n_i,
  input  logic       prog_n_i,
  input  logic [3:0] p2_i,
  output logic [3:0] p2_o,
  output logic       p2_en_o,
  input  logic [3:0] p4_i,
  output logic [3:0] p4_o,
  output logic       p4_en_o,
  input  logic [3:0] p5_i,
  output logic [3:0] p5_o,
  output logic       p5_en_o,
  input  logic [3:0] p6_i,
  output logic [3:0] p6_o,
  output logic       p6_en_o,
  input  logic [3:0] p7_i,
  output logic [3:0] p7_o,
  output logic       p7_en_o
);

  // instruction: 0 read, 1 write, 2 ORLD, 3 ANLD (= P2[3:2] at the PROG falling edge)
  logic [1:0] instr_q;
  logic [3:0] sel_q, en_q;          // one-hot port 4..7
  logic       p2_en_q;
  logic [3:0] latch_q [0:3];
  logic [3:0] port_v, data_s;

  generate
    if (clk_fall_level_g == 1) begin : g_rise
      always_ff @(posedge clk_i or posedge cs_n_i)
        if (cs_n_i) begin
          sel_q   <= 4'b0000;
          p2_en_q <= 1'b0;
          instr_q <= 2'd1;
        end else if (clk_fall_en_i) begin
          sel_q   <= 4'b0001 << p2_i[1:0];
          p2_en_q <= p2_i[3:2] == 2'b00;
          instr_q <= p2_i[3:2];
        end
    end else begin : g_fall
      always_ff @(negedge clk_i or posedge cs_n_i)
        if (cs_n_i) begin
          sel_q   <= 4'b0000;
          p2_en_q <= 1'b0;
          instr_q <= 2'd1;
        end else if (clk_fall_en_i) begin
          sel_q   <= 4'b0001 << p2_i[1:0];
          p2_en_q <= p2_i[3:2] == 2'b00;
          instr_q <= p2_i[3:2];
        end
    end
  endgenerate

  always_ff @(posedge clk_i or negedge reset_n_i)
    if (!reset_n_i) begin
      en_q       <= 4'b0000;
      latch_q[0] <= 4'h0;
      latch_q[1] <= 4'h0;
      latch_q[2] <= 4'h0;
      latch_q[3] <= 4'h0;
    end else if (!cs_n_i && clk_rise_en_i) begin
      for (int i = 0; i < 4; i++)
        if (sel_q[i]) begin
          en_q[i] <= instr_q != 2'd0;
          if (instr_q != 2'd0) latch_q[i] <= data_s;
        end
    end

  always_comb begin
    case (sel_q)
      4'b0001: begin port_v = latch_q[0]; p2_o = p4_i; end
      4'b0010: begin port_v = latch_q[1]; p2_o = p5_i; end
      4'b0100: begin port_v = latch_q[2]; p2_o = p6_i; end
      4'b1000: begin port_v = latch_q[3]; p2_o = p7_i; end
      default: begin port_v = 4'h0;       p2_o = 4'h0; end
    endcase
    case (instr_q)
      2'd1:    data_s = p2_i;
      2'd2:    data_s = p2_i | port_v;
      2'd3:    data_s = p2_i & port_v;
      default: data_s = 4'h0;
    endcase
  end

  assign p2_en_o = !cs_n_i && !prog_n_i && p2_en_q;
  assign p4_o    = latch_q[0];
  assign p5_o    = latch_q[1];
  assign p6_o    = latch_q[2];
  assign p7_o    = latch_q[3];
  assign p4_en_o = en_q[0];
  assign p5_en_o = en_q[1];
  assign p6_en_o = en_q[2];
  assign p7_en_o = en_q[3];

endmodule


`define T48SV_8243_PORTS \
  input  logic       cs_n_i,   \
  input  logic       prog_n_i, \
  input  logic [3:0] p2_i,     \
  output logic [3:0] p2_o,     \
  output logic       p2_en_o,  \
  input  logic [3:0] p4_i,     \
  output logic [3:0] p4_o,     \
  output logic       p4_en_o,  \
  input  logic [3:0] p5_i,     \
  output logic [3:0] p5_o,     \
  output logic       p5_en_o,  \
  input  logic [3:0] p6_i,     \
  output logic [3:0] p6_o,     \
  output logic       p6_en_o,  \
  input  logic [3:0] p7_i,     \
  output logic [3:0] p7_o,     \
  output logic       p7_en_o

`define T48SV_8243_CONN \
  .cs_n_i(cs_n_i), .prog_n_i(prog_n_i), .p2_i(p2_i), .p2_o(p2_o), .p2_en_o(p2_en_o), \
  .p4_i(p4_i), .p4_o(p4_o), .p4_en_o(p4_en_o), .p5_i(p5_i), .p5_o(p5_o), .p5_en_o(p5_en_o), \
  .p6_i(p6_i), .p6_o(p6_o), .p6_en_o(p6_en_o), .p7_i(p7_i), .p7_o(p7_o), .p7_en_o(p7_en_o)

module t48sv_t8243_sync_notri (
  input  logic clk_i,
  input  logic clk_en_i,
  input  logic reset_n_i,
  `T48SV_8243_PORTS
);
  logic prog_n_q;

  always_ff @(posedge clk_i or negedge reset_n_i)
    if (!reset_n_i)    prog_n_q <= 1'b1;
    else if (clk_en_i) prog_n_q <= prog_n_i;

  t48sv_t8243_core #(.clk_fall_level_g(1)) t8243_core_b (
    .clk_i(clk_i), .clk_rise_en_i(clk_en_i & ~prog_n_q & prog_n_i),
    .clk_fall_en_i(clk_en_i & prog_n_q & ~prog_n_i), .reset_n_i(reset_n_i), `T48SV_8243_CONN
  );
endmodule

module t48sv_t8243_async_notri (
  input  logic reset_n_i,
  `T48SV_8243_PORTS
);
  t48sv_t8243_core #(.clk_fall_level_g(0)) t8243_core_b (
    .clk_i(prog_n_i), .clk_rise_en_i(1'b1), .clk_fall_en_i(1'b1), .reset_n_i(reset_n_i),
    `T48SV_8243_CONN
  );
endmodule

module t48sv_t8243 (
  input  logic       cs_n_i,
  input  logic       prog_n_i,
  inout  wire  [3:0] p2_b,
  inout  wire  [3:0] p4_b,
  inout  wire  [3:0] p5_b,
  inout  wire  [3:0] p6_b,
  inout  wire  [3:0] p7_b
);
  logic [3:0] p2_s, p4_s, p5_s, p6_s, p7_s;
  logic       p2_en_s, p4_en_s, p5_en_s, p6_en_s, p7_en_s;

  t48sv_t8243_async_notri t8243_async_notri_b (
    .reset_n_i(1'b1), .cs_n_i(cs_n_i), .prog_n_i(prog_n_i),
    .p2_i(p2_b), .p2_o(p2_s), .p2_en_o(p2_en_s), .p4_i(p4_b), .p4_o(p4_s), .p4_en_o(p4_en_s),
    .p5_i(p5_b), .p5_o(p5_s), .p5_en_o(p5_en_s), .p6_i(p6_b), .p6_o(p6_s), .p6_en_o(p6_en_s),
    .p7_i(p7_b), .p7_o(p7_s), .p7_en_o(p7_en_s)
  );

  assign p2_b = p2_en_s ? p2_s : 4'bzzzz;
  assign p4_b = p4_en_s ? p4_s : 4'bzzzz;
  assign p5_b = p5_en_s ? p5_s : 4'bzzzz;
  assign p6_b = p6_en_s ? p6_s : 4'bzzzz;
  assign p7_b = p7_en_s ? p7_s : 4'bzzzz;
endmodule

