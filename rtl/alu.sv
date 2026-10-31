// Main ALU. op codes: 0 ADD 1 SUB 2 AND 3 OR 4 XOR 5 SLL 6 SRL 7 SRA 8 SLT 9 SLTU.
// Also exposes zero/equality bits and full add/sub results used by BRANCH units.
module alu (
  input  logic [31:0] a,
  input  logic [31:0] b,
  input  logic [3:0]  op,
  output logic [31:0] res,
  output logic        eq,          // a == b
  output logic        slt_r,       // signed a < b
  output logic        sltu_r       // unsigned a < b
);
  logic [31:0] sub;
  logic [4:0]  sh;
  assign sh   = b[4:0];
  assign sub  = a - b;
  assign eq   = (a == b);
  assign slt_r  = ($signed(a) < $signed(b));
  assign sltu_r = (a < b);

  always_comb begin
    case (op)
      4'd0: res = a + b;
      4'd1: res = sub;                               // SUB
      4'd2: res = a & b;
      4'd3: res = a | b;
      4'd4: res = a ^ b;
      4'd5: res = a << sh;
      4'd6: res = a >> sh;
      4'd7: res = $signed(a) >>> sh;
      4'd8: res = {31'b0, slt_r};
      4'd9: res = {31'b0, sltu_r};
      default: res = a + b;
    endcase
  end
endmodule
