// State-free memory interface used by the formal pipeline checker.
module mem32 (
  input  logic        clk,
  input  logic [31:0] ia,
  output logic [31:0] id,
  input  logic [31:0] la,
  output logic [31:0] ld,
  input  logic        sw,
  input  logic [31:0] sa,
  input  logic [31:0] sd,
  input  logic [1:0]  ssz,
  input  logic        lwe,
  input  logic [31:0] lwa,
  input  logic [31:0] lwd
);
  assign id = 32'h0;
  assign ld = 32'h0;
endmodule