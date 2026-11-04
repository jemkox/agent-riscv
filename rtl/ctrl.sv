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
  output logic         is_sys,      // SYSTEM ECALL/EBREAK in current halt mode
  output logic         is_fence,    // FENCE opcode (no-op in M1)
  output logic         is_m,
  output logic [2:0]   m_op,        // 0 MUL, 1 MULH, 2 MULHSU, 3 MULHU, 4 DIV, 5 DIVU, 6 REM, 7 REMU
  output logic         is_mret,
  output logic         is_ill,
  output logic         is_csr,      // Zicsr CSRRW/S/C and immediate forms
  output logic         is_wfi,      // WFI (0x10000073): waits until an IRQ is pending
  output logic         is_amo,      // A: LR/SC/AMO*.w (simulation CPU only; FPGA: 0)
  output logic         is_lr,       // LR.W
  output logic         is_sc,       // SC.W
  output logic [4:0]   amo5,        // AMO funct5 selector (i[31:27])
  output logic [11:0]  csr_num      // i[31:20]
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
  assign is_fence = (opc == 7'b0001111);
  assign is_mret  = (opc == 7'b1110011 && i[14:12] == 3'b000 && i[31:20] == 12'h302);
`ifdef FPGA
  assign is_wfi   = 1'b0;           // FPGA never executes WFI (no OS on the card;
                                     // keeps SYSTEM f3=0 decode shape for Fmax seed4)
`else
  assign is_wfi   = (opc == 7'b1110011 && i[14:12] == 3'b000 &&
                     ((i[31:20] == 12'h100) || (i[31:20] == 12'h105)));
`endif
`ifndef FPGA
  logic amo5_ok;
  always_comb begin
    case (i[31:27])
      5'b00000, 5'b00001, 5'b00011, 5'b00100, 5'b01000,
      5'b01100, 5'b10000, 5'b10100, 5'b11000, 5'b11100:
        amo5_ok = 1'b1;
      5'b00010:
        amo5_ok = (i[24:20] == 5'd0);   // LR.W requires rs2=0
      default:
        amo5_ok = 1'b0;
    endcase
  end
  assign is_amo = (opc == 7'b0101111) && (i[14:12] == 3'b010) && amo5_ok;
  assign is_lr  = is_amo && (i[31:27] == 5'b00010);
  assign is_sc  = is_amo && (i[31:27] == 5'b00011);
  assign amo5   = i[31:27];
`ifdef DBGCTRL
  always_comb if (is_amo) $display("CTRLD i=%08x f5=%05b f3=%03b is_amo=%b is_sc=%b is_lr=%b", i, i[31:27], i[14:12], is_amo, is_sc, is_lr);
`endif
`else
  assign is_amo = 1'b0; assign is_lr = 1'b0; assign is_sc = 1'b0; assign amo5 = 5'd0;
`endif
  assign f3  = i[14:12];
  assign op7 = i[31:25];
  assign rs1 = i[19:15];
  assign rs2 = i[24:20];
  assign rd  = i[11:7];
  assign csr_num = i[31:20];

  always_comb begin
    alu_op = 4'd0; a_sel = 0; b_sel = 0;
    is_ill = 0; is_m = 0; is_sys = 0; is_csr = 0; m_op = 3'd0;
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
        if (op7 == 7'b0000001) begin
          is_m = 1;
          case (f3)
            3'b000: m_op = 3'd0;                       // MUL
            3'b001: m_op = 3'd1;                       // MULH
            3'b010: m_op = 3'd2;                       // MULHSU
            3'b011: m_op = 3'd3;                       // MULHU
            3'b100: m_op = 3'd4;                       // DIV
            3'b101: m_op = 3'd5;                       // DIVU
            3'b110: m_op = 3'd6;                       // REM
            3'b111: m_op = 3'd7;                       // REMU
            default: is_ill = 1;
          endcase
        end else begin
          case (f3)
            3'b000: alu_op = (op7 == 7'b0100000) ? 4'd1 : 4'd0; // ADD/SUB
            3'b001: alu_op = 4'd5;                       // SLL
            3'b101: alu_op = (op7 == 7'b0100000) ? 4'd7 : 4'd6; // SRL/SRA
            3'b010: alu_op = 4'd8;                       // SLT
            3'b011: alu_op = 4'd9;                       // SLTU
            3'b100: alu_op = 4'd4;                       // XOR
            3'b110: alu_op = 4'd3;                       // OR
            3'b111: alu_op = 4'd2;                       // AND
            default: is_ill = 1;
          endcase
          if ((f3 == 3'b000 || f3 == 3'b101) &&
              (op7 != 7'b0000000 && op7 != 7'b0100000)) is_ill = 1;
          if ((f3 == 3'b001 || f3 == 3'b010 || f3 == 3'b011 ||
               f3 == 3'b100 || f3 == 3'b110 || f3 == 3'b111) &&
              (op7 != 7'b0000000)) is_ill = 1;
        end
      end
`ifndef FPGA
      7'b0101111: if (!is_amo) is_ill = 1;
`endif
      7'b0001111: begin end                                             // FENCE
      7'b1110011: begin                                                  // SYSTEM / CSR
        case (f3)
          3'b000: begin
`ifdef FPGA
            // FPGA build: WFI never runs; keep committed decode shape (Fmax seed4)
            if (i[31:20] == 12'h000) is_sys = 1;                         // ECALL
            else if (i[31:20] == 12'h001) is_sys = 1;                    // EBREAK
            else if (i[31:20] == 12'h302) begin end                      // MRET
            else is_ill = 1;
`else
            is_sys = (i[31:20] == 12'h000) || (i[31:20] == 12'h001);
            if (!((i[31:20] == 12'h000) || (i[31:20] == 12'h001) ||
                   (i[31:20] == 12'h302) || (i[31:20] == 12'h100) ||
                   (i[31:20] == 12'h105))) is_ill = 1;
`endif
          end
          3'b001: is_csr = 1;
          3'b010: is_csr = 1;
          3'b011: is_csr = 1;
          3'b100: is_ill = 1;
          3'b101: is_csr = 1;
          3'b110: is_csr = 1;
          3'b111: is_csr = 1;
          default: is_ill = 1;
        endcase
      end
      default: is_ill = 1;
    endcase
    if (is_br && (f3 == 3'b010 || f3 == 3'b011)) is_ill = 1;
    if (is_jalr && i[14:12] != 3'b000) is_ill = 1;
    if (is_ld && (f3 == 3'b011 || f3 == 3'b110 || f3 == 3'b111)) is_ill = 1;
    if (is_st && (f3 == 3'b011 || f3 == 3'b110 || f3 == 3'b111)) is_ill = 1;
    if (is_opi && (f3 == 3'b001 || f3 == 3'b101) && (i[25])) is_ill = 1;
  end
endmodule
