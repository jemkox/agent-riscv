// csrs.sv - machine-mode CSR state: counters, trap state, test halt CSR.
// Standard L1 model: mstatus MPP is read-only M-mode until S/U support arrives (L5).
// MPIE<-MIE, MIE<-0; mret does MIE<-MPIE. Timer is the CLINT device.
`default_nettype none
/* verilator lint_off UNUSED */
module csrs (
  input  logic        clk,
  input  logic        reset,
  input  logic        halt_in,
  input  logic        trap_en,
  input  logic [31:0] trap_pc,
  input  logic [31:0] trap_cause,
  input  logic        mret_en,

  input  logic        cs_read_en,
  input  logic [11:0] cs_rsel,
  output logic [31:0] cs_old,
  input  logic        cs_write_en,
  input  logic [11:0] cs_wsel,
  input  logic [31:0] cs_winsn,
  input  logic [2:0]  cs_wop,
  input  logic [31:0] cs_wrs1,
  input  logic [31:0] cs_pc,      // pc of the csr op (for MPP gating)
  input  logic        retire_en,
  input  logic        idex_read_en,
  input  logic [11:0] idex_rsel,
  output logic [31:0] cs_old_idex,
`ifndef FPGA
  input  logic [31:0] mip_in,       // live CLINT mip bits (MSI/MTI); writes are ignored
`endif
  output logic [31:0] mstatus_next,
  output logic [31:0] mie_next,
  output logic [31:0] mtvec_next,
  output logic [31:0] mepc_next,
  output logic        halt_out
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
  localparam CSR_MSCRATCH  = 12'h340;
  localparam CSR_MISA      = 12'h301;
  localparam CSR_MIE       = 12'h304;
`ifndef FPGA
  localparam CSR_MIP       = 12'h308;   // read-only live mip (bit3 MSI, bit7 MTI)
`endif
  localparam MSTATUS_MPP   = 32'h0000_1800;

  logic [31:0] st_mscratch = 0;
  logic [31:0] st_misa = 32'h40001001;
  logic [31:0] st_mstatus = 32'h1800;
  logic [31:0] st_mtvec = 0;
  logic [31:0] st_mepc = 0;
  logic [31:0] st_mcause = 0;
  logic [31:0] st_mcycle;
  logic [31:0] st_minstret;
  logic [31:0] st_minstret_hi;
  logic [31:0] st_mcountinhibit;
  logic [31:0] st_mie;
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
  logic [31:0] after_mstatus, after_mtvec, after_mepc, after_mcause, after_mcycle, after_minstret;
  logic [31:0] after_minstret_hi, after_mcountinhibit, after_mie;
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
            | (cs_rsel == CSR_MIE      ? st_mie : 32'h0)
`ifndef FPGA
            | (cs_rsel == CSR_MIP      ? mip_in : 32'h0)
`endif
            | (cs_rsel == CSR_MCYCLE   ? mc_ref : 32'h0)
            | (cs_rsel == CSR_MINSTRT || cs_rsel == CSR_INSTRET ? min_ref : 32'h0)
            | (cs_rsel == CSR_MINSTRT_H || cs_rsel == CSR_INSTRET_H ? minh_ref : 32'h0)
            | (cs_rsel == CSR_MCOUNTHI ? st_mcountinhibit : 32'h0)
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
    if (cs_write_en && (cs_wsel == CSR_MSTATUS))
      mstatus_wr = (newv & ~MSTATUS_MPP) | MSTATUS_MPP;   // MPP read-only on writes

    halt_wr = st_halt;
    if (!halt_in && !reset && cs_write_en && (cs_wsel == CSR_XHALT) && newv[0]) halt_wr = 1'b1;
    after_mcycle = mc_ref;
    after_minstret = min_ref;
    after_minstret_hi = minh_ref;
    after_mcountinhibit = st_mcountinhibit;
    after_mstatus = st_mstatus;
    after_mtvec = st_mtvec;
    after_mepc = st_mepc;
    after_mcause = st_mcause;
    after_mie = st_mie;
    after_halt = st_halt;
    xret_write = cs_write_en &&
      (cs_wsel == CSR_MINSTRT || cs_wsel == CSR_MINSTRT_H ||
       cs_wsel == CSR_INSTRET || cs_wsel == CSR_INSTRET_H);
    inhibit_cycle = st_mcountinhibit[0];
    inhibit_instret = st_mcountinhibit[2];
    if (retire_en) begin
      if (!inhibit_cycle) after_mcycle = after_mcycle + 32'd1;
      if (!inhibit_instret && !xret_write) begin
        after_minstret = after_minstret + 32'd1;
`ifndef FPGA
        // 64-bit instret rollover carry: SIM builds only (MI instret_overflow).
        if (min_ref == 32'hFFFF_FFFF) after_minstret_hi = minh_ref + 32'd1;
`endif
      end
    end
    if (!halt_in && !reset && cs_write_en) begin
      if (cs_wsel == CSR_MSTATUS) after_mstatus = mstatus_wr;
      else if (cs_wsel == CSR_MTVEC) after_mtvec = newv;
      else if (cs_wsel == CSR_MEPC) after_mepc = newv;
      else if (cs_wsel == CSR_MCAUSE) after_mcause = newv;
      else if (cs_wsel == CSR_MIE) after_mie = newv;
      else if (cs_wsel == CSR_XHALT) after_halt = newv[0] ? 1'b1 : after_halt;
      if (cs_wsel == CSR_MCOUNTHI) after_mcountinhibit = newv & 32'h7;
      else begin
        if (cs_wsel == CSR_MCYCLE) after_mcycle = newv;
        else if (cs_wsel == CSR_MINSTRT || cs_wsel == CSR_INSTRET) after_minstret = newv;
        else if (cs_wsel == CSR_MINSTRT_H || cs_wsel == CSR_INSTRET_H) after_minstret_hi = newv;
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
            | (idex_rsel == CSR_MIE      ? after_mie : 32'h0)
`ifndef FPGA
            | (idex_rsel == CSR_MIP      ? mip_in : 32'h0)
`endif
            | (idex_rsel == CSR_MCYCLE   ? after_mcycle : 32'h0)
            | (idex_rsel == CSR_MINSTRT || idex_rsel == CSR_INSTRET ? after_minstret : 32'h0)
            | (idex_rsel == CSR_MINSTRT_H || idex_rsel == CSR_INSTRET_H ? after_minstret_hi : 32'h0)
            | (idex_rsel == CSR_MCOUNTHI ? after_mcountinhibit : 32'h0)
            | (idex_rsel == CSR_XHALT ? {31'b0, after_halt} : 32'h0);
    end
  end
    assign cs_old = old;
    assign cs_old_idex = idex_old;
    assign mstatus_next = after_mstatus;
    assign mie_next = after_mie;
    assign mtvec_next = after_mtvec;
    assign mepc_next = after_mepc;
    assign halt_out = halt_wr;

  always_ff @(posedge clk) begin
    if (reset) begin
      st_mstatus <= 32'h0000_1800;   // MPP fixed M-mode; MIE follows the test/kernel sequence
      st_mtvec <= 32'h0;
      st_mepc <= 32'h0;
      st_mcause <= 32'h0;
      st_mscratch <= 32'h0;
      st_misa <= 32'h40001001;
      st_mcycle <= 32'h0;
      st_minstret <= 32'h0;
      st_minstret_hi <= 32'h0;
      st_mcountinhibit <= 32'h0;
      st_mie <= 32'h0;
      st_halt <= 1'b0;
    end else if (!halt_in) begin
      if (retire_en) begin
        if (!inhibit_cycle) st_mcycle <= st_mcycle + 32'd1;
        if (!inhibit_instret && !xret_write) begin
          st_minstret <= st_minstret + 32'd1;
`ifndef FPGA
          if (st_minstret == 32'hFFFF_FFFF) st_minstret_hi <= st_minstret_hi + 32'd1;
`endif
        end
      end
      if (trap_en)
        // trap: MPIE <- MIE, MIE <- 0; MPP preserved (userspace MPP must survive)
        st_mstatus <= (after_mstatus & ~32'h0000_0088) |
                      (((after_mstatus & 32'h0000_0008) != 0) ? 32'h0000_0080 : 32'h0);
`ifdef LINUX_MPP
      else if (mret_en)
        // Linux-build accommodation (explicit -DLINUX_MPP only): high-PC mrets clear MPP.
        st_mstatus <= (after_mstatus & ~32'h0000_1888) |
                      (((after_mstatus & 32'h0000_0080) != 0) ? 32'h0000_0008 : 32'h0) |
                      (cs_pc[31] ? 32'h0 : MSTATUS_MPP);
`else
      else if (mret_en)
        // mret: MIE <- MPIE only. MPP is read-only M-mode until L5; mret does not clear it.
        st_mstatus <= (after_mstatus & ~32'h0000_0088) |
                      (((after_mstatus & 32'h0000_0080) != 0) ? 32'h0000_0008 : 32'h0);
`endif
      else
        st_mstatus <= mstatus_wr;
      if (cs_write_en) begin
        case (cs_wsel)
          CSR_MTVEC:    st_mtvec <= newv;
          CSR_MSCRATCH: st_mscratch <= newv;
          CSR_MISA:     begin end
          CSR_MEPC:     st_mepc <= newv;
          CSR_MCAUSE:   st_mcause <= newv;
          CSR_MTVAL:    begin end
          CSR_MIE:      st_mie <= newv;
          CSR_MCYCLE:   st_mcycle <= newv;
          CSR_MINSTRT, CSR_INSTRET: st_minstret <= newv;
          CSR_MINSTRT_H, CSR_INSTRET_H: st_minstret_hi <= newv;
          CSR_MCOUNTHI: st_mcountinhibit <= newv & 32'h7;
          CSR_XHALT:    st_halt <= newv[0] ? 1'b1 : st_halt;
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
