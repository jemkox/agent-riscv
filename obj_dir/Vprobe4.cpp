// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vprobe4__pch.h"

//============================================================
// Constructors

Vprobe4::Vprobe4(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vprobe4__Syms(contextp(), _vcname__, this)}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vprobe4::Vprobe4(const char* _vcname__)
    : Vprobe4(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vprobe4::~Vprobe4() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vprobe4___024root___eval_debug_assertions(Vprobe4___024root* vlSelf);
#endif  // VL_DEBUG
void Vprobe4___024root___eval_static(Vprobe4___024root* vlSelf);
void Vprobe4___024root___eval_initial(Vprobe4___024root* vlSelf);
void Vprobe4___024root___eval_settle(Vprobe4___024root* vlSelf);
void Vprobe4___024root___eval(Vprobe4___024root* vlSelf);

void Vprobe4::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vprobe4::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vprobe4___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vprobe4___024root___eval_static(&(vlSymsp->TOP));
        Vprobe4___024root___eval_initial(&(vlSymsp->TOP));
        Vprobe4___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vprobe4___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vprobe4::eventsPending() { return !vlSymsp->TOP.__VdlySched.empty(); }

uint64_t Vprobe4::nextTimeSlot() { return vlSymsp->TOP.__VdlySched.nextTimeSlot(); }

//============================================================
// Utilities

const char* Vprobe4::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vprobe4___024root___eval_final(Vprobe4___024root* vlSelf);

VL_ATTR_COLD void Vprobe4::final() {
    Vprobe4___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vprobe4::hierName() const { return vlSymsp->name(); }
const char* Vprobe4::modelName() const { return "Vprobe4"; }
unsigned Vprobe4::threads() const { return 1; }
void Vprobe4::prepareClone() const { contextp()->prepareClone(); }
void Vprobe4::atClone() const {
    contextp()->threadPoolpOnClone();
}

//============================================================
// Trace configuration

VL_ATTR_COLD void Vprobe4::trace(VerilatedVcdC* tfp, int levels, int options) {
    vl_fatal(__FILE__, __LINE__, __FILE__,"'Vprobe4::trace()' called on model that was Verilated without --trace option");
}
