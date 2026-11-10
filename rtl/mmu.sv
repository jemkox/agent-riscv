// mmu.sv - L6 Sv32 MMU: direct-mapped 4-entry fetch/data TLBs + 2-level walker.
// Walker reads/writes leave through the shared cache access port; grant decisions
// in always_comb never look at p_data/p_ready (no combinational cycle). The PTE
// value is latched (pv) in the clocked block ONLY on a grant cycle where p_ready
// (cache32 mem_ready) says the access completed; own/won (the "data landed" and
// "store committed" state bits) are set with the same gate, so with CACHE_LAT>1
// a cold PTE line keeps the side in its pending state (re-issuing the same
// address via the retry branches) until the fill returns. A/D writes stay held
// (p_we re-issued by the s=2 pending-write retry) until the store commits.
`default_nettype none
/* verilator lint_off UNUSED */
/* verilator lint_off WIDTHEXPAND */
`ifndef FPGA
module mmu (
  input  logic        clk, reset,
  input  logic        mode,     // I-side Sv32 enable (spec: satp never translates M-mode fetches)
  input  logic        dm,       // D-side Sv32 enable (also set for M+MPRV loads/stores)
  input  logic [21:0] sppn,
  input  logic [1:0]  priv,     // I-side privilege
  input  logic [1:0]  dpriv,    // D-side effective privilege (MPRV at M maps MPP's priv)
  input  logic        sum, mxr,
  input  logic        flush,
  input  logic [31:0] if_va,
  input  logic        if_on,
  output logic        if_hit, if_fault, if_stall,
  output logic [31:0] if_pa,
  input  logic [31:0] df_va,
  input  logic        df_on,
  input  logic        df_r, df_w,
  output logic        df_hit, df_fault, df_stall,
  output logic [31:0] df_pa,
  output logic [3:0]  df_cause,
  output logic        p_ld, p_we,
  output logic [31:0] p_a, p_wa, p_wd,
  input  logic [31:0] p_data,
  input  logic        p_ready   // cache32 mem_ready: the shared-port access done
);
  logic [3:0]  tv_i = 0, tv_d = 0;
  logic [19:0] tg_i [0:3], tg_d [0:3];
  logic [21:0] ppa_i [0:3], ppa_d [0:3];
  logic [6:0]  fg_i [0:3], fg_d [0:3];
  logic [1:0]  s_i = 0, s_d = 0;   // 0 idle 1 pending-read 2 pending-write 3 fault-hold
  logic        own_i = 0, own_d = 0, won_i = 0, won_d = 0;
  logic        lvl_i = 0, lvl_d = 0;
  logic [19:0] wt_i = 20'hFFFFF, wt_d = 20'hFFFFF;
  logic [31:0] pv_i = 0, pv_d = 0, ra_i = 0, ra_d = 0;
  logic        fcsr_i = 0, fcsr_d = 0;   // last s==3 fault was a pure permission fault (CSR-healable)
  logic [31:0] cap_i = 0, cap_d = 0, wda_i = 0, wda_d = 0, wdv_i = 0, wdv_d = 0;

  logic [19:0] tag_i, tag_d;
  assign tag_i = if_va[31:12];
  assign tag_d = df_va[31:12];
  logic hit_i, hit_d;
  assign hit_i = mode && tv_i[tag_i[1:0]] && (tg_i[tag_i[1:0]] == tag_i);
  assign hit_d = dm && tv_d[tag_d[1:0]] && (tg_d[tag_d[1:0]] == tag_d);

  function logic pbad (input [4:0] f, input logic rd, input logic wr,
                      input [1:0] pr, input logic sm, input logic mx);
    logic r, w, x, u, ok;
    // spec PTE bits (callers pass f = {lvl, pv1, pv2, pv3, pv4}): R=bit1 W=bit2
    // X=bit3 U=bit4 -> load needs f[3]=R, fetch needs f[1]=X.
    r = f[3]; w = f[2]; x = f[1]; u = f[0];
    ok = 1;
    if (!rd && !wr) begin
      if (!x) ok = 0;
      // S NEVER fetches a U page: mstatus.SUM only governs S loads/stores (spec
      // access-control table; arch-test Sv_sv32_upage_mstatus_sum_set_Smode faults
      // the jalr even with SUM set). M may fetch anything permitted.
      if (u && pr == 2'b01) ok = 0;
    end else begin
      if (rd && !(r || (pr == 2'b01 && x && mx))) ok = 0;  // MXR rescues x-only loads at S-effective priv only (spec); U eff needs r (t43 pins via MPRV+MPP=U)
      if (wr && !w) ok = 0;
    end
    if (pr == 2'b00 && !u) ok = 0;
    if (pr == 2'b01 && (rd || wr) && u && !sm) ok = 0;
    pbad = !ok;
  endfunction

  logic hb_i, hb_d, nw_i, nw_d, hit_ok_i, hit_ok_d;
  assign hb_i = hit_i && pbad(fg_i[tag_i[1:0]][3:0], 0, 0, priv, sum, mxr);
  assign hb_d = hit_d && pbad(fg_d[tag_d[1:0]][3:0], df_r, df_w, dpriv, sum, mxr);
  // A/D bits live in entry flags [5:4]; a hit missing them must re-walk so the
  // PTE A/D update happens (parity with the reference model).
  assign nw_i = hit_i && !fg_i[tag_i[1:0]][5];
  assign nw_d = df_on && hit_d && (!fg_d[tag_d[1:0]][5] || (df_w && !fg_d[tag_d[1:0]][4]));
  assign hit_ok_i = hit_i && !nw_i;
  assign hit_ok_d = hit_d && !nw_d;

  assign if_hit = hit_ok_i;
  assign df_hit = hit_ok_d;
  assign if_pa = hit_ok_i ? (fg_i[tag_i[1:0]][6] ? {ppa_i[tag_i[1:0]][19:10], if_va[21:0]}
                      : {ppa_i[tag_i[1:0]][19:0], if_va[11:0]}) : 32'h0;
  assign df_pa = hit_ok_d ? (fg_d[tag_d[1:0]][6] ? {ppa_d[tag_d[1:0]][19:10], df_va[21:0]}
                      : {ppa_d[tag_d[1:0]][19:0], df_va[11:0]}) : 32'h0;
  // A previously faulted entry (s==3) whose latched PTE is now permitted due to
  // a CSR change (SUM/MXR/priv) self-heals: fill the TLB and proceed instead of
  // re-faulting (matches the reference model re-walking every access).
  logic heal_i, heal_d;
  assign heal_i = mode && if_on && s_i == 2'b11 && wt_i == tag_i && fcsr_i &&
                  !pbad({lvl_i, pv_i[1], pv_i[2], pv_i[3], pv_i[4]}, 0, 0, priv, sum, mxr);
  assign heal_d = dm && df_on && s_d == 2'b11 && wt_d == tag_d && fcsr_d &&
                  !pbad({lvl_d, pv_d[1], pv_d[2], pv_d[3], pv_d[4]}, df_r, df_w, dpriv, sum, mxr);
  assign if_fault = (hit_ok_i && hb_i) || (mode && s_i == 2'b11 && wt_i == tag_i && !heal_i);
  assign df_fault = df_on && ((hit_ok_d && hb_d) || (dm && s_d == 2'b11 && wt_d == tag_d && !heal_d));
  assign df_cause = df_w ? 4'hF : 4'hD;
  assign if_stall = mode && if_on && !hit_ok_i;
  assign df_stall = dm && df_on && !hit_ok_d;

  logic [9:0] vp1_i, vp0_i, vp1_d, vp0_d;
  logic [31:0] l1a_i, l1a_d;
  assign vp1_i = if_va[31:22];
  assign vp0_i = if_va[21:12];
  assign vp1_d = df_va[31:22];
  assign vp0_d = df_va[21:12];
  assign l1a_i = {sppn[19:0], vp1_i, 2'b0};   // (PPN<<12 + VPN1*4) mod 2^32
  assign l1a_d = {sppn[19:0], vp1_d, 2'b0};

  logic ev_i, ev_d;                 // evaluating latched read this cycle
  logic [2:0] fa, fd;               // 0 none 1 fault 2 write-adi 3 fill 4 descend
  logic cperm_i, cperm_d;           // this ev fault (if any) is a pure permission fault
  logic fcsr_ni, fcsr_nd;           // next fcsr state
  logic wi_r, wi_w, wd_r, wd_w;
  logic g_r_i, g_r_d, g_w_i, g_w_d;
  logic iss_i, iss_d;               // read issued by this side this cycle (latch p_data)
  logic [1:0] ns_i, ns_d;
  logic own_ni, own_nd, won_ni, won_nd, lvl_ni, lvl_nd;
  logic [19:0] nwt_i, nwt_d;
  logic [31:0] nra_i, nra_d, ncap_i, ncap_d, nwda_i, nwda_d, nwdv_i, nwdv_d;
  logic fi_i, fi_d;
  logic [21:0] fpa_i, fpa_d;
  logic [6:0]  ffl_i, ffl_d;

  always_comb begin
    ns_i = s_i; ns_d = s_d;
    own_ni = 0; own_nd = 0; won_ni = 0; won_nd = 0;
    lvl_ni = lvl_i; lvl_nd = lvl_d;
    nwt_i = wt_i; nwt_d = wt_d;
    nra_i = ra_i; nra_d = ra_d;
    ncap_i = cap_i; ncap_d = cap_d; nwda_i = wda_i; nwda_d = wda_d;
    nwdv_i = wdv_i; nwdv_d = wdv_d;
    fi_i = 0; fpa_i = 0; ffl_i = 0; fi_d = 0; fpa_d = 0; ffl_d = 0;
    wi_r = 0; wi_w = 0; wd_r = 0; wd_w = 0;
    iss_i = 0; iss_d = 0;
    p_ld = 0; p_we = 0; p_a = 0; p_wa = 0; p_wd = 0;
    fa = 0; fd = 0;
    cperm_i = 0; cperm_d = 0;
    fcsr_ni = fcsr_i; fcsr_nd = fcsr_d;

    ev_i = mode && if_on && s_i == 2'b01 && own_i && tag_i == wt_i;
    ev_d = dm && df_on && s_d == 2'b01 && own_d && tag_d == wt_d;
    if (ev_i) begin
      if (!pv_i[0]) fa = 1;
      else if (pv_i[3:1] != 0) begin
        if (lvl_i && pv_i[19:10] != 0) fa = 1;
        else if (pbad({lvl_i, pv_i[1], pv_i[2], pv_i[3], pv_i[4]}, 0, 0, priv, sum, mxr)) begin fa = 1; cperm_i = 1; end
        else if (!pv_i[6]) fa = 2;
        else fa = 3;
      end else if (lvl_i) fa = 4;
      else fa = 1;
    end
    if (ev_d) begin
      if (!pv_d[0]) fd = 1;
      else if (pv_d[3:1] != 0) begin
        if (lvl_d && pv_d[19:10] != 0) fd = 1;
        else if (pbad({lvl_d, pv_d[1], pv_d[2], pv_d[3], pv_d[4]}, df_r, df_w, dpriv, sum, mxr)) begin fd = 1; cperm_d = 1; end
        else if (!pv_d[6] || (df_w && !pv_d[7])) fd = 2;
        else fd = 3;
      end else if (lvl_d) fd = 4;
      else fd = 1;
    end
`ifdef LINUX_DEBUG
    if (fa == 1)
      $display("MMUI va=%08x pv=%08x lvl=%b vp=%03x sppn=%05x priv=%b sum=%b mxr=%b perm=%b", if_va, pv_i, lvl_i, vp1_i, sppn, priv, sum, mxr, cperm_i);
    if (fd == 1)
      $display("MMUD va=%08x pv=%08x lvl=%b vp=%03x sppn=%05x priv=%b sum=%b mxr=%b rw=%b%b perm=%b", df_va, pv_d, lvl_d, vp1_d, sppn, dpriv, sum, mxr, df_r, df_w, cperm_d);
`endif

    // want flags (depend on state/pv only, never on port outputs)
    if (s_i == 2'b00)                     wi_r = mode && if_on && !hit_ok_i;
    else if (s_i == 2'b01) begin
      if (tag_i != wt_i || !own_i)        wi_r = mode && if_on;      // restart / reissue
      else if (fa == 4)                   wi_r = mode && if_on;      // descend read
      else if (fa == 2)                   wi_w = 1;                  // queue A/D write
    end else if (s_i == 2'b10) begin
      if (!won_i)                         wi_w = mode && if_on;      // (re)issue write
    end else if (s_i == 2'b11) begin
      if (tag_i != wt_i)                  wi_r = mode && if_on;      // restart / reissue
      else if (heal_i) begin
        // CSRs changed since the fault (SUM/MXR/priv): the latched PTE is now
        // permitted -> fill and let the access proceed (reference model re-walks).
        ns_i = 2'b00; fi_i = 1; fpa_i = pv_i[31:10];
        ffl_i = {lvl_i, pv_i[6], pv_i[7], pv_i[1], pv_i[2], pv_i[3], pv_i[4]};
      end
    end
    if (s_d == 2'b00)                     wd_r = dm && df_on && !hit_ok_d;
    else if (s_d == 2'b01) begin
      if (tag_d != wt_d || !own_d)        wd_r = dm && df_on;
      else if (fd == 4)                   wd_r = dm && df_on;
      else if (fd == 2)                   wd_w = 1;
    end else if (s_d == 2'b10) begin
      if (!won_d)                         wd_w = dm && df_on;
    end else if (s_d == 2'b11) begin
      if (tag_d != wt_d)                  wd_r = dm && df_on;      // restart / reissue
      else if (heal_d) begin
        // CSR change since the fault made the latched PTE legal -> fill, proceed.
        ns_d = 2'b00; fi_d = 1; fpa_d = pv_d[31:10];
        ffl_d = {lvl_d, pv_d[6], pv_d[7], pv_d[1], pv_d[2], pv_d[3], pv_d[4]};
      end
    end

    g_w_d = wd_w;
    g_w_i = wi_w && !wd_w;
    g_r_d = wd_r && !g_w_d && !g_w_i;
    g_r_i = wi_r && !g_w_d && !g_w_i && !g_r_d;

    // fetch transitions
    if (s_i == 2'b10) begin
      if (won_i) begin
        ns_i = 2'b00; fi_i = 1; fpa_i = cap_i[31:10];
        ffl_i = {lvl_i, wdv_i[6], wdv_i[7], wdv_i[1], wdv_i[2], wdv_i[3], wdv_i[4]};
      end else if (g_w_i) begin
        p_we = 1; p_wa = wda_i; p_wd = wdv_i; won_ni = 1;
      end
    end else if (ev_i) begin
      if (fa == 1) begin ns_i = 2'b11; nwt_i = tag_i; fcsr_ni = cperm_i; end
      else if (fa == 2) begin
        ns_i = 2'b10; ncap_i = pv_i; nwda_i = ra_i; nwdv_i = pv_i | 32'h40;
      end else if (fa == 3) begin
        ns_i = 2'b00; fi_i = 1; fpa_i = pv_i[31:10];
        ffl_i = {lvl_i, pv_i[6], pv_i[7], pv_i[1], pv_i[2], pv_i[3], pv_i[4]};
      end else if (fa == 4 && g_r_i) begin
        ns_i = 2'b01; own_ni = 1; lvl_ni = 0; iss_i = 1;
        nra_i = {pv_i[29:10], vp0_i, 2'b0};
        p_ld = 1; p_a = nra_i;
      end else if (fa == 4) ns_i = 2'b01;   // descend issue lost: retry (own_ni=0)
    end else if (s_i == 2'b00 && wi_r && g_r_i) begin
      ns_i = 2'b01; own_ni = 1; iss_i = 1; lvl_ni = 1; nwt_i = tag_i; nra_i = l1a_i;
      p_ld = 1; p_a = l1a_i;
    end else if ((s_i == 2'b01 || s_i == 2'b11) && wi_r && g_r_i) begin
      ns_i = 2'b01; own_ni = 1; iss_i = 1;
      if (tag_i == wt_i && s_i == 2'b01) p_a = ra_i;          // reissue same stage
      else begin p_a = l1a_i; lvl_ni = 1; nwt_i = tag_i; nra_i = l1a_i; end  // restart / new
      p_ld = 1;
    end

    // data transitions
    if (s_d == 2'b10) begin
      if (won_d) begin
        ns_d = 2'b00; fi_d = 1; fpa_d = cap_d[31:10];
        ffl_d = {lvl_d, wdv_d[6], wdv_d[7], wdv_d[1], wdv_d[2], wdv_d[3], wdv_d[4]};
      end else if (g_w_d) begin
        p_we = 1; p_wa = wda_d; p_wd = wdv_d; won_nd = 1;
      end
    end else if (ev_d) begin
      if (fd == 1) begin ns_d = 2'b11; nwt_d = tag_d; fcsr_nd = cperm_d; end
      else if (fd == 2) begin
        ns_d = 2'b10; ncap_d = pv_d; nwda_d = ra_d;
        nwdv_d = pv_d | 32'h40 | (df_w ? 32'h80 : 32'h0);
      end else if (fd == 3) begin
        ns_d = 2'b00; fi_d = 1; fpa_d = pv_d[31:10];
        ffl_d = {lvl_d, pv_d[6], pv_d[7], pv_d[1], pv_d[2], pv_d[3], pv_d[4]};
      end else if (fd == 4 && g_r_d) begin
        ns_d = 2'b01; own_nd = 1; lvl_nd = 0; iss_d = 1;
        nra_d = {pv_d[29:10], vp0_d, 2'b0};
        p_ld = 1; p_a = nra_d;
      end else if (fd == 4) ns_d = 2'b01;
    end else if (s_d == 2'b00 && wd_r && g_r_d) begin
      ns_d = 2'b01; own_nd = 1; iss_d = 1; lvl_nd = 1; nwt_d = tag_d; nra_d = l1a_d;
      p_ld = 1; p_a = l1a_d;
    end else if ((s_d == 2'b01 || s_d == 2'b11) && wd_r && g_r_d) begin
      ns_d = 2'b01; own_nd = 1; iss_d = 1;
      if (tag_d == wt_d && s_d == 2'b01) p_a = ra_d;
      else begin p_a = l1a_d; lvl_nd = 1; nwt_d = tag_d; nra_d = l1a_d; end
      p_ld = 1;
    end
  end

  always_ff @(posedge clk) begin
    if (reset || flush) begin
      tv_i <= 0; tv_d <= 0;
      s_i <= 0; s_d <= 0; own_i <= 0; own_d <= 0; won_i <= 0; won_d <= 0;
    end else begin
      s_i <= ns_i; s_d <= ns_d;
      own_i <= own_ni && (!iss_i || p_ready); own_d <= own_nd && (!iss_d || p_ready);
      won_i <= won_ni && (!g_w_i || p_ready); won_d <= won_nd && (!g_w_d || p_ready);
      lvl_i <= lvl_ni; lvl_d <= lvl_nd;
      wt_i <= nwt_i; wt_d <= nwt_d;
      fcsr_i <= fcsr_ni; fcsr_d <= fcsr_nd;
      ra_i <= nra_i; ra_d <= nra_d;
      cap_i <= ncap_i; cap_d <= ncap_d;
      wda_i <= nwda_i; wda_d <= nwda_d;
      wdv_i <= nwdv_i; wdv_d <= nwdv_d;
      if (iss_i && p_ready) pv_i <= p_data;
      if (iss_d && p_ready) pv_d <= p_data;
`ifdef SCDBG2
      if (mode)
        $display("MMUW s_i=%0d o_i=%0d l_i=%0d t_i=%x w_i=%x pv_i=%x f_i=%x n_i=%x iss_i=%x p_ld=%x p_a=%x r=%x va=%x s_d=%0d o_d=%0d l_d=%0d t_d=%x w_d=%x pv_d=%x f_d=%x n_d=%x iss_d=%x fc_i=%b fc_d=%b tv=%b tg=%x fg=%x fgA=%b",
                 s_i, own_i, lvl_i, tag_i, wt_i, pv_i, fa, ns_i, iss_i, p_ld, p_a,
                 ra_i, if_va,
                 s_d, own_d, lvl_d, tag_d, wt_d, pv_d, fd, ns_d, iss_d,
                 fcsr_i, fcsr_d,
                 tv_i[tag_i[1:0]], tg_i[tag_i[1:0]], fg_i[tag_i[1:0]], fg_i[tag_i[1:0]][5]);
`endif
      if (fi_i) begin
        tv_i[tag_i[1:0]] <= 1; tg_i[tag_i[1:0]] <= tag_i;
        ppa_i[tag_i[1:0]] <= fpa_i; fg_i[tag_i[1:0]] <= ffl_i;
      end
      if (fi_d) begin
        tv_d[tag_d[1:0]] <= 1; tg_d[tag_d[1:0]] <= tag_d;
        ppa_d[tag_d[1:0]] <= fpa_d; fg_d[tag_d[1:0]] <= ffl_d;
      end
    end
  end
endmodule
`endif
/* verilator lint_on UNUSED */
