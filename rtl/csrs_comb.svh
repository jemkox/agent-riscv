    old = 32'h0;
    if (cs_read_en) begin
      old =   (cs_rsel == CSR_MSTATUS  ? st_mstatus : 32'h0)
            | (cs_rsel == CSR_SSTATUS  ? (st_mstatus & SSTATUS_MASK) : 32'h0)
            | (cs_rsel == CSR_MTVEC    ? st_mtvec : 32'h0)
            | (cs_rsel == CSR_MEPC     ? st_mepc : 32'h0)
            | (cs_rsel == CSR_MCAUSE   ? st_mcause : 32'h0)
            | (cs_rsel == CSR_MTVAL    ? st_mtval : 32'h0)
            | (cs_rsel == CSR_MSCRATCH ? st_mscratch : 32'h0)
            | (cs_rsel == CSR_MISA     ? st_misa : 32'h0)
            | (cs_rsel == CSR_MIE      ? st_mie : 32'h0)
            | (cs_rsel == CSR_MEDELEG  ? st_medeleg : 32'h0)
            | (cs_rsel == CSR_MIDELEG  ? st_mideleg : 32'h0)
            | (cs_rsel == CSR_STVEC    ? st_stvec : 32'h0)
            | (cs_rsel == CSR_SEPC     ? st_sepc : 32'h0)
            | (cs_rsel == CSR_SCAUSE   ? st_scause : 32'h0)
            | (cs_rsel == CSR_STVAL    ? st_stval : 32'h0)
            | (cs_rsel == CSR_SSCRATCH ? st_sscratch : 32'h0)
            | (cs_rsel == CSR_SIE      ? st_sie : 32'h0)
            | (cs_rsel == CSR_SCNTR    ? st_scntr : 32'h0)
            | (cs_rsel == CSR_SATP     ? st_satp : 32'h0)
`ifndef FPGA
            | ((cs_rsel == CSR_MIP || cs_rsel == CSR_MIP_OLD) ? mip_live : 32'h0)
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

    // mstatus / sstatus write-back (sstatus = S-visible subset of mstatus)
    mstatus_wr = st_mstatus;
    if (cs_write_en && (cs_wsel == CSR_SSTATUS))
      mstatus_wr = (st_mstatus & ~SSTATUS_MASK) | (newv & SSTATUS_MASK);
    else if (cs_write_en && (cs_wsel == CSR_MSTATUS)) begin
      if (((newv & MSTATUS_MPP) == 32'h0) ||
          ((newv & MSTATUS_MPP) == 32'h0800) ||
          ((newv & MSTATUS_MPP) == MSTATUS_MPP))
        mstatus_wr = newv;
      else
        mstatus_wr = (newv & ~MSTATUS_MPP) | MSTATUS_MPP;
    end

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
    after_mtval = st_mtval;
    after_mie = st_mie;
    after_medeleg = st_medeleg;
    after_mideleg = st_mideleg;
    after_stvec = st_stvec;
    after_sepc = st_sepc;
    after_scause = st_scause;
    after_stval = st_stval;
    after_sscratch = st_sscratch;
    after_sie = st_sie;
    after_scntr = st_scntr;
    after_halt = st_halt;
    after_mscratch = st_mscratch;
    after_satp = st_satp;
    after_priv = st_priv;
`ifndef FPGA
    after_mip_sw = st_mip_sw;
`endif
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
        if (min_ref == 32'hFFFF_FFFF) after_minstret_hi = minh_ref + 32'd1;
`endif
      end
    end
    if (!halt_in && !reset && cs_write_en) begin
      if (cs_wsel == CSR_MSTATUS || cs_wsel == CSR_SSTATUS) after_mstatus = mstatus_wr;
      else if (cs_wsel == CSR_MTVEC) after_mtvec = newv;
      else if (cs_wsel == CSR_MEPC) after_mepc = newv;
      else if (cs_wsel == CSR_MCAUSE) after_mcause = newv;
      else if (cs_wsel == CSR_MIE) after_mie = newv;
      else if (cs_wsel == CSR_MSCRATCH) after_mscratch = newv;
      else if (cs_wsel == CSR_MEDELEG) after_medeleg = newv;
      else if (cs_wsel == CSR_MIDELEG) after_mideleg = newv;
      else if (cs_wsel == CSR_STVEC) after_stvec = newv;
      else if (cs_wsel == CSR_SEPC) after_sepc = newv;
      else if (cs_wsel == CSR_SCAUSE) after_scause = newv;
      else if (cs_wsel == CSR_STVAL) after_stval = newv;
      else if (cs_wsel == CSR_SSCRATCH) after_sscratch = newv;
      else if (cs_wsel == CSR_SIE) after_sie = newv;
      else if (cs_wsel == CSR_SCNTR) after_scntr = newv;
      else if (cs_wsel == CSR_SATP) after_satp = newv & 32'h803F_FFFF;
      else if (cs_wsel == CSR_XHALT) after_halt = newv[0] ? 1'b1 : after_halt;
`ifndef FPGA
      else if (cs_wsel == CSR_MIP || cs_wsel == CSR_MIP_OLD) after_mip_sw = newv & 32'hFFFF_FF77;
`endif
      else if (cs_wsel == CSR_MCOUNTHI) after_mcountinhibit = newv & 32'h7;
      else begin
        if (cs_wsel == CSR_MCYCLE) after_mcycle = newv;
        else if (cs_wsel == CSR_MINSTRT || cs_wsel == CSR_INSTRET) after_minstret = newv;
        else if (cs_wsel == CSR_MINSTRT_H || cs_wsel == CSR_INSTRET_H) after_minstret_hi = newv;
      end
    end
    idex_old = 32'h0;
    if (idex_read_en) begin
      idex_old =   (idex_rsel == CSR_MSTATUS  ? after_mstatus : 32'h0)
            | (idex_rsel == CSR_SSTATUS ? (after_mstatus & SSTATUS_MASK) : 32'h0)
            | (idex_rsel == CSR_MTVEC    ? after_mtvec : 32'h0)
            | (idex_rsel == CSR_MEPC     ? after_mepc : 32'h0)
            | (idex_rsel == CSR_MCAUSE   ? after_mcause : 32'h0)
            | (idex_rsel == CSR_MTVAL    ? after_mtval : 32'h0)
            | (idex_rsel == CSR_MSCRATCH ? after_mscratch : 32'h0)
            | (idex_rsel == CSR_MISA     ? st_misa : 32'h0)
            | (idex_rsel == CSR_MIE      ? after_mie : 32'h0)
            | (idex_rsel == CSR_MEDELEG  ? after_medeleg : 32'h0)
            | (idex_rsel == CSR_MIDELEG  ? after_mideleg : 32'h0)
            | (idex_rsel == CSR_STVEC    ? after_stvec : 32'h0)
            | (idex_rsel == CSR_SEPC     ? after_sepc : 32'h0)
            | (idex_rsel == CSR_SCAUSE   ? after_scause : 32'h0)
            | (idex_rsel == CSR_STVAL    ? after_stval : 32'h0)
            | (idex_rsel == CSR_SSCRATCH ? after_sscratch : 32'h0)
            | (idex_rsel == CSR_SIE      ? after_sie : 32'h0)
            | (idex_rsel == CSR_SCNTR    ? after_scntr : 32'h0)
            | (idex_rsel == CSR_SATP     ? after_satp : 32'h0)
`ifndef FPGA
             | ((idex_rsel == CSR_MIP || idex_rsel == CSR_MIP_OLD)
                ? (mip_in | (after_mip_sw & 32'hFFFF_FF77)) : 32'h0)
`endif
            | (idex_rsel == CSR_MCYCLE   ? after_mcycle : 32'h0)
            | (idex_rsel == CSR_MINSTRT || idex_rsel == CSR_INSTRET ? after_minstret : 32'h0)
            | (idex_rsel == CSR_MINSTRT_H || idex_rsel == CSR_INSTRET_H ? after_minstret_hi : 32'h0)
            | (idex_rsel == CSR_MCOUNTHI ? after_mcountinhibit : 32'h0)
            | (idex_rsel == CSR_XHALT ? {31'b0, after_halt} : 32'h0);
    end
