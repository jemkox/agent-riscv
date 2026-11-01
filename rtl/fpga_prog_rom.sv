// auto-generated FPGA ROM include for fpga_pipe_top
localparam int FPGA_PROG_WORDS = 21;
function [31:0] fpga_prog_word;
  input [15:0] idx;
  case (idx)
    0: fpga_prog_word = 32'hfffff0b7;
    1: fpga_prog_word = 32'hfff08093;
    2: fpga_prog_word = 32'h00001137;
    3: fpga_prog_word = 32'h7ff10193;
    4: fpga_prog_word = 32'h80010213;
    5: fpga_prog_word = 32'h004182b3;
    6: fpga_prog_word = 32'h40418333;
    7: fpga_prog_word = 32'h0ff0f393;
    8: fpga_prog_word = 32'hf0026413;
    9: fpga_prog_word = 32'hfff0c493;
    10: fpga_prog_word = 32'hfff22513;
    11: fpga_prog_word = 32'hfff23593;
    12: fpga_prog_word = 32'h00100613;
    13: fpga_prog_word = 32'h01f61613;
    14: fpga_prog_word = 32'h01f65693;
    15: fpga_prog_word = 32'hfff00713;
    16: fpga_prog_word = 32'h41f75713;
    17: fpga_prog_word = 32'h003227b3;
    18: fpga_prog_word = 32'h00323833;
    19: fpga_prog_word = 32'h00000897;
    20: fpga_prog_word = 32'h00100073;
    default: fpga_prog_word = 32'h0000_0000;
  endcase
endfunction
