// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vprobe2.h for the primary calling header

#include "Vprobe2__pch.h"
#include "Vprobe2__Syms.h"
#include "Vprobe2___024root.h"

void Vprobe2___024root___ctor_var_reset(Vprobe2___024root* vlSelf);

Vprobe2___024root::Vprobe2___024root(Vprobe2__Syms* symsp, const char* v__name)
    : VerilatedModule{v__name}
    , __VdlySched{*symsp->_vm_contextp__}
    , vlSymsp{symsp}
 {
    // Reset structure values
    Vprobe2___024root___ctor_var_reset(this);
}

void Vprobe2___024root::__Vconfigure(bool first) {
    if (false && first) {}  // Prevent unused
}

Vprobe2___024root::~Vprobe2___024root() {
}
