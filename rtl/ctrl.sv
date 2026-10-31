// Instruction decode control for RV32IM (+ later CSR/AMO fields).
// alu_op: 0 ADD 1 SUB 2 AND 3 OR 4 XOR 5 SLL 6 SRL 7 SRA 8 SLT 9 SLTU
//         10 MUL 11 MULH 12 MULHU (added in M3)
module ctrl (
  input  logic [31:0]  i,
  output logic [3:0]   alu_op,
  output logic [2:0]   f3,          // funct3 i[14:12]
  output logic [6:0]   op7,         // i[31:25]
  output logic [4:0]   rs1,
  output logic [4:0]   rs2,
  output logic [4:0]   rd,
  output logic         a_sel,       // ALU A source: 0 = rs1, 1 = imm
  output logic         b_sel,       // ALU B source: 0 = rs2, 1 = imm
  output logic         is_ld,
  output logic         is_st,
  output logic         is_br,
  output logic         is_jal,
  output logic         is_jalr,
  output logic         is_lui,
  output logic         is_auipc,
  output logic         is_opi,
  output logic         is_op,
  output logic         is_sys,      // SYSTEM opcode (ecall/ebreak/CSR in M5)
  output logic         is_fence,    // FENCE opcode (no-op in M1)
  output logic         is_mret,
  output logic         is_ill
);
  logic [6:0] opc;
  assign opc = i[6:0];
  assign is_ld    = (opc == 7'b0000011);
  assign is_st    = (opc == 7'b0100011);
  assign is_br    = (opc == 7'b1100011);
  assign is_jal   = (opc == 7'b1101111);
  assign is_jalr  = (opc == 7'b1100111);
  assign is_lui   = (opc == 7'b0110111);
  assign is_auipc = (opc == 7'b0010111);
  assign is_opi   = (opc == 7'b0010011);
  assign is_op    = (opc == 7'b0110011);
  assign is_sys   = (opc == 7'b1110011);
  assign is_fence = (opc == 7'b0001111);
  assign is_mret  = 1'b0;
  assign f3  = i[14:12];
  assign op7 = i[31:25];
  assign rs1 = i[19:15];
  assign rs2 = i[24:20];
  assign rd  = i[11:7];

  always_comb begin
    alu_op = 4'd0; a_sel = 0; b_sel = 0;
    is_ill = 0;
    case (opc)
      7'b0000011: begin alu_op = 4'd0; b_sel = 1; end                          // LOAD
      7'b0100011: begin alu_op = 4'd0; b_sel = 1; end                          // STORE
      7'b1100011: begin end                                              // BRANCH
      7'b1101111: begin alu_op = 4'd0; a_sel = 1; b_sel = 1; end               // JAL
      7'b1100111: begin alu_op = 4'd0; b_sel = 1; end                          // JALR
      7'b0110111: begin end                                                // LUI
      7'b0010111: begin end                                              // AUIPC
      7'b0010011: begin                                                   // OP-IMM
        case (f3)
          3'b000: alu_op = 4'd0;                       // ADDI
          3'b100: alu_op = 4'd4;                       // XORI
          3'b110: alu_op = 4'd3;                       // ORDI
          3'b111: alu_op = 4'd2;                       // ANDI
          3'b010: alu_op = 4'd8;                       // SLTI
          3'b011: alu_op = 4'd9;                       // SLTIU
          3'b001: alu_op = 4'd5;                       // SLLI
          3'b101: alu_op = op7[5] ? 4'd7 : 4'd6;       // SRLI/SRAI
          default: is_ill = 1;
        endcase
        b_sel = 1;
      end
      7'b0110011: begin                                                   // OP
        case (f3)
          3'b000: alu_op = op7[5] ? 4'd1 : 4'd0;      // ADD/SUB
          3'b001: alu_op = 4'd5;                       // SLL
          3'b101: alu_op = op7[5] ? 4'd7 : 4'd6;       // SRL/SRA
          3'b010: alu_op = 4'd8;                       // SLT
          3'b011: alu_op = 4'd9;                       // SLTU
          3'b100: alu_op = 4'd4;                       // XOR
          3'b110: alu_op = 4'd3;                       // OR
          3'b111: alu_op = 4'd2;                       // AND
          default: is_ill = 1;
        endcase
      end
      7'b0001111: begin end                                             // FENCE
      7'b1110011: begin end                                             // SYSTEM
      default: is_ill = 1;
    endcase
    if (is_br && (f3 == 3'b010 || f3 == 3'b011)) is_ill = 1;
    if (is_jalr && i[14:12] != 3'b000) is_ill = 1;
    if (is_ld && (f3 == 3'b011 || f3 == 3'b110 || f3 == 3'b111)) is_ill = 1;
    if (is_st && (f3 == 3'b011 || f3 == 3'b110 || f3 == 3'b111)) is_ill = 1;
  end
endmodule
