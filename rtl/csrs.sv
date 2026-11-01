// csrs.sv — machine-mode CSR state: counters, trap state, test halt CSR.
`default_nettype none
/* verilator lint_off UNUSED */
module csrs (
  input  logic        clk,
  input  logic        reset,
  input  logic        halt_in,
  input  logic        trap_en,
  input  logic [31:0] trap_pc,
  input  logic [31:0] trap_cause,

  input  logic        cs_read_en,
  input  logic [11:0] cs_rsel,
  output logic [31:0] cs_old,
  input  logic        cs_write_en,
  input  logic [11:0] cs_wsel,
  input  logic [31:0] cs_winsn,
  input  logic [2:0]  cs_wop,
  input  logic [31:0] cs_wrs1,
  input  logic        retire_en,
  input  logic        idex_read_en,
  input  logic [11:0] idex_rsel,
  output logic [31:0] cs_old_idex,
  output logic [31:0] mc_next,
  output logic [31:0] mtcmp_next,
  output logic [31:0] mstatus_next,
  output logic        halt_out,
  output logic [31:0] mstatus,
  output logic [31:0] mtvec,
  output logic [31:0] mepc,
  output logic [31:0] mcause,
  output logic [31:0] mcycle,
  output logic [31:0] minstret,
  output logic [31:0] mtimecmp
);
  localparam CSR_MSTATUS = 12'h300;
  localparam CSR_MTVEC   = 12'h305;
  localparam CSR_MEPC    = 12'h341;
  localparam CSR_MCAUSE  = 12'h342;
  localparam CSR_MTVAL   = 12'h343;
  localparam CSR_MCYCLE  = 12'hb00;
  localparam CSR_MINSTRT = 12'hb02;
  localparam CSR_XHALT   = 12'h3ff;
  localparam CSR_MCOUNTHI= 12'h320;
  localparam CSR_MINSTRT_H = 12'hb82;
  localparam CSR_INSTRET   = 12'hc02;
  localparam CSR_INSTRET_H = 12'hc82;
  localparam CSR_MTIME     = 12'h704;
  localparam CSR_MTIMECMP  = 12'h705;
  localparam CSR_MSCRATCH  = 12'h340;
  localparam CSR_MISA      = 12'h301;
  localparam MSTATUS_MPP = 32'h0000_1800;
  localparam MSTATUS_M   = 32'h0000_1000;

  logic [31:0] st_mscratch = 0;
  logic [31:0] st_misa = 32'h40001001;
  logic [31:0] st_mstatus = 0;
  logic [31:0] st_mtvec = 0;
  logic [31:0] st_mepc = 0;
  logic [31:0] st_mcause = 0;
`ifndef FPGA
  logic [31:0] st_mcycle;
  logic [31:0] st_minstret;
  logic [31:0] st_minstret_hi;
`endif
  logic [31:0] st_mcountinhibit;
  logic [31:0] st_mtimecmp;
  logic        st_halt;

  wire [31:0] mc_ref;
  wire [31:0] min_ref;
  wire [31:0] minh_ref;
`ifdef FPGA
  assign mc_ref = 32'h0;
  assign min_ref = 32'h0;
  assign minh_ref = 32'h0;
`else
  assign mc_ref = st_mcycle;
  assign min_ref = st_minstret;
  assign minh_ref = st_minstret_hi;
`endif
  logic [31:0] old;
  logic [31:0] newv;
  logic [31:0] idex_old;
  logic xret_write, inhibit_cycle, inhibit_instret;
  logic [31:0] after_mstatus, after_mtvec, after_mepc, after_mcause, after_mcycle, after_minstret, after_mtimecmp;
  logic [31:0] after_minstret_hi, after_mcountinhibit;
  logic after_halt;
  logic [31:0] mstatus_wr;
  logic halt_wr;

  always_comb begin
    old = 32'h0;
    if (cs_read_en) begin
      if (cs_rsel == CSR_MSTATUS) old = st_mstatus;
      else if (cs_rsel == CSR_MTVEC) old = st_mtvec;
      else if (cs_rsel == CSR_MEPC) old = st_mepc;
      else if (cs_rsel == CSR_MCAUSE) old = st_mcause;
      else if (cs_rsel == CSR_MTVAL) old = 32'h0;
      else if (cs_rsel == CSR_MSCRATCH) old = st_mscratch;
      else if (cs_rsel == CSR_MISA) old = st_misa;
      else if (cs_rsel == CSR_MCYCLE) old = mc_ref;
      else if (cs_rsel == CSR_MINSTRT || cs_rsel == CSR_INSTRET) old = min_ref;
      else if (cs_rsel == CSR_MINSTRT_H || cs_rsel == CSR_INSTRET_H) old = minh_ref;
      else if (cs_rsel == CSR_MCOUNTHI) old = st_mcountinhibit;
      else if (cs_rsel == CSR_MTIME) old = mc_ref;
      else if (cs_rsel == CSR_MTIMECMP) old = st_mtimecmp;
      else if (cs_rsel == CSR_XHALT) old = st_halt ? 32'h1 : 32'h0;
    end
    newv = cs_wrs1;
    if (cs_wop == 3'b001) newv = cs_wrs1;
    else if (cs_wop == 3'b010) newv = cs_wrs1 | old;
    else if (cs_wop == 3'b011) newv = old & ~cs_wrs1;
    else if (cs_wop == 3'b101) newv = {27'b0, cs_winsn[19:15]};
    else if (cs_wop == 3'b110) newv = {27'b0, cs_winsn[19:15]} | old;
    else if (cs_wop == 3'b111) newv = old & ~{27'b0, cs_winsn[19:15]};

    mstatus_wr = st_mstatus;
    if (!halt_in && !reset && cs_write_en && (cs_wsel == CSR_MSTATUS))
      mstatus_wr = ((newv & MSTATUS_M) != 0) ? (newv | 32'h0000_0800)
                                             : (newv & ~32'h0000_0800);
    halt_wr = st_halt;
    if (!halt_in && !reset && cs_write_en && (cs_wsel == CSR_XHALT) && newv[0]) halt_wr = 1'b1;
    after_mcycle = mc_ref;
    after_minstret = min_ref;
    after_minstret_hi = minh_ref;
    after_mtimecmp = st_mtimecmp;
    after_mcountinhibit = st_mcountinhibit;
    xret_write = cs_write_en &&
      (cs_wsel == CSR_MINSTRT || cs_wsel == CSR_MINSTRT_H ||
       cs_wsel == CSR_INSTRET || cs_wsel == CSR_INSTRET_H);
    inhibit_cycle = st_mcountinhibit[0];
    inhibit_instret = st_mcountinhibit[2];
`ifndef FPGA
    if (retire_en) begin
      if (!inhibit_cycle) after_mcycle = after_mcycle + 32'd1;
      if (!inhibit_instret && !xret_write) begin
        if (st_minstret == 32'hFFFF_FFFF) begin
          after_minstret = 32'h0;
          after_minstret_hi = after_minstret_hi + 32'd1;
        end else begin
          after_minstret = after_minstret + 32'd1;
        end
      end
    end
`endif
    if (cs_write_en) begin
`ifndef FPGA
      if (cs_wsel == CSR_MCYCLE) after_mcycle = newv;
      else if (cs_wsel == CSR_MINSTRT || cs_wsel == CSR_INSTRET) after_minstret = newv;
      else if (cs_wsel == CSR_MINSTRT_H || cs_wsel == CSR_INSTRET_H) after_minstret_hi = newv;
      else if (cs_wsel == CSR_MTIME) after_mcycle = newv;
`endif
      if (cs_wsel == CSR_MCOUNTHI) after_mcountinhibit = newv & 32'h7;
      else if (cs_wsel == CSR_MTIMECMP) after_mtimecmp = newv;
    end
  end

  always_comb begin
    after_mstatus = st_mstatus;
    after_mtvec = st_mtvec;
    after_mepc = st_mepc;
    after_mcause = st_mcause;
    after_halt = st_halt;
    if (!halt_in && !reset) begin
      if (cs_write_en) begin
        if (cs_wsel == CSR_MSTATUS)
          after_mstatus = ((newv & MSTATUS_M) != 0) ? (newv | 32'h0000_0800)
                                                   : (newv & ~32'h0000_0800);
        else if (cs_wsel == CSR_MTVEC) after_mtvec = newv;
        else if (cs_wsel == CSR_MEPC) after_mepc = newv;
        else if (cs_wsel == CSR_MCAUSE) after_mcause = newv;
        else if (cs_wsel == CSR_XHALT) after_halt = newv[0] ? 1'b1 : after_halt;
      end
      if (trap_en) begin
        after_mepc = trap_pc;
        after_mcause = trap_cause;
        after_mstatus = after_mstatus | MSTATUS_MPP;
      end
    end
    idex_old = 32'h0;
    if (idex_read_en) begin
      if (idex_rsel == CSR_MSTATUS) idex_old = after_mstatus;
      else if (idex_rsel == CSR_MTVEC) idex_old = after_mtvec;
      else if (idex_rsel == CSR_MEPC) idex_old = after_mepc;
      else if (idex_rsel == CSR_MCAUSE) idex_old = after_mcause;
      else if (idex_rsel == CSR_MTVAL) idex_old = 32'h0;
      else if (idex_rsel == CSR_MSCRATCH) idex_old = st_mscratch;
      else if (idex_rsel == CSR_MISA) idex_old = st_misa;
      else if (idex_rsel == CSR_MCYCLE) idex_old = after_mcycle;
      else if (idex_rsel == CSR_MINSTRT || idex_rsel == CSR_INSTRET) idex_old = after_minstret;
      else if (idex_rsel == CSR_MINSTRT_H || idex_rsel == CSR_INSTRET_H) idex_old = after_minstret_hi;
      else if (idex_rsel == CSR_MCOUNTHI) idex_old = after_mcountinhibit;
      else if (idex_rsel == CSR_MTIME) idex_old = after_mcycle;
      else if (idex_rsel == CSR_MTIMECMP) idex_old = after_mtimecmp;
      else if (idex_rsel == CSR_XHALT) idex_old = after_halt ? 32'h1 : 32'h0;
    end
  end
    assign cs_old = old;
    assign cs_old_idex = idex_old;
    assign mc_next = after_mcycle;
    assign mtcmp_next = after_mtimecmp;
    assign mstatus_next = mstatus_wr;
    assign halt_out = halt_wr;


  always_comb begin
    mstatus = st_mstatus;
    mtvec = st_mtvec;
    mepc = st_mepc;
    mcause = st_mcause;
    mcycle = mc_ref;
    minstret = min_ref;
    mtimecmp = st_mtimecmp;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      st_mstatus <= 32'h0;
      st_mtvec <= 32'h0;
      st_mepc <= 32'h0;
      st_mcause <= 32'h0;
      st_mscratch <= 32'h0;
      st_misa <= 32'h40001001;
`ifndef FPGA
      st_mcycle <= 32'h0;
      st_minstret <= 32'h0;
      st_minstret_hi <= 32'h0;
`endif
      st_mcountinhibit <= 32'h0;
      st_mtimecmp <= 32'hFFFF_FFFF;
      st_halt <= 1'b0;
      end else if (!halt_in) begin
`ifndef FPGA
        if (retire_en) begin
          if (!inhibit_cycle) st_mcycle <= st_mcycle + 32'd1;
          if (!inhibit_instret && !xret_write) begin
            if (st_minstret == 32'hFFFF_FFFF) begin
              st_minstret <= 32'h0;
              st_minstret_hi <= st_minstret_hi + 32'd1;
            end else begin
              st_minstret <= st_minstret + 32'd1;
            end
          end
        end
`endif
        if (!halt_in) st_mstatus <= mstatus_wr;
      if (trap_en) st_mstatus <= st_mstatus | MSTATUS_MPP;
      if (cs_write_en) begin
        case (cs_wsel)
          CSR_MTVEC:   st_mtvec <= newv;
          CSR_MSCRATCH: st_mscratch <= newv;
          CSR_MISA:    begin end
          CSR_MEPC:    st_mepc <= newv;
          CSR_MCAUSE:  st_mcause <= newv;
          CSR_MTVAL:   begin end
`ifndef FPGA
          CSR_MCYCLE:  st_mcycle <= newv;
          CSR_MINSTRT, 12'hc02: st_minstret <= newv;
          CSR_MINSTRT_H, 12'hc82: st_minstret_hi <= newv;
          CSR_MTIME:   st_mcycle <= newv;
`endif
          CSR_MCOUNTHI: st_mcountinhibit <= newv & 32'h7;
          CSR_MTIMECMP: st_mtimecmp <= newv;
          CSR_XHALT:   st_halt <= newv[0] ? 1'b1 : st_halt;
          default: begin end
        endcase
      end
      if (trap_en) begin
        st_mepc <= trap_pc;
        st_mcause <= trap_cause;
      end
    end
  end
endmodule
/* verilator lint_on UNUSED */
`default_nettype wire
