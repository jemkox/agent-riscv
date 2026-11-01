// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vprobe2.h for the primary calling header

#include "Vprobe2__pch.h"
#include "Vprobe2___024root.h"

VL_ATTR_COLD void Vprobe2___024root___eval_static__TOP(Vprobe2___024root* vlSelf);

VL_ATTR_COLD void Vprobe2___024root___eval_static(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_static\n"); );
    // Body
    Vprobe2___024root___eval_static__TOP(vlSelf);
}

VL_ATTR_COLD void Vprobe2___024root___eval_static__TOP(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_static__TOP\n"); );
    // Body
    vlSelf->probe2__DOT__clk = 0U;
    vlSelf->probe2__DOT__a = 0U;
}

VL_ATTR_COLD void Vprobe2___024root___eval_final(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_final\n"); );
}

VL_ATTR_COLD void Vprobe2___024root___eval_settle(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_settle\n"); );
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vprobe2___024root___dump_triggers__act(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(vlSelf->__VactTriggered.any())))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 0 is active: @(posedge probe2.clk)\n");
    }
    if ((2ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 1 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

#ifdef VL_DEBUG
VL_ATTR_COLD void Vprobe2___024root___dump_triggers__nba(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___dump_triggers__nba\n"); );
    // Body
    if ((1U & (~ (IData)(vlSelf->__VnbaTriggered.any())))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 0 is active: @(posedge probe2.clk)\n");
    }
    if ((2ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 1 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vprobe2___024root___ctor_var_reset(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___ctor_var_reset\n"); );
    // Body
    vlSelf->probe2__DOT__clk = VL_RAND_RESET_I(1);
    vlSelf->probe2__DOT__a = VL_RAND_RESET_I(32);
    vlSelf->__Vtrigprevexpr___TOP__probe2__DOT__clk__0 = VL_RAND_RESET_I(1);
}
