// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vprobe4.h for the primary calling header

#include "Vprobe4__pch.h"
#include "Vprobe4__Syms.h"
#include "Vprobe4___024root.h"

#ifdef VL_DEBUG
VL_ATTR_COLD void Vprobe4___024root___dump_triggers__act(Vprobe4___024root* vlSelf);
#endif  // VL_DEBUG

void Vprobe4___024root___eval_triggers__act(Vprobe4___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vprobe4__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vprobe4___024root___eval_triggers__act\n"); );
    // Body
    vlSelf->__VactTriggered.set(0U, ((IData)(vlSelf->probe4__DOT__clk) 
                                     & (~ (IData)(vlSelf->__Vtrigprevexpr___TOP__probe4__DOT__clk__0))));
    vlSelf->__VactTriggered.set(1U, vlSelf->__VdlySched.awaitingCurrentTime());
    vlSelf->__Vtrigprevexpr___TOP__probe4__DOT__clk__0 
        = vlSelf->probe4__DOT__clk;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vprobe4___024root___dump_triggers__act(vlSelf);
    }
#endif
}
