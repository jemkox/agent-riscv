// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vmem32.h for the primary calling header

#include "Vmem32__pch.h"
#include "Vmem32__Syms.h"
#include "Vmem32___024root.h"

#ifdef VL_DEBUG
VL_ATTR_COLD void Vmem32___024root___dump_triggers__act(Vmem32___024root* vlSelf);
#endif  // VL_DEBUG

void Vmem32___024root___eval_triggers__act(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_triggers__act\n"); );
    // Body
    vlSelf->__VactTriggered.set(0U, ((IData)(vlSelf->probe3__DOT__clk) 
                                     & (~ (IData)(vlSelf->__Vtrigprevexpr___TOP__probe3__DOT__clk__0))));
    vlSelf->__VactTriggered.set(1U, vlSelf->__VdlySched.awaitingCurrentTime());
    vlSelf->__Vtrigprevexpr___TOP__probe3__DOT__clk__0 
        = vlSelf->probe3__DOT__clk;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vmem32___024root___dump_triggers__act(vlSelf);
    }
#endif
}
