// ldext.sv — RV32 load sign/zero extension from raw memory word.
`default_nettype none
module ldext (
  input  logic [2:0]  f3,
  input  logic [31:0] raw,
  output logic [31:0] ext
);
  always_comb begin
    ext = raw;
    case (f3)
      3'b000: ext = {{24{raw[7]}}, raw[7:0]};
      3'b001: ext = {{16{raw[15]}}, raw[15:0]};
      3'b010: ext = raw;
      3'b100: ext = {24'h000000, raw[7:0]};
      3'b101: ext = {16'h0000, raw[15:0]};
      default: ext = raw;
    endcase
  end
endmodule
`default_nettype wire
