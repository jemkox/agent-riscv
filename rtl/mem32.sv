// Word-addressable RAM: byte addr a -> word index a[17:2]; 256 KiB range 0..0x3FFFF.
// Continuous reads (fetch, load); clocked writes (CPU store with byte-enables; tb loader word).
/* verilator lint_off UNUSEDSIGNAL */
module mem32 #(
  parameter int SIZE = 65536
)(
  input  logic        clk,
  input  logic [31:0] ia,            // fetch addr
  output logic [31:0] id,
  input  logic [31:0] la,            // load addr
  output logic [31:0] ld,
  input  logic        sw,            // CPU store
  input  logic [31:0] sa,
  input  logic [31:0] sd,
  input  logic [3:0]  sbe,
  input  logic        lwe,           // testbench loader port
  input  logic [31:0] lwa,
  input  logic [31:0] lwd
);
  logic [31:0] ram [0:SIZE-1];

  assign id = ram[ia[17:2]];
  assign ld = ram[la[17:2]];

  always_ff @(posedge clk) begin
    if (lwe) ram[lwa[17:2]] <= lwd;
    if (sw) begin
      if (sbe[0]) ram[sa[17:2]][7:0]    <= sd[7:0];
      if (sbe[1]) ram[sa[17:2]][15:8]   <= sd[15:8];
      if (sbe[2]) ram[sa[17:2]][23:16]  <= sd[23:16];
      if (sbe[3]) ram[sa[17:2]][31:24]  <= sd[31:24];
    end
  end
endmodule
