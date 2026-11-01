// store.sv — RV32 store byte-enable and aligned store-data generation.
`default_nettype none
module store (
  input  logic        st_ok,
  input  logic [2:0]  ce_f3,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0] ea,
  input  logic [31:0] b_ex,
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [1:0]  ssz,
  output logic [31:0] sd_raw,
  output logic [31:0] sd_log,
  output logic [3:0]  sbe
);
  always_comb begin
    ssz = 2'b00;
    sd_raw = 32'h0;
    sd_log = 32'h0;
    sbe = 4'h0;
    if (st_ok) begin
      if (ce_f3 == 3'b000) begin
        ssz = 2'b00;
        sd_raw = {24'h000000, b_ex[7:0]};
        case (ea[1:0])
          2'b00: begin sbe = 4'b0001; sd_log = {24'h000000, b_ex[7:0]}; end
          2'b01: begin sbe = 4'b0010; sd_log = {16'h0000, b_ex[7:0], 8'h00}; end
          2'b10: begin sbe = 4'b0100; sd_log = {8'h00, b_ex[7:0], 16'h0000}; end
          2'b11: begin sbe = 4'b1000; sd_log = {b_ex[7:0], 24'h000000}; end
          default: begin sbe = 4'h0; sd_log = 32'h0; end
        endcase
      end else if (ce_f3 == 3'b001 || ce_f3 == 3'b101) begin
        ssz = 2'b01;
        sd_raw = {16'h0000, b_ex[15:0]};
        if (ea[1] == 1'b0) begin
          sbe = 4'b0011;
          sd_log = {16'h0000, b_ex[15:0]};
        end else begin
          sbe = 4'b1100;
          sd_log = {b_ex[15:0], 16'h0000};
        end
      end else begin
        ssz = 2'b10;
        sd_raw = b_ex;
        sbe = 4'b1111;
        sd_log = b_ex;
      end
    end
  end
endmodule
`default_nettype wire
