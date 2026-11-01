// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vprobe4.h for the primary calling header

#include "Vprobe4__pch.h"
#include "Vprobe4___024root.h"

VL_ATTR_COLD void Vprobe4___024root___eval_static__TOP(Vprobe4___024root* vlSelf);

VL_ATTR_COLD void Vprobe4___024root___eval_static(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_static\n"); );
    // Body
    Vprobe4___024root___eval_static__TOP(vlSelf);
}

VL_ATTR_COLD void Vprobe4___024root___eval_static__TOP(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_static__TOP\n"); );
    // Body
    vlSelf->probe4__DOT__clk = 0U;
    vlSelf->probe4__DOT__ram[0U] = 0U;
    vlSelf->probe4__DOT__ram[1U] = 0U;
}

VL_ATTR_COLD void Vprobe4___024root___eval_final(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_final\n"); );
}

VL_ATTR_COLD void Vprobe4___024root___eval_settle(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_settle\n"); );
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vprobe4___024root___dump_triggers__act(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(vlSelf->__VactTriggered.any())))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 0 is active: @(posedge probe4.clk)\n");
    }
    if ((2ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 1 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

#ifdef VL_DEBUG
VL_ATTR_COLD void Vprobe4___024root___dump_triggers__nba(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___dump_triggers__nba\n"); );
    // Body
    if ((1U & (~ (IData)(vlSelf->__VnbaTriggered.any())))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 0 is active: @(posedge probe4.clk)\n");
    }
    if ((2ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 1 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vprobe4___024root___ctor_var_reset(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___ctor_var_reset\n"); );
    // Body
    vlSelf->probe4__DOT__clk = VL_RAND_RESET_I(1);
    for (int __Vi0 = 0; __Vi0 < 2; ++__Vi0) {
        vlSelf->probe4__DOT__ram[__Vi0] = VL_RAND_RESET_I(32);
    }
    vlSelf->__Vtrigprevexpr___TOP__probe4__DOT__clk__0 = VL_RAND_RESET_I(1);
}
