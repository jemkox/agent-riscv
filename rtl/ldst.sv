// ldst.sv — legal load/store flags.
`default_nettype none
module ldst (
  input  logic is_ld,
  input  logic is_st,
  input  logic is_ill,
  input  logic is_amo,
  output logic ld_ok,
  output logic st_ok
);
  always_comb begin
    ld_ok = (is_ld || is_amo) && !is_ill;
    st_ok = is_st && !is_ill;
  end
endmodule
`default_nettype wire
