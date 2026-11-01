// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vprobe4.h for the primary calling header

#include "Vprobe4__pch.h"
#include "Vprobe4___024root.h"

VlCoroutine Vprobe4___024root___eval_initial__TOP__Vtiming__0(Vprobe4___024root* vlSelf);

void Vprobe4___024root___eval_initial(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_initial\n"); );
    // Body
    Vprobe4___024root___eval_initial__TOP__Vtiming__0(vlSelf);
    vlSelf->__Vtrigprevexpr___TOP__probe4__DOT__clk__0 
        = vlSelf->probe4__DOT__clk;
}

VL_INLINE_OPT VlCoroutine Vprobe4___024root___eval_initial__TOP__Vtiming__0(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_initial__TOP__Vtiming__0\n"); );
    // Body
    vlSelf->probe4__DOT__clk = 1U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe4.sv", 
                                       5);
    vlSelf->probe4__DOT__clk = 0U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe4.sv", 
                                       6);
    vlSelf->probe4__DOT__clk = 1U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe4.sv", 
                                       7);
    vlSelf->probe4__DOT__clk = 0U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe4.sv", 
                                       8);
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe4.sv", 
                                       9);
    VL_WRITEF("#RAM0=%08x\n",32,vlSelf->probe4__DOT__ram
              [0U]);
}

void Vprobe4___024root___eval_act(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_act\n"); );
}

VL_INLINE_OPT void Vprobe4___024root___nba_sequent__TOP__0(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___nba_sequent__TOP__0\n"); );
    // Body
    vlSelf->probe4__DOT__ram[0U] = 0x42U;
}

void Vprobe4___024root___eval_nba(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_nba\n"); );
    // Body
    if ((1ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vprobe4___024root___nba_sequent__TOP__0(vlSelf);
    }
}

void Vprobe4___024root___timing_resume(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___timing_resume\n"); );
    // Body
    if ((2ULL & vlSelf->__VactTriggered.word(0U))) {
        vlSelf->__VdlySched.resume();
    }
}

void Vprobe4___024root___eval_triggers__act(Vprobe4___024root* vlSelf);

bool Vprobe4___024root___eval_phase__act(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_phase__act\n"); );
    // Init
    VlTriggerVec<2> __VpreTriggered;
    CData/*0:0*/ __VactExecute;
    // Body
    Vprobe4___024root___eval_triggers__act(vlSelf);
    __VactExecute = vlSelf->__VactTriggered.any();
    if (__VactExecute) {
        __VpreTriggered.andNot(vlSelf->__VactTriggered, vlSelf->__VnbaTriggered);
        vlSelf->__VnbaTriggered.thisOr(vlSelf->__VactTriggered);
        Vprobe4___024root___timing_resume(vlSelf);
        Vprobe4___024root___eval_act(vlSelf);
    }
    return (__VactExecute);
}

bool Vprobe4___024root___eval_phase__nba(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_phase__nba\n"); );
    // Init
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = vlSelf->__VnbaTriggered.any();
    if (__VnbaExecute) {
        Vprobe4___024root___eval_nba(vlSelf);
        vlSelf->__VnbaTriggered.clear();
    }
    return (__VnbaExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vprobe4___024root___dump_triggers__nba(Vprobe4___024root* vlSelf);
#endif  // VL_DEBUG
#ifdef VL_DEBUG
VL_ATTR_COLD void Vprobe4___024root___dump_triggers__act(Vprobe4___024root* vlSelf);
#endif  // VL_DEBUG

void Vprobe4___024root___eval(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval\n"); );
    // Init
    IData/*31:0*/ __VnbaIterCount;
    CData/*0:0*/ __VnbaContinue;
    // Body
    __VnbaIterCount = 0U;
    __VnbaContinue = 1U;
    while (__VnbaContinue) {
        if (VL_UNLIKELY((0x64U < __VnbaIterCount))) {
#ifdef VL_DEBUG
            Vprobe4___024root___dump_triggers__nba(vlSelf);
#endif
            VL_FATAL_MT("tools/probe4.sv", 1, "", "NBA region did not converge.");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        __VnbaContinue = 0U;
        vlSelf->__VactIterCount = 0U;
        vlSelf->__VactContinue = 1U;
        while (vlSelf->__VactContinue) {
            if (VL_UNLIKELY((0x64U < vlSelf->__VactIterCount))) {
#ifdef VL_DEBUG
                Vprobe4___024root___dump_triggers__act(vlSelf);
#endif
                VL_FATAL_MT("tools/probe4.sv", 1, "", "Active region did not converge.");
            }
            vlSelf->__VactIterCount = ((IData)(1U) 
                                       + vlSelf->__VactIterCount);
            vlSelf->__VactContinue = 0U;
            if (Vprobe4___024root___eval_phase__act(vlSelf)) {
                vlSelf->__VactContinue = 1U;
            }
        }
        if (Vprobe4___024root___eval_phase__nba(vlSelf)) {
            __VnbaContinue = 1U;
        }
    }
}

#ifdef VL_DEBUG
void Vprobe4___024root___eval_debug_assertions(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_debug_assertions\n"); );
}
#endif  // VL_DEBUG
