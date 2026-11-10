// Probe: decode the busybox fault instruction words through ctrl.
module t_ctrl_probe();
  logic [31:0] i;
  ctrl C(.i(i));
  initial begin
    i = 32'h12a42023; #1; $display("SW  12a42023: is_st=%b is_ill=%b f3=%b opc=%b rs1=%b rs2=%b imm-ish=%b",
      C.is_st, C.is_ill, C.f3, i[6:0], C.rs1, C.rs2, i[31:25]);
    i = 32'h1d9710ef; #1; $display("JAL 1d9710ef: is_jal=%b is_ill=%b f3=%b", C.is_jal, C.is_ill, C.f3);
    i = 32'h00078513; #1; $display("ADD 00078513: is_ill=%b", C.is_ill);
    i = 32'h1c1710ef; #1; $display("    1c1710ef: is_ill=%b is_jal=%b", C.is_ill, C.is_jal);
    i = 32'hedc58593; #1; $display("LW  edc58593: is_ld=%b is_ill=%b", C.is_ld, C.is_ill);
    i = 32'hba1b80ef; #1; $display("JR  ba1b80ef: is_jalr=%b is_ill=%b f3=%b", C.is_jalr, C.is_ill, C.f3);
    i = 32'haca1a023; #1; $display("SW  aca1a023: is_st=%b is_ill=%b f3=%b", C.is_st, C.is_ill, C.f3);
    i = 32'haca1a023;
    $display("rs1 field of aca1a023 = %02d rs2=%02d", C.rs1, C.rs2);
    $finish;
  end
endmodule
