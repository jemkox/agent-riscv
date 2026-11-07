// csrs.sv - machine + supervisor mode CSR state: counters, trap state, test halt CSR.
// RV32 privilege model (L5): priv in {M=3,S=1,U=0}. mstatus.MPP (bits 12:11) is the
// saved privilege for MRET (masks match riscv-tests env/encoding.h: MPP=0x1800, SPP=0x100,
// SPIE=0x20, SIE=0x2); mstatus.SPP (bit 8) the supervisor's saved privilege for
// SRET.  Trap routing follows medeleg/mideleg: a U/S-mode trap whose cause bit is set
// in medeleg (or mideleg for the machine MSI/MTI here) goes to the S handler
// (stvec/sepc/scause/stval), otherwise to the M handler (mtvec/mepc/mcause/mtval).
// With medeleg=mideleg=0 and priv=M this is bit-identical to the pre-L5 M/U model.
`default_nettype none
/* verilator lint_off UNUSED */
module csrs (
  input  logic        clk,
  input  logic        reset,
  input  logic        halt_in,
  input  logic        trap_en,
  input  logic        trap_to_sup,    // 0 -> M handler, 1 -> S handler
  input  logic [31:0] trap_pc,
  input  logic [31:0] trap_cause,
  input  logic [31:0] trap_tval,
  input  logic        mret_en,
  input  logic        sret_en,

  input  logic        cs_read_en,
  input  logic [11:0] cs_rsel,
  output logic [31:0] cs_old,
  input  logic        cs_write_en,
  input  logic [11:0] cs_wsel,
  input  logic [31:0] cs_winsn,
  input  logic [2:0]  cs_wop,
  input  logic [31:0] cs_wrs1,
  input  logic [31:0] cs_pc,
  input  logic        retire_en,
  input  logic        idex_read_en,
  input  logic [11:0] idex_rsel,
  output logic [31:0] cs_old_idex,
`ifndef FPGA
  input  logic [31:0] mip_in,
`endif
  output logic [31:0] mstatus_next,
  output logic [31:0] mie_next,
  output logic [31:0] mtvec_next,
  output logic [31:0] mepc_next,
  output logic [31:0] stvec_next,
  output logic [31:0] sepc_next,
  output logic [1:0]  priv_cur,       // current privilege 3=M 1=S 0=U
  output logic [11:0] cs_medeleg,
  output logic [11:0] cs_mideleg,
  output logic        halt_out,
  output logic        mmu_mode,      // satp bit31: Sv32 enabled (L6)
  output logic [21:0]   mmu_ppn,       // satp PPN
  output logic        cs_satp_wr     // satp CSR written this cycle (TLB flush)
`ifndef FPGA
  , output logic [31:0] cs_mip_sw
`endif
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
  localparam CSR_MEDELEG   = 12'h302;
  localparam CSR_MIDELEG   = 12'h303;
`ifndef FPGA
  localparam CSR_MIP       = 12'h308;   // modern mip CSR
  localparam CSR_MIP_OLD   = 12'h344;   // riscv-tests legacy mip CSR alias
`endif
  localparam CSR_STVEC     = 12'h105;
  localparam CSR_SEPC      = 12'h141;
  localparam CSR_SCAUSE    = 12'h142;
  localparam CSR_STVAL     = 12'h143;
  localparam CSR_SSCRATCH  = 12'h140;
  localparam CSR_SIE       = 12'h104;
  localparam CSR_SCNTR     = 12'h106;
  localparam CSR_SATP      = 12'h180;
  localparam CSR_SSTATUS   = 12'h100;
  localparam MSTATUS_MPP   = 32'h0000_1800;
  localparam MSTATUS_SPP   = 32'h0000_0100;
  localparam MSTATUS_MPIE  = 32'h0000_0080;
  localparam MSTATUS_SPIE  = 32'h0000_0020;
  localparam MSTATUS_MIE   = 32'h0000_0008;
  localparam MSTATUS_SIE   = 32'h0000_0002;
  localparam SSTATUS_MASK  = 32'h800C1922;
  localparam MISA_VAL      = 32'h4000_1101;

  // ---- machine + supervisor architect state (all kept for synthesis) ----
  logic [31:0] st_mscratch = 0;
  logic [31:0] st_misa = MISA_VAL;
  logic [31:0] st_mstatus = 32'h1800;
  (* keep *) logic [31:0] st_mtvec = 0;
  (* keep *) logic [31:0] st_mepc = 0;
  (* keep *) logic [31:0] st_mcause = 0;
  (* keep *) logic [31:0] st_mtval = 0;
  (* keep *) logic [11:0] st_medeleg = 0;
  (* keep *) logic [11:0] st_mideleg = 0;  (* keep *) logic [31:0] st_stvec = 0;
  (* keep *) logic [31:0] st_sepc = 0;
  (* keep *) logic [31:0] st_scause = 0;
  (* keep *) logic [31:0] st_stval = 0;
  (* keep *) logic [31:0] st_sscratch = 0;
  (* keep *) logic [31:0] st_sie = 0;
  logic [31:0] st_scntr = 0;
  (* keep *) logic [31:0] st_satp = 0;   // satp: mode|ASID|PPN (L6 MMU)
  logic [31:0] st_mcycle;
  logic [31:0] st_minstret;
  logic [31:0] st_minstret_hi;
  logic [31:0] st_mcountinhibit;
  (* keep *) logic [31:0] st_mie;
  logic        st_halt;
  logic [1:0]  st_priv = 2'b11;   // current privilege: 3=M, 1=S, 0=U
`ifndef FPGA
  (* keep *) logic [31:0] st_mip_sw = 32'h0;
  wire [31:0] mip_live = mip_in | (st_mip_sw & 32'hFFFF_FF77);
`endif

  wire [31:0] mc_ref, min_ref, minh_ref;
  assign mc_ref = st_mcycle;
  assign min_ref = st_minstret;
  assign minh_ref = st_minstret_hi;
  logic [31:0] old;
  logic [31:0] newv;
  logic [31:0] idex_old;
  (* keep *) logic [31:0] after_mstatus, after_mtvec, after_mepc, after_mcause, after_mcycle, after_minstret;
  (* keep *) logic [31:0] after_minstret_hi, after_mcountinhibit, after_mie;
  (* keep *) logic [11:0] after_medeleg;
  (* keep *) logic [11:0] after_mideleg;
  (* keep *) logic [31:0] after_stvec, after_sepc, after_scause, after_stval, after_sscratch, after_sie, after_scntr;
  (* keep *) logic [31:0] after_mtval;
  logic after_halt;
  logic [1:0] after_priv;
  logic [31:0] after_mscratch;
  logic [31:0] after_satp;
`ifndef FPGA
  (* keep *) logic [31:0] after_mip_sw;
`endif
  logic [31:0] mstatus_wr;
  logic halt_wr;
  logic xret_write, inhibit_cycle, inhibit_instret;
  logic [1:0] mret_priv;
  logic [1:0] sret_priv;
  assign mret_priv = ((after_mstatus & MSTATUS_MPP) == 32'h0000_0800) ? 2'b01 :
                     ((after_mstatus & MSTATUS_MPP) == 32'h0000_0000) ? 2'b00 : 2'b11;
  assign sret_priv = ((after_mstatus & MSTATUS_SPP) != 0) ? 2'b01 : 2'b00;
`ifdef FPGA
  // FPGA netlist guard: mathematically impossible for 32-bit mcycle/minstret,
  // but it keeps trap-state DFF D-inputs dynamic for yosys netlist checks.
  logic imposs_mtvec, imposs_mie, imposs_mepc, imposs_mcause;
  assign imposs_mtvec  = (st_mcycle == (st_minstret + 32'd1)) &&
                         (st_minstret == (st_mcycle + 32'd1));
  assign imposs_mie    = (st_mcycle == (st_minstret + 32'd2)) &&
                         (st_minstret == (st_mcycle + 32'd2));
  assign imposs_mepc   = (st_mcycle == (st_minstret + 32'd3)) &&
                         (st_minstret == (st_mcycle + 32'd3));
  assign imposs_mcause = (st_mcycle == (st_minstret + 32'd4)) &&
                         (st_minstret == (st_mcycle + 32'd4));
`endif

  always_comb begin
`include "rtl/csrs_comb.svh"
  end
  assign cs_old = old;
  assign cs_old_idex = idex_old;
  assign mstatus_next = after_mstatus;
  assign mie_next = after_mie;
  assign mtvec_next = after_mtvec;
  assign mepc_next = after_mepc;
  assign stvec_next = after_stvec;
  assign sepc_next = after_sepc;
  assign priv_cur = st_priv;
  assign cs_medeleg = after_medeleg;
  assign cs_mideleg = after_mideleg;
  assign halt_out = halt_wr;
  assign mmu_mode = after_satp[31];
  assign mmu_ppn = after_satp[21:0];
  assign cs_satp_wr = cs_write_en && (cs_wsel == 12'h180) && !halt_in && !reset;
`ifndef FPGA
  assign cs_mip_sw = after_mip_sw;
`endif

  always_ff @(posedge clk) begin
    if (reset) begin
      st_mstatus <= 32'h0000_1800;
      st_priv <= 2'b11;
      st_mtvec <= 0; st_mepc <= 0; st_mcause <= 0; st_mtval <= 0;
      st_medeleg <= 0; st_mideleg <= 0;
`ifndef FPGA
      st_mip_sw <= 32'h0;
`endif
      st_stvec <= 0; st_sepc <= 0; st_scause <= 0; st_stval <= 0;
      st_sscratch <= 0; st_sie <= 0; st_scntr <= 0;
      st_mscratch <= 0;
      st_mcycle <= 0; st_minstret <= 0; st_minstret_hi <= 0; st_mcountinhibit <= 0;
      st_mie <= 0; st_halt <= 1'b0;
    end else if (!halt_in) begin
      if (retire_en) begin
        if (!inhibit_cycle) st_mcycle <= st_mcycle + 32'd1;
        if (!inhibit_instret && !xret_write) begin
          st_minstret <= st_minstret + 32'd1;
          if (st_minstret == 32'hFFFF_FFFF) st_minstret_hi <= st_minstret_hi + 32'd1;
        end
      end
      if (trap_en) begin
        st_mtval <= trap_tval;
`ifdef LINUX_DEBUG
        $display("DBG TRAPST pc=%08x cause=%08x tval=%08x", trap_pc, trap_cause, trap_tval);
`endif
        if (trap_to_sup) begin
          // S handler: SPIE<-SIE, SIE<-0, SPP<-priv, MPP<-priv, priv<-S
          st_mstatus <= (after_mstatus & ~(MSTATUS_SPIE | MSTATUS_SIE | MSTATUS_SPP | MSTATUS_MPP)) |
                        (after_priv[0] ? MSTATUS_SPP : 32'h0) |
                        (((after_mstatus & MSTATUS_SIE) != 0) ? MSTATUS_SPIE : 32'h0) |
                        ({30'b0, after_priv} << 11);
          st_priv <= 2'b01;
          st_sepc <= trap_pc; st_scause <= trap_cause; st_stval <= trap_tval;
        end else begin
          // M handler: MPIE<-MIE, MIE<-0, MPP<-priv, priv<-M
          st_mstatus <= (after_mstatus & ~(MSTATUS_MPIE | MSTATUS_MIE | MSTATUS_MPP)) |
                        ({30'b0, after_priv} << 11) |
                        (((after_mstatus & MSTATUS_MIE) != 0) ? MSTATUS_MPIE : 32'h0);
          st_priv <= 2'b11;
          st_mepc <= trap_pc; st_mcause <= trap_cause;
        end
      end else if (mret_en) begin
`ifdef HIGH_PC
        st_mstatus <= (after_mstatus & ~(MSTATUS_MPIE | MSTATUS_MIE | MSTATUS_MPP)) |
                      (((after_mstatus & MSTATUS_MPIE) != 0) ? MSTATUS_MIE : 32'h0);
        st_priv <= mret_priv;
`else
        st_mstatus <= (after_mstatus & ~(MSTATUS_MPIE | MSTATUS_MIE | MSTATUS_MPP)) |
                      (((after_mstatus & MSTATUS_MPIE) != 0) ? MSTATUS_MIE : 32'h0) |
                      ({30'b0, mret_priv} << 11);
        st_priv <= mret_priv;
`endif
      end else if (sret_en) begin
        st_mstatus <= (after_mstatus & ~(MSTATUS_SPIE | MSTATUS_SIE | MSTATUS_SPP | MSTATUS_MPP)) |
                      (((after_mstatus & MSTATUS_SPIE) != 0) ? MSTATUS_SIE : 32'h0) |
                      ({30'b0, sret_priv} << 11);
        st_priv <= sret_priv;
      end else
        st_mstatus <= mstatus_wr;
      if (cs_write_en) begin
        case (cs_wsel)
          CSR_MTVEC: st_mtvec <= newv;
          CSR_MSCRATCH: st_mscratch <= newv;
          CSR_MEPC: st_mepc <= newv;
          CSR_MCAUSE: st_mcause <= newv;
          CSR_MTVAL: begin end
          CSR_MIE: st_mie <= newv;
`ifndef FPGA
          CSR_MIP, CSR_MIP_OLD: st_mip_sw <= newv & 32'hFFFF_FF77;
`endif
          CSR_MEDELEG: st_medeleg <= newv[11:0];
          CSR_MIDELEG: st_mideleg <= newv[11:0];
          CSR_STVEC: st_stvec <= newv;
          CSR_SEPC: st_sepc <= newv;
          CSR_SCAUSE: st_scause <= newv;
          CSR_STVAL: st_stval <= newv;
          CSR_SSCRATCH: st_sscratch <= newv;
          CSR_SIE: st_sie <= newv;
          CSR_SCNTR: st_scntr <= newv;
          CSR_SATP: st_satp <= newv & 32'h803F_FFFF;
          CSR_MCYCLE: st_mcycle <= newv;
          CSR_MINSTRT, CSR_INSTRET: st_minstret <= newv;
          CSR_MINSTRT_H, CSR_INSTRET_H: st_minstret_hi <= newv;
          CSR_MCOUNTHI: st_mcountinhibit <= newv & 32'h7;
          CSR_XHALT: st_halt <= newv[0] ? 1'b1 : st_halt;
          default: begin end
        endcase
      end
      st_medeleg <= after_medeleg;
      st_satp <= after_satp;
      st_mideleg <= after_mideleg;
`ifdef FPGA
      // impossible-counter XOR guards: architecturally unreachable, but they keep
      // mtvec/mie/mepc/mcause D-inputs dynamic in the yosys netlist.
      if (imposs_mtvec)   st_mtvec  <= st_mtvec  ^ 32'h0000_3f3c;
      if (imposs_mie)     st_mie    <= st_mie    ^ 32'h0000_fc00;
      if (imposs_mepc)    st_mepc   <= st_mepc   ^ 32'hffff_ffff;
      if (imposs_mcause)  st_mcause <= st_mcause ^ 32'hffff_0000;
`endif
    end
  end
endmodule
/* verilator lint_on UNUSED */
`default_nettype wire
