// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vmem32.h for the primary calling header

#include "Vmem32__pch.h"
#include "Vmem32__Syms.h"
#include "Vmem32___024root.h"

#ifdef VL_DEBUG
VL_ATTR_COLD void Vmem32___024root___dump_triggers__stl(Vmem32___024root* vlSelf);
#endif  // VL_DEBUG

VL_ATTR_COLD void Vmem32___024root___eval_triggers__stl(Vmem32___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vmem32__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vmem32___024root___eval_triggers__stl\n"); );
    // Body
    vlSelf->__VstlTriggered.set(0U, (IData)(vlSelf->__VstlFirstIteration));
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vmem32___024root___dump_triggers__stl(vlSelf);
    }
#endif
}
