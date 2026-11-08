# t43: MPRV data access at M with MPP=U + MXR set: the MXR x-only-page rescue must
# apply to S-effective privilege loads ONLY (spec). vpn3 PA0x3000 leaf X|A|U|V
# (xwr=100, u=1): at eff=S (MPRV+MPP=S+SUM+MXR) the load succeeds (rescued); store
# there -> PF15 mtval 0x3000. Flip to MPP=U (MPRV+MXR stay): the SAME page load MUST
# fault PF13 mtval 0x3000 (no U rescue - t5 stays 0). vpn4 PA0x4000 leaf R|W|A|D|U|V
# loads/stores fine at eff=U. Handler counts exactly 2 (sees cause 15 then 13, mtval
# 0x3000 both); recovery verifies the RW page at U; gp=1.
/* MMU_CODE_VPN: 0 for tests/link.ld; 0x20 for the spike build (see t30). */
#ifndef MMU_CODE_VPN
#define MMU_CODE_VPN 0
#endif
#ifndef L1_ENTRY
#define L1_ENTRY 0x2401
#endif
#ifndef CODE_FLAGS
#define CODE_FLAGS 0xB
#endif
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw mtvec, t1
  # seed sentinels at M physical (identity, satp still 0)
  li t0, 0x3000
  li t1, 0x1111
  sw t1, 0(t0)
  li t0, 0x4000
  li t1, 0x2222
  sw t1, 0(t0)
  # L1 page table at PA0x9000
  li t0, 0x9000
  li t1, L1_ENTRY
  sw t1, 0(t0)
  li t1, (MMU_CODE_VPN<<10)|CODE_FLAGS
  sw t1, (MMU_CODE_VPN&0xFF)*4(t0)
  li t1, ((MMU_CODE_VPN+1)<<10)|CODE_FLAGS
  sw t1, ((MMU_CODE_VPN+1)&0xFF)*4(t0)
  li t1, 0xC59        # vpn3 3 -> PA0x3000 | X|A|U|V (xwr=100, u=1)
  sw t1, 12(t0)
  li t1, 0x10AF       # vpn4 4 -> PA0x4000 | R|W|A|D|U|V
  sw t1, 16(t0)
  li t0, 0x80000009   # satp: sv32, root PPN 0x9 (PA0x9000)
  csrw satp, t0
  li t0, 0x1800       # clear MPP (-> M in bits)
  csrc mstatus, t0
  li t0, 0xE0800      # MPRV(17)|SUM(18)|MXR(19) + MPP=S
  csrs mstatus, t0
  li t2, 0x3000
  lw t3, 0(t2)        # eff=S: X page load RESCUED by MXR at S priv
  li t4, 0x1111
  bne t3, t4, fail
  sw t3, 0(t2)        # store into x-only page -> PF15 (handler #1 skips)
  nop
  # flip MPP to U (00): just clear; MPRV/SUM/MXR bits stay
  li t0, 0x1800
  csrc mstatus, t0
  li t2, 0x3000       # reload VA: the handler used t2 as mepc scratch (clobbers it)
  li t5, 0            # probe register: fault leaves t5=0
  lw t5, 0(t2)        # eff=U: SAME x-only page load with MXR set MUST FAULT (no U rescue)
  nop
  bnez t5, fail       # if MXR wrongly rescued at U, t5=0x1111 -> fail
  # RW page at eff=U must work normally (r=1,w=1,u=1)
  li t0, 0x4000
  lw t3, 0(t0)
  li t4, 0x2222
  bne t3, t4, fail
  li t1, 0x3333
  sw t1, 0(t0)        # store at eff=U ok
  lw t3, 0(t0)
  bne t3, t1, fail
  li t2, 2
  bne s0, t2, fail
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  csrr t2, mcause
  csrr t3, mtval
  li t4, 0x3000       # BOTH faults: mtval must be the faulting VA 0x3000
  bne t3, t4, fail
  li t4, 15
  beq t2, t4, ok
  li t4, 13
  beq t2, t4, ok
  j fail
ok:
  addi s0, s0, 1
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
