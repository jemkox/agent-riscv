// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VMEM32__SYMS_H_
#define VERILATED_VMEM32__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vmem32.h"

// INCLUDE MODULE CLASSES
#include "Vmem32___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES)Vmem32__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vmem32* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vmem32___024root               TOP;

    // CONSTRUCTORS
    Vmem32__Syms(VerilatedContext* contextp, const char* namep, Vmem32* modelp);
    ~Vmem32__Syms();

    // METHODS
    const char* name() { return TOP.name(); }
};

#endif  // guard
