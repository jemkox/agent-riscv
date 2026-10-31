#!/bin/sh
# Resumes the RISC-V CPU agent session with the upgraded setup (FPGA tools, Verilator full sim, picolibc).
exec "$HOME/.local/bin/agent-window" --session ses_e6c7d9eaaffeAw6fDbX28mLtHl --prompt "SETUP UPGRADED, I restarted you. Read hdl/rv32cpu/PROMPT.md now: it REPLACES the previous task prompt (new tools: Verilator full simulation, nextpnr-ice40/icepack FPGA flow, picolibc; new FPGA milestone M8). Keep the files you already wrote in hdl/rv32cpu, check them, create PROGRESS.md, and continue M1 from where you were. Do not stop until FINAL ACCEPTANCE in PROMPT.md is met."
