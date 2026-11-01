#include <verilated.h>
#include <memory>
#include "Vrun_doom.h"

int main(int argc, char** argv, char** envp) {
    Verilated::commandArgs(argc, argv);
    std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    std::unique_ptr<Vrun_doom> model{new Vrun_doom(contextp.get())};
    model->eval();
    model->final();
    return 0;
}
