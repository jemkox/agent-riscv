// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vmem32.h for the primary calling header

#include "Vmem32__pch.h"
#include "Vmem32___024root.h"

VlCoroutine Vmem32___024root___eval_initial__TOP__Vtiming__0(Vmem32___024root* vlSelf);

void Vmem32___024root___eval_initial(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_initial\n"); );
    // Body
    Vmem32___024root___eval_initial__TOP__Vtiming__0(vlSelf);
    vlSelf->__Vtrigprevexpr___TOP__probe3__DOT__clk__0 
        = vlSelf->probe3__DOT__clk;
}

VL_INLINE_OPT VlCoroutine Vmem32___024root___eval_initial__TOP__Vtiming__0(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_initial__TOP__Vtiming__0\n"); );
    // Body
    vlSelf->probe3__DOT__lwa = 0U;
    vlSelf->probe3__DOT__lwd = 0x42U;
    vlSelf->probe3__DOT__clk = 1U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe3.sv", 
                                       10);
    vlSelf->probe3__DOT__clk = 0U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe3.sv", 
                                       11);
    vlSelf->probe3__DOT__clk = 1U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe3.sv", 
                                       12);
    vlSelf->probe3__DOT__clk = 0U;
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe3.sv", 
                                       13);
    co_await vlSelf->__VdlySched.delay(1ULL, nullptr, 
                                       "tools/probe3.sv", 
                                       14);
    VL_WRITEF("#RAM0=%08x\n",32,vlSelf->probe3__DOT__M__DOT__ram
              [0U]);
}

void Vmem32___024root___eval_act(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_act\n"); );
}

VL_INLINE_OPT void Vmem32___024root___nba_sequent__TOP__0(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___nba_sequent__TOP__0\n"); );
    // Init
    SData/*15:0*/ __Vdlyvdim0__probe3__DOT__M__DOT__ram__v0;
    __Vdlyvdim0__probe3__DOT__M__DOT__ram__v0 = 0;
    IData/*31:0*/ __Vdlyvval__probe3__DOT__M__DOT__ram__v0;
    __Vdlyvval__probe3__DOT__M__DOT__ram__v0 = 0;
    // Body
    __Vdlyvval__probe3__DOT__M__DOT__ram__v0 = vlSelf->probe3__DOT__lwd;
    __Vdlyvdim0__probe3__DOT__M__DOT__ram__v0 = (0xffffU 
                                                 & (vlSelf->probe3__DOT__lwa 
                                                    >> 2U));
    vlSelf->probe3__DOT__M__DOT__ram[__Vdlyvdim0__probe3__DOT__M__DOT__ram__v0] 
        = __Vdlyvval__probe3__DOT__M__DOT__ram__v0;
}

void Vmem32___024root___eval_nba(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_nba\n"); );
    // Body
    if ((1ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vmem32___024root___nba_sequent__TOP__0(vlSelf);
    }
}

void Vmem32___024root___timing_resume(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___timing_resume\n"); );
    // Body
    if ((2ULL & vlSelf->__VactTriggered.word(0U))) {
        vlSelf->__VdlySched.resume();
    }
}

void Vmem32___024root___eval_triggers__act(Vmem32___024root* vlSelf);

bool Vmem32___024root___eval_phase__act(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_phase__act\n"); );
    // Init
    VlTriggerVec<2> __VpreTriggered;
    CData/*0:0*/ __VactExecute;
    // Body
    Vmem32___024root___eval_triggers__act(vlSelf);
    __VactExecute = vlSelf->__VactTriggered.any();
    if (__VactExecute) {
        __VpreTriggered.andNot(vlSelf->__VactTriggered, vlSelf->__VnbaTriggered);
        vlSelf->__VnbaTriggered.thisOr(vlSelf->__VactTriggered);
        Vmem32___024root___timing_resume(vlSelf);
        Vmem32___024root___eval_act(vlSelf);
    }
    return (__VactExecute);
}

bool Vmem32___024root___eval_phase__nba(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_phase__nba\n"); );
    // Init
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = vlSelf->__VnbaTriggered.any();
    if (__VnbaExecute) {
        Vmem32___024root___eval_nba(vlSelf);
        vlSelf->__VnbaTriggered.clear();
    }
    return (__VnbaExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vmem32___024root___dump_triggers__nba(Vmem32___024root* vlSelf);
#endif  // VL_DEBUG
#ifdef VL_DEBUG
VL_ATTR_COLD void Vmem32___024root___dump_triggers__act(Vmem32___024root* vlSelf);
#endif  // VL_DEBUG

void Vmem32___024root___eval(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval\n"); );
    // Init
    IData/*31:0*/ __VnbaIterCount;
    CData/*0:0*/ __VnbaContinue;
    // Body
    __VnbaIterCount = 0U;
    __VnbaContinue = 1U;
    while (__VnbaContinue) {
        if (VL_UNLIKELY((0x64U < __VnbaIterCount))) {
#ifdef VL_DEBUG
            Vmem32___024root___dump_triggers__nba(vlSelf);
#endif
            VL_FATAL_MT("tools/probe3.sv", 1, "", "NBA region did not converge.");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        __VnbaContinue = 0U;
        vlSelf->__VactIterCount = 0U;
        vlSelf->__VactContinue = 1U;
        while (vlSelf->__VactContinue) {
            if (VL_UNLIKELY((0x64U < vlSelf->__VactIterCount))) {
#ifdef VL_DEBUG
                Vmem32___024root___dump_triggers__act(vlSelf);
#endif
                VL_FATAL_MT("tools/probe3.sv", 1, "", "Active region did not converge.");
            }
            vlSelf->__VactIterCount = ((IData)(1U) 
                                       + vlSelf->__VactIterCount);
            vlSelf->__VactContinue = 0U;
            if (Vmem32___024root___eval_phase__act(vlSelf)) {
                vlSelf->__VactContinue = 1U;
            }
        }
        if (Vmem32___024root___eval_phase__nba(vlSelf)) {
            __VnbaContinue = 1U;
        }
    }
}

#ifdef VL_DEBUG
void Vmem32___024root___eval_debug_assertions(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_debug_assertions\n"); );
}
#endif  // VL_DEBUG
