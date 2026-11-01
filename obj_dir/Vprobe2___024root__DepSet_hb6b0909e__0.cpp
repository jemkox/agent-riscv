// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vprobe2.h for the primary calling header

#include "Vprobe2__pch.h"
#include "Vprobe2__Syms.h"
#include "Vprobe2___024root.h"

#ifdef VL_DEBUG
VL_ATTR_COLD void Vprobe2___024root___dump_triggers__act(Vprobe2___024root* vlSelf);
#endif  // VL_DEBUG

void Vprobe2___024root___eval_triggers__act(Vprobe2___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe2__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe2___024root___eval_triggers__act\n"); );
    // Body
    vlSelf->__VactTriggered.set(0U, ((IData)(vlSelf->probe2__DOT__clk) 
                                     & (~ (IData)(vlSelf->__Vtrigprevexpr___TOP__probe2__DOT__clk__0))));
    vlSelf->__VactTriggered.set(1U, vlSelf->__VdlySched.awaitingCurrentTime());
    vlSelf->__Vtrigprevexpr___TOP__probe2__DOT__clk__0 
        = vlSelf->probe2__DOT__clk;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vprobe2___024root___dump_triggers__act(vlSelf);
    }
#endif
}
