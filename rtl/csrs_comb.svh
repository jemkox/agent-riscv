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
    if (cs_write_en && (cs_wsel == CSR_MSTATUS)) begin
      if (((newv & MSTATUS_MPP) == 32'h0) ||
          ((newv & MSTATUS_MPP) == MSTATUS_MPP))
        mstatus_wr = (newv & ~MSTATUS_MPP) | (newv & MSTATUS_MPP);
      else
        mstatus_wr = (newv & ~MSTATUS_MPP) | MSTATUS_MPP;   // WARL illegal MPP -> M
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
    after_mie = st_mie;
    after_halt = st_halt;
    after_mscratch = st_mscratch;
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
      else if (cs_wsel == CSR_MSCRATCH) after_mscratch = newv;
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
            | (idex_rsel == CSR_MSCRATCH ? after_mscratch : 32'h0)
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
