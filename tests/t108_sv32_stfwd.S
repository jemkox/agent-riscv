/* t108_sv32_stfwd: store-DATA forwarding across an S-mode D-TLB walk.
   Linux-boot symptom: `addi sp,sp,-48` (result feeds the store's rs1) immediately
   followed by `sw ra,44(sp)` onto a *cold* page stored the sp result instead of
   ra. The D-TLB miss makes the store redo after the page walk; the redo path
   must keep EX/MEM forwarding for both rs1 (addr) and rs2 (data).
   Same table layout as t30: L1@PA0x8000, L0@PA0x9000, code identity VPN 0/1,
   data page VA 0x8000 -> PA 0xA000 (R|W, A|D preset). */
#ifndef MMU_CODE_VPN
#define MMU_CODE_VPN 0
#endif
#ifndef CODE_FLAGS
#define CODE_FLAGS 0xB
#endif
#ifndef L1_ENTRY
#define L1_ENTRY 0x2401
#endif
  .globl _start
  .option norvc
_start:
  li gp, 0
  li s0, 0
  la t1, handler
  csrw mtvec, t1
  li t0, 0x1800
  csrw mstatus, t0
  li t0, 0x8000
  li t1, L1_ENTRY
  sw t1, 0(t0)
  li t0, 0x9000
  li t1, (MMU_CODE_VPN<<10)|CODE_FLAGS
  sw t1, (MMU_CODE_VPN&0xFF)*4(t0)
  li t1, ((MMU_CODE_VPN+1)<<10)|CODE_FLAGS
  sw t1, ((MMU_CODE_VPN+1)&0xFF)*4(t0)
  li t1, 0x28C7        # VA0x8000 -> PA0xA000 R|W|A|D|V
  sw t1, 32(t0)
  li t1, 0x2CC7        # VA0xB000 -> PA0xB000 (identity) R|W|A|D|V
  sw t1, 44(t0)
  li t0, 0x80000008
  csrw satp, t0
  la t2, ssw
  csrw mepc, t2
  li t0, 0x1800
  csrc mstatus, t0
  li t0, 0x800
  csrs mstatus, t0
  mret
ssw:
  /* variant 1: boot-exact. addi sp feeds rs1; store data comes from an
     older reg. First touch of the data page is the STORE itself. */
  li x1, 0xC0FFEE11
  li x2, 0x8100
  addi x2, x2, -48
  sw x1, 44(x2)            # cold page -> D-TLB walk redo
  lw x3, 44(x2)
  li x4, 0xC0FFEE11
  bne x3, x4, fail
  /* variant 2: rs2 produced by the immediately preceding addi, store cold */
  li x2, 0x8200
  addi x1, x0, 0x77       # producer of rs2 right before the store
  sw x1, 44(x2)           # new line within the (now warm) page
  lw x3, 44(x2)
  li x4, 0x77
  bne x3, x4, fail
  /* variant 3: rs1 addi + rs2 addi both right before the store */
  li x2, 0x8300
  addi x2, x2, -48
  addi x1, x0, 0x123
  sw x1, 44(x2)
  lw x3, 44(x2)
  li x4, 0x123
  bne x3, x4, fail
  /* variant 4: store on a page whose *only* prior access was an itlb/walk
     of the second data page; the data page for this store was walked via
     a load first (warm), rs1 produced by addi in EX/MEM */
  li x8, 0xB000
  lw x9, 0(x8)             # walk page B (value undefined-ish, A|D preset)
  li x2, 0xB100
  addi x2, x2, -48
  li x1, 0x33221100
  sw x1, 44(x2)
  lw x3, 44(x2)
  bne x3, x1, fail
  j pass
fail2:
  li gp, 5
  j done
pass:
  li gp, 1
  j done
fail:
  li gp, 3
done:
  li t4, 1
  csrrw x0, 0x3ff, t4
handler:
  csrr t2, mcause
  li t3, 11
  bne t2, t3, fail
  addi s0, s0, 1
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
