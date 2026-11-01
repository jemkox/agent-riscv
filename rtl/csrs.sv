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
  logic [31:0] st_mcycle;
  logic [31:0] st_minstret;
  logic [31:0] st_minstret_hi;
  logic [31:0] st_mcountinhibit;
  logic [31:0] st_mtimecmp;
  logic        st_halt;

  wire [31:0] mc_ref;
  wire [31:0] min_ref;
  wire [31:0] minh_ref;
  assign mc_ref = st_mcycle;
  assign min_ref = st_minstret;
  assign minh_ref = st_minstret_hi;
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
      old =   (cs_rsel == CSR_MSTATUS  ? st_mstatus : 32'h0)
            | (cs_rsel == CSR_MTVEC    ? st_mtvec : 32'h0)
            | (cs_rsel == CSR_MEPC     ? st_mepc : 32'h0)
            | (cs_rsel == CSR_MCAUSE   ? st_mcause : 32'h0)
            | (cs_rsel == CSR_MSCRATCH ? st_mscratch : 32'h0)
            | (cs_rsel == CSR_MISA     ? st_misa : 32'h0)
            | (cs_rsel == CSR_MCYCLE || cs_rsel == CSR_MTIME ? mc_ref : 32'h0)
            | (cs_rsel == CSR_MINSTRT || cs_rsel == CSR_INSTRET ? min_ref : 32'h0)
            | (cs_rsel == CSR_MINSTRT_H || cs_rsel == CSR_INSTRET_H ? minh_ref : 32'h0)
            | (cs_rsel == CSR_MCOUNTHI ? st_mcountinhibit : 32'h0)
            | (cs_rsel == CSR_MTIMECMP ? st_mtimecmp : 32'h0)
            | (cs_rsel == CSR_XHALT ? {31'b0, st_halt} : 32'h0);
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
    if (retire_en) begin
      if (!inhibit_cycle) after_mcycle = after_mcycle + 32'd1;
      if (!inhibit_instret && !xret_write) begin
        after_minstret = after_minstret + 32'd1;
        if (min_ref == 32'hFFFF_FFFF) after_minstret_hi = minh_ref + 32'd1;
      end
    end
    if (cs_write_en) begin
      if (cs_wsel == CSR_MCYCLE) after_mcycle = newv;
      else if (cs_wsel == CSR_MINSTRT || cs_wsel == CSR_INSTRET) after_minstret = newv;
      else if (cs_wsel == CSR_MINSTRT_H || cs_wsel == CSR_INSTRET_H) after_minstret_hi = newv;
      else if (cs_wsel == CSR_MTIME) after_mcycle = newv;
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
      idex_old =   (idex_rsel == CSR_MSTATUS  ? after_mstatus : 32'h0)
            | (idex_rsel == CSR_MTVEC    ? after_mtvec : 32'h0)
            | (idex_rsel == CSR_MEPC     ? after_mepc : 32'h0)
            | (idex_rsel == CSR_MCAUSE   ? after_mcause : 32'h0)
            | (idex_rsel == CSR_MSCRATCH ? st_mscratch : 32'h0)
            | (idex_rsel == CSR_MISA     ? st_misa : 32'h0)
            | (idex_rsel == CSR_MCYCLE || idex_rsel == CSR_MTIME ? after_mcycle : 32'h0)
            | (idex_rsel == CSR_MINSTRT || idex_rsel == CSR_INSTRET ? after_minstret : 32'h0)
            | (idex_rsel == CSR_MINSTRT_H || idex_rsel == CSR_INSTRET_H ? after_minstret_hi : 32'h0)
            | (idex_rsel == CSR_MCOUNTHI ? after_mcountinhibit : 32'h0)
            | (idex_rsel == CSR_MTIMECMP ? after_mtimecmp : 32'h0)
            | (idex_rsel == CSR_XHALT ? {31'b0, after_halt} : 32'h0);
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
      st_mcycle <= 32'h0;
      st_minstret <= 32'h0;
      st_minstret_hi <= 32'h0;
      st_mcountinhibit <= 32'h0;
      st_mtimecmp <= 32'hFFFF_FFFF;
      st_halt <= 1'b0;
      end else if (!halt_in) begin
        if (retire_en) begin
          if (!inhibit_cycle) st_mcycle <= st_mcycle + 32'd1;
          if (!inhibit_instret && !xret_write) begin
            st_minstret <= st_minstret + 32'd1;
            if (st_minstret == 32'hFFFF_FFFF) st_minstret_hi <= st_minstret_hi + 32'd1;
          end
        end
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
          CSR_MCYCLE:  st_mcycle <= newv;
          CSR_MINSTRT, 12'hc02: st_minstret <= newv;
          CSR_MINSTRT_H, 12'hc82: st_minstret_hi <= newv;
          CSR_MTIME:   st_mcycle <= newv;
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
