// fwd.sv — EX operand forwarding plus IF/ID read forwarding for next cycle.
`default_nettype none
module fwd (
  input  logic        idex_valid,
  input  logic        ce_br,
  input  logic        ce_jalr,
  input  logic        ce_opi,
  input  logic        ce_op,
  input  logic        ce_csr,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic        ce_m,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic        ld_ok,
  input  logic        st_ok,
`ifndef FPGA
  input  logic        ce_amo,
`endif
  input  logic [4:0]  ce_rs1,
  input  logic [4:0]  ce_rs2,
  input  logic [31:0] idex_r1,
  input  logic [31:0] idex_r2,
  input  logic        exmem_valid,
  input  logic [4:0]  exmem_rd,
  input  logic        exmem_wben,
  input  logic        exmem_ld,
  input  logic        exmem_st,
  input  logic        exmem_stop,
  input  logic [31:0] exmem_result,
  input  logic        mwb_valid,
  input  logic [4:0]  mwb_rd,
  input  logic        mwb_wben,
  input  logic [31:0] mwb_wv,
  input  logic        ifid_valid,
  input  logic [31:0] ifid_r1,
  input  logic [31:0] ifid_r2,
  input  logic        ceif_br,
  input  logic        ceif_jalr,
  input  logic        ceif_ld,
  input  logic        ceif_st,
  input  logic        ceif_opi,
  input  logic        ceif_op,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic        ceif_m,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic        ceif_csr,
`ifndef FPGA
  input  logic        ceif_amo,
`endif
  input  logic [4:0]  ceif_rs1,
  input  logic [4:0]  ceif_rs2,
  output logic [31:0] a_ex,
  output logic [31:0] b_ex,
  output logic        read_a,
  output logic        read_b,
  output logic [31:0] ifid_r1_fwd,
  output logic [31:0] ifid_r2_fwd
);
  logic exmem_fwd, mwb_fwd, id_read_a, id_read_b;
  always_comb begin
    exmem_fwd = exmem_valid && (exmem_rd != 5'd0) && exmem_wben && !exmem_ld && !exmem_st && !exmem_stop;
    mwb_fwd = mwb_valid && (mwb_rd != 5'd0) && mwb_wben;
    a_ex = idex_r1;
    b_ex = idex_r2;
    if (exmem_fwd && (ce_rs1 == exmem_rd)) a_ex = exmem_result;
    else if (mwb_fwd && (ce_rs1 == mwb_rd)) a_ex = mwb_wv;
    if (exmem_fwd && (ce_rs2 == exmem_rd)) b_ex = exmem_result;
    else if (mwb_fwd && (ce_rs2 == mwb_rd)) b_ex = mwb_wv;
    read_a = idex_valid && ((ce_br || ce_jalr || ce_csr || ld_ok || st_ok || ce_opi || ce_op
`ifdef FPGA
 || ce_m
`endif
) && (ce_rs1 != 5'd0));
    read_b = idex_valid && ((ce_br || st_ok || ce_op
`ifdef FPGA
 || ce_m
`else
 || ce_amo
`endif
) && (ce_rs2 != 5'd0));

    id_read_a = ifid_valid &&
                ((ceif_br || ceif_jalr || ceif_csr || ceif_ld || ceif_st || ceif_opi || ceif_op
`ifdef FPGA
 || ceif_m
`else
 || ceif_amo
`endif
) && (ceif_rs1 != 5'd0));
    id_read_b = ifid_valid && ((ceif_br || ceif_st || ceif_op
`ifdef FPGA
 || ceif_m
`else
 || ceif_amo
`endif
) && (ceif_rs2 != 5'd0));
    ifid_r1_fwd = ifid_r1;
    ifid_r2_fwd = ifid_r2;
    if (id_read_a) begin
      if (exmem_fwd && (ceif_rs1 == exmem_rd)) ifid_r1_fwd = exmem_result;
      else if (mwb_fwd && (ceif_rs1 == mwb_rd)) ifid_r1_fwd = mwb_wv;
    end
    if (id_read_b) begin
      if (exmem_fwd && (ceif_rs2 == exmem_rd)) ifid_r2_fwd = exmem_result;
      else if (mwb_fwd && (ceif_rs2 == mwb_rd)) ifid_r2_fwd = mwb_wv;
    end
  end
endmodule
`default_nettype wire
