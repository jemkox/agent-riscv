// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VPROBE2__SYMS_H_
#define VERILATED_VPROBE2__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vprobe2.h"

// INCLUDE MODULE CLASSES
#include "Vprobe2___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES)Vprobe2__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vprobe2* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vprobe2___024root              TOP;

    // CONSTRUCTORS
    Vprobe2__Syms(VerilatedContext* contextp, const char* namep, Vprobe2* modelp);
    ~Vprobe2__Syms();

    // METHODS
    const char* name() { return TOP.name(); }
};

#endif  // guard
