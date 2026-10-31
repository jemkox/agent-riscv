module mem32 (
  input  logic        clk,
  input  logic [31:0] ia,
  output logic [31:0] id,
  input  logic [31:0] la,
  output logic [31:0] ld,
  input  logic        sw,
  input  logic [31:0] sa,
  input  logic [31:0] sd,
  input  logic [3:0]  sbe,
  input  logic        lwe,
  input  logic [31:0] lwa,
  input  logic [31:0] lwd
);
  logic [31:0] ram [0:15];
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
