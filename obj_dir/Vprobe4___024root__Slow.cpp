// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vprobe4.h for the primary calling header

#include "Vprobe4__pch.h"
#include "Vprobe4__Syms.h"
#include "Vprobe4___024root.h"

void Vprobe4___024root___ctor_var_reset(Vprobe4___024root* vlSelf);

Vprobe4___024root::Vprobe4___024root(Vprobe4__Syms* symsp, const char* v__name)
    : VerilatedModule{v__name}
    , __VdlySched{*symsp->_vm_contextp__}
    , vlSymsp{symsp}
 {
    // Reset structure values
    Vprobe4___024root___ctor_var_reset(this);
}

void Vprobe4___024root::__Vconfigure(bool first) {
    if (false && first) {}  // Prevent unused
}

Vprobe4___024root::~Vprobe4___024root() {
}
