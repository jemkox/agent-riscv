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
  localparam int BYTES = 64;
  localparam int MASK  = 63;
  logic [7:0] ram [0:BYTES-1];

  int lbase, sbase;

  assign lbase = lwa & MASK;
  assign sbase = sa  & MASK;

  assign id = { ram[(ia + 3) & MASK], ram[(ia + 2) & MASK],
                ram[(ia + 1) & MASK], ram[ ia       & MASK] };
  assign ld = { ram[(la + 3) & MASK], ram[(la + 2) & MASK],
                ram[(la + 1) & MASK], ram[ la       & MASK] };

  always_ff @(posedge clk) begin
    if (lwe) begin
      ram[lbase]                  <= lwd[7:0];
      ram[(lbase + 1) & MASK]     <= lwd[15:8];
      ram[(lbase + 2) & MASK]     <= lwd[23:16];
      ram[(lbase + 3) & MASK]     <= lwd[31:24];
    end
    if (sw) begin
      ram[sbase] <= sd[7:0];
      if (ssz == 2'b01 || ssz == 2'b10)
        ram[(sbase + 1) & MASK] <= sd[15:8];
      if (ssz == 2'b10) begin
        ram[(sbase + 2) & MASK] <= sd[23:16];
        ram[(sbase + 3) & MASK] <= sd[31:24];
      end
    end
  end
endmodule
