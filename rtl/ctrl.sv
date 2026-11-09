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
  output logic         is_sret,      // SRET (SYSTEM f3=0 imm=0x106)
  output logic         is_ill,
  output logic         is_csr,
  output logic [1:0]   csr_req,     // required privilege of the id CSR op
  output logic         csr_def,     // CSR number is implemented; else the CSR op faults
  output logic         csr_ro,      // read-only CSR (Zicntr views); write -> illegal
  output logic         is_wfi,      // WFI builder aliases: 0x100 (x10000073) and 0x105 (x10500073)
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
  assign is_sret  = (opc == 7'b1110011 && i[14:12] == 3'b000 &&
                     (i[31:20] == 12'h102 || i[31:20] == 12'h106));
  // Legacy mhpmcounter3..31 CSRs 0xB03-0xB1F: pinned spike defines them
  // machine-level (bits [9:8]=3), reads 0 / ignores writes. OpenSBI probes
  // mhint3=0xB03 while still in M; a strict "unimplemented CSR" decode traps
  // there and diverges from the pin. 0xB00/0xB02/0xB82 keep their own counters;
  // 0xB01/0xB81/0xB20/0xBA0 stay illegal (spike probes t48/t48b).
  function bit csr_hint;
    input bit [11:0] c;
    csr_hint = ((c >= 12'hb03) && (c <= 12'hb1f)) ||
               (c == 12'hb80) || ((c >= 12'hb83) && (c <= 12'hb9f)) ||
               (c == 12'h31a);   // menvcfgh: spike keeps it 0 (mask empty)
  endfunction
  assign csr_req  = (csr_num == 12'h3ff) ? 2'b00
                    : csr_hint(csr_num) ? 2'b11        // spike: machine-only
                    : (csr_num == 12'h282) ? 2'b11     // medelegh: machine-only (spike)
                    : csr_num[9:8];
  assign csr_def  = csr_defined(csr_num);
  assign csr_ro   = is_csr_readonly(csr_num);
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
                    (i[31:20] == 12'h302) || (i[31:20] == 12'h102) ||
                    (i[31:20] == 12'h100) || (i[31:20] == 12'h105) ||
                    (i[31:20] == 12'h106) || (i[31:20] == 12'h120) ||
                    ((i[31:25] == 7'b0001001) && (i[11:7] == 5'b0)))) is_ill = 1;
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

  function bit csr_defined;   // implemented CSR numbers (aligned to spike banner)
    input bit [11:0] c;
    csr_defined = (c == 12'h300 || c == 12'h301 || c == 12'h302 || c == 12'h303 ||
            c == 12'h304 || c == 12'h305 || c == 12'h320 ||
            c == 12'h340 || c == 12'h341 || c == 12'h342 || c == 12'h343 ||
            c == 12'h344 ||             c == 12'h3ff || c == 12'h100 || c == 12'h104 ||
            c == 12'h105 || c == 12'h106 || c == 12'h140 || c == 12'h141 ||
            c == 12'h142 || c == 12'h143 || c == 12'h180 || c == 12'hb00 ||
            c == 12'hb02 || c == 12'hb82 || c == 12'hc01 || c == 12'hc02 ||
            c == 12'hc81 || c == 12'hc82 ||             c == 12'hc00 || c == 12'hc80 ||
            (c >= 12'hb03 && c <= 12'hb1f) ||   // legacy mhpmcounter3..31 (spike-defined)
            c == 12'hb80 || (c >= 12'hb83 && c <= 12'hb9f) ||  // mcycleh + mhpmcounterNh
            c == 12'hb80 || (c >= 12'hb83 && c <= 12'hb9f) || // mcycleh + mhpmcounterNh
            c == 12'h310 || c == 12'h306 || c == 12'h30a ||   // mstatush,mcounteren,menvcfg
            c == 12'h31a ||                                  // menvcfgh (always 0, spike)
            ((c >= 12'h7a0) && (c <= 12'h7a4)) ||            // spike smask-family CSRs
            c == 12'hf11 || c == 12'hf12 || c == 12'hf13 ||
            c == 12'hf14 || c == 12'h7a0 || c == 12'h7a1 || c == 12'h7a2 ||
            c == 12'h7a3 || c == 12'h7a4 || c == 12'h7a5 || c == 12'h7a6 ||
            c == 12'h7a7 || c == 12'h270 || c == 12'h144 ||
            c == 12'h202 || c == 12'h282);   // smedelegh / medelegh (spike)
  endfunction

  function bit is_csr_readonly;   // Zicntr read-only views: write -> illegal
    input bit [11:0] c;
    is_csr_readonly = (c == 12'hc00 || c == 12'hc80 || c == 12'hc01 ||
            c == 12'hc81 || c == 12'hc02 || c == 12'hc82);
  endfunction
endmodule
