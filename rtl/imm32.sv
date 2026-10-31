// All RV32I immediates extracted from instruction word i[31:0].
/* verilator lint_off UNUSEDSIGNAL */
module imm32 (
  input  logic [31:0]  i,
  output logic [31:0]  iimm,   // I-type: i[31:20] sext
  output logic [31:0]  simm,   // S-type: i[31:25],i[11:7] sext
  output logic [31:0]  bimm,   // B-type: i[31],i[7],i[30:25],i[11:8],0 sext
  output logic [31:0]  uimm,   // U-type: i[31:12]<<12
  output logic [31:0]  jimm    // J-type: i[31],i[19:12],i[20],i[30:21] sext
);
  always_comb begin
    iimm = {{20{i[31]}}, i[31:20]};
    simm = {{20{i[31]}}, i[31:25], i[11:7]};
    bimm = {{19{i[31]}}, i[31], i[7], i[30:25], i[11:8], 1'b0};
    uimm = {i[31:12], 12'h000};
    jimm = {{11{i[31]}}, i[31], i[19:12], i[20], i[30:21], 1'b0};
  end
endmodule
