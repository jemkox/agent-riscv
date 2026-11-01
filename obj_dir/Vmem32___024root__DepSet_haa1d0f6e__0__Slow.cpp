// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vmem32.h for the primary calling header

#include "Vmem32__pch.h"
#include "Vmem32___024root.h"

VL_ATTR_COLD void Vmem32___024root___eval_static__TOP(Vmem32___024root* vlSelf);

VL_ATTR_COLD void Vmem32___024root___eval_static(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_static\n"); );
    // Body
    Vmem32___024root___eval_static__TOP(vlSelf);
}

VL_ATTR_COLD void Vmem32___024root___eval_static__TOP(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_static__TOP\n"); );
    // Body
    vlSelf->probe3__DOT__clk = 0U;
    vlSelf->probe3__DOT__lwa = 0U;
    vlSelf->probe3__DOT__lwd = 0U;
}

VL_ATTR_COLD void Vmem32___024root___eval_final(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_final\n"); );
}

VL_ATTR_COLD void Vmem32___024root___eval_settle(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_settle\n"); );
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vmem32___024root___dump_triggers__act(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(vlSelf->__VactTriggered.any())))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 0 is active: @(posedge probe3.clk)\n");
    }
    if ((2ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 1 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

#ifdef VL_DEBUG
VL_ATTR_COLD void Vmem32___024root___dump_triggers__nba(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___dump_triggers__nba\n"); );
    // Body
    if ((1U & (~ (IData)(vlSelf->__VnbaTriggered.any())))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 0 is active: @(posedge probe3.clk)\n");
    }
    if ((2ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 1 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vmem32___024root___ctor_var_reset(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___ctor_var_reset\n"); );
    // Body
    vlSelf->probe3__DOT__clk = VL_RAND_RESET_I(1);
    vlSelf->probe3__DOT__lwa = VL_RAND_RESET_I(32);
    vlSelf->probe3__DOT__lwd = VL_RAND_RESET_I(32);
    for (int __Vi0 = 0; __Vi0 < 65536; ++__Vi0) {
        vlSelf->probe3__DOT__M__DOT__ram[__Vi0] = VL_RAND_RESET_I(32);
    }
    vlSelf->__Vtrigprevexpr___TOP__probe3__DOT__clk__0 = VL_RAND_RESET_I(1);
}
