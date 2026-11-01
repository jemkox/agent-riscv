// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vmem32.h for the primary calling header

#include "Vmem32__pch.h"
#include "Vmem32__Syms.h"
#include "Vmem32___024root.h"

void Vmem32___024root___ctor_var_reset(Vmem32___024root* vlSelf);

Vmem32___024root::Vmem32___024root(Vmem32__Syms* symsp, const char* v__name)
    : VerilatedModule{v__name}
    , __VdlySched{*symsp->_vm_contextp__}
    , vlSymsp{symsp}
 {
    // Reset structure values
    Vmem32___024root___ctor_var_reset(this);
}

void Vmem32___024root::__Vconfigure(bool first) {
    if (false && first) {}  // Prevent unused
}

Vmem32___024root::~Vmem32___024root() {
}
