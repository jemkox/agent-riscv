// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vmem32__pch.h"

//============================================================
// Constructors

Vmem32::Vmem32(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vmem32__Syms(contextp(), _vcname__, this)}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vmem32::Vmem32(const char* _vcname__)
    : Vmem32(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vmem32::~Vmem32() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vmem32___024root___eval_debug_assertions(Vmem32___024root* vlSelf);
#endif  // VL_DEBUG
void Vmem32___024root___eval_static(Vmem32___024root* vlSelf);
void Vmem32___024root___eval_initial(Vmem32___024root* vlSelf);
void Vmem32___024root___eval_settle(Vmem32___024root* vlSelf);
void Vmem32___024root___eval(Vmem32___024root* vlSelf);

void Vmem32::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vmem32::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vmem32___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vmem32___024root___eval_static(&(vlSymsp->TOP));
        Vmem32___024root___eval_initial(&(vlSymsp->TOP));
        Vmem32___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vmem32___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vmem32::eventsPending() { return !vlSymsp->TOP.__VdlySched.empty(); }

uint64_t Vmem32::nextTimeSlot() { return vlSymsp->TOP.__VdlySched.nextTimeSlot(); }

//============================================================
// Utilities

const char* Vmem32::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vmem32___024root___eval_final(Vmem32___024root* vlSelf);

VL_ATTR_COLD void Vmem32::final() {
    Vmem32___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vmem32::hierName() const { return vlSymsp->name(); }
const char* Vmem32::modelName() const { return "Vmem32"; }
unsigned Vmem32::threads() const { return 1; }
void Vmem32::prepareClone() const { contextp()->prepareClone(); }
void Vmem32::atClone() const {
    contextp()->threadPoolpOnClone();
}

//============================================================
// Trace configuration

VL_ATTR_COLD void Vmem32::trace(VerilatedVcdC* tfp, int levels, int options) {
    vl_fatal(__FILE__, __LINE__, __FILE__,"'Vmem32::trace()' called on model that was Verilated without --trace option");
}
