// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VPROBE4__SYMS_H_
#define VERILATED_VPROBE4__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vprobe4.h"

// INCLUDE MODULE CLASSES
#include "Vprobe4___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES)Vprobe4__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vprobe4* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vprobe4___024root              TOP;

    // CONSTRUCTORS
    Vprobe4__Syms(VerilatedContext* contextp, const char* namep, Vprobe4* modelp);
    ~Vprobe4__Syms();

    // METHODS
    const char* name() { return TOP.name(); }
};

#endif  // guard
