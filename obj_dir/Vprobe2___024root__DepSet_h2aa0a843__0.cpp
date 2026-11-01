// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vprobe2.h for the primary calling header

#include "Vprobe2__pch.h"
#include "Vprobe2___024root.h"

VlCoroutine Vprobe2___024root___eval_initial__TOP__Vtiming__0(Vprobe2___024root* vlSelf);

void Vprobe2___024root___eval_initial(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_initial\n"); );
    // Body
    Vprobe2___024root___eval_initial__TOP__Vtiming__0(vlSelf);
    vlSelf->__Vtrigprevexpr___TOP__probe2__DOT__clk__0 
        = vlSelf->probe2__DOT__clk;
}

VL_INLINE_OPT VlCoroutine Vprobe2___024root___eval_initial__TOP__Vtiming__0(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_initial__TOP__Vtiming__0\n"); );
    // Body
    vlSelf->probe2__DOT__clk = 1U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe2.sv", 
                                       8);
    vlSelf->probe2__DOT__clk = 0U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe2.sv", 
                                       9);
    vlSelf->probe2__DOT__clk = 1U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe2.sv", 
                                       8);
    vlSelf->probe2__DOT__clk = 0U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe2.sv", 
                                       9);
    vlSelf->probe2__DOT__clk = 1U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe2.sv", 
                                       8);
    vlSelf->probe2__DOT__clk = 0U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe2.sv", 
                                       9);
    VL_WRITEF("#A=%08x\n",32,vlSelf->probe2__DOT__a);
}

void Vprobe2___024root___eval_act(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_act\n"); );
}

VL_INLINE_OPT void Vprobe2___024root___nba_sequent__TOP__0(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___nba_sequent__TOP__0\n"); );
    // Body
    vlSelf->probe2__DOT__a = 0x42U;
}

void Vprobe2___024root___eval_nba(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_nba\n"); );
    // Body
    if ((1ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vprobe2___024root___nba_sequent__TOP__0(vlSelf);
    }
}

void Vprobe2___024root___timing_resume(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___timing_resume\n"); );
    // Body
    if ((2ULL & vlSelf->__VactTriggered.word(0U))) {
        vlSelf->__VdlySched.resume();
    }
}

void Vprobe2___024root___eval_triggers__act(Vprobe2___024root* vlSelf);

bool Vprobe2___024root___eval_phase__act(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_phase__act\n"); );
    // Init
    VlTriggerVec<2> __VpreTriggered;
    CData/*0:0*/ __VactExecute;
    // Body
    Vprobe2___024root___eval_triggers__act(vlSelf);
    __VactExecute = vlSelf->__VactTriggered.any();
    if (__VactExecute) {
        __VpreTriggered.andNot(vlSelf->__VactTriggered, vlSelf->__VnbaTriggered);
        vlSelf->__VnbaTriggered.thisOr(vlSelf->__VactTriggered);
        Vprobe2___024root___timing_resume(vlSelf);
        Vprobe2___024root___eval_act(vlSelf);
    }
    return (__VactExecute);
}

bool Vprobe2___024root___eval_phase__nba(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_phase__nba\n"); );
    // Init
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = vlSelf->__VnbaTriggered.any();
    if (__VnbaExecute) {
        Vprobe2___024root___eval_nba(vlSelf);
        vlSelf->__VnbaTriggered.clear();
    }
    return (__VnbaExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vprobe2___024root___dump_triggers__nba(Vprobe2___024root* vlSelf);
#endif  // VL_DEBUG
#ifdef VL_DEBUG
VL_ATTR_COLD void Vprobe2___024root___dump_triggers__act(Vprobe2___024root* vlSelf);
#endif  // VL_DEBUG

void Vprobe2___024root___eval(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval\n"); );
    // Init
    IData/*31:0*/ __VnbaIterCount;
    CData/*0:0*/ __VnbaContinue;
    // Body
    __VnbaIterCount = 0U;
    __VnbaContinue = 1U;
    while (__VnbaContinue) {
        if (VL_UNLIKELY((0x64U < __VnbaIterCount))) {
#ifdef VL_DEBUG
            Vprobe2___024root___dump_triggers__nba(vlSelf);
#endif
            VL_FATAL_MT("tools/probe2.sv", 1, "", "NBA region did not converge.");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        __VnbaContinue = 0U;
        vlSelf->__VactIterCount = 0U;
        vlSelf->__VactContinue = 1U;
        while (vlSelf->__VactContinue) {
            if (VL_UNLIKELY((0x64U < vlSelf->__VactIterCount))) {
#ifdef VL_DEBUG
                Vprobe2___024root___dump_triggers__act(vlSelf);
#endif
                VL_FATAL_MT("tools/probe2.sv", 1, "", "Active region did not converge.");
            }
            vlSelf->__VactIterCount = ((IData)(1U) 
                                       + vlSelf->__VactIterCount);
            vlSelf->__VactContinue = 0U;
            if (Vprobe2___024root___eval_phase__act(vlSelf)) {
                vlSelf->__VactContinue = 1U;
            }
        }
        if (Vprobe2___024root___eval_phase__nba(vlSelf)) {
            __VnbaContinue = 1U;
        }
    }
}

#ifdef VL_DEBUG
void Vprobe2___024root___eval_debug_assertions(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_debug_assertions\n"); );
}
#endif  // VL_DEBUG
