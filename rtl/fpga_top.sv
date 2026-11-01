// Small FPGA proof CPU: subset RV32I single-cycle datapath + block-RAM data + UART TX.
// Supports: addi, lui, sw, lw, add. Fixed ROM program exercises RAM load/store and UART TX.
`default_nettype none
module fpga_top (
  input  logic        clk,
  input  logic        reset,
  output logic [7:0]  uart_tx,
  output logic        uart_tx_valid,
  output logic        halt
);
  localparam int PROG_WORDS = 9;
  localparam int END_PC = PROG_WORDS * 4;
  localparam [31:0] UART_ADDR = 32'h1000_0000;

  logic [31:0] pc = 0;
  logic stop = 0;
  logic [31:0] ir;
  logic [31:0] regs [0:7];
  (* BRAM = 1, BRAM_INIT = 1 *) logic [31:0] dmem [0:1023];
  logic [6:0] op;
  logic [2:0] rd_i, rs1_i, rs2_i, load_dest;
  logic [31:0] a, b, alu, wb_val, imm_i, imm_s, imm_u, load_ea, store_ea;
  logic is_load, is_store, is_lui, is_addi, is_add, wb_en, mem_write;
  logic load_req;
  logic [31:0] load_val_q;

  always_comb begin
    ir = 0;
    case (pc[5:2])
      4'd0: ir = 32'h0410_0093; // addi x1,x0,65
      4'd1: ir = 32'h0000_0113; // addi x2,x0,0
      4'd2: ir = 32'h0000_0193; // addi x3,x0,0
      4'd3: ir = 32'h1000_02B7; // lui x5,0x10000
      4'd4: ir = 32'h0011_8023; // sw x1,0(x3)
      4'd5: ir = 32'h0001_8203; // lw x4,0(x3)
      4'd6: ir = 32'h0000_0013; // addi x0,x0,0 (load delay slot)
      4'd7: ir = 32'h0046_8023; // sw x4,0(x5)
      default: ir = 32'h0042_03B3; // add x7,x1,x4
    endcase
  end

  assign op = ir[6:0];
  assign rd_i = ir[9:7];
  assign rs1_i = ir[17:15];
  assign rs2_i = ir[22:20];
  assign imm_i = {{20{ir[31]}}, ir[31:20]};
  assign imm_s = {{20{ir[31]}}, ir[31:25], ir[11:7]};
  assign imm_u = {ir[31:12], 12'h0};
  assign a = regs[rs1_i];
  assign b = regs[rs2_i];
  assign is_load = (op == 7'h03);
  assign is_store = (op == 7'h23);
  assign is_lui = (op == 7'h37);
  assign is_addi = (op == 7'h13);
  assign is_add = (op == 7'h33);
  assign load_ea = a + imm_i;
  assign store_ea = a + imm_s;
  assign alu = is_add ? (a + b) : (is_lui ? imm_u : (is_store ? store_ea : load_ea));
  assign wb_en = ((is_lui || is_addi || is_add) && (rd_i != 3'd0));
  assign wb_val = alu;
  assign mem_write = is_store && (store_ea != UART_ADDR);
  assign halt = stop;
  assign uart_tx_valid = is_store && (store_ea == UART_ADDR) && !stop;
  assign uart_tx = b[7:0];

  always_ff @(posedge clk) begin
    if (reset) begin
      pc <= 0;
      stop <= 1'b0;
      load_req <= 1'b0;
      for (int i = 0; i < 8; i++) regs[i] <= 32'h0;
    end else if (stop) begin
      pc <= pc;
      stop <= stop;
    end else begin
      pc <= pc + 32'h4;
      stop <= ((pc + 32'h4) >= END_PC);
      load_req <= is_load;
      if (load_req && (load_dest != 3'd0)) regs[load_dest] <= load_val_q;
      if (wb_en) regs[rd_i] <= wb_val;
      if (mem_write) dmem[store_ea[11:2]] <= b;
      if (is_load) begin
        load_dest <= rd_i;
        load_val_q <= dmem[load_ea[11:2]];
      end
    end
  end
endmodule
`default_nettype none
