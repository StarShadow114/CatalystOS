#include <aech/aarch64/sysregs.h>
//boot.S
.sectiom .text.boot, "ax"
.global _start
.equ STACK_TOP, 0x88000
_start:
  //关中断
  msr DAIFSet, #0xF

  //探测当前el

  mrs x0, CurrentEL
  mov x1, #0xc
  and x0, x0, x1
  cmp x0, #0xc
  b.eq drop_from_el3
  b el1_common

drop_from_el3:
  mov x0, #(1 << 10)
  orr x0, x0, #(1 << 0)
  msr SRC_EL3, x0

  mov x0, #0x3c9
  msr SPSR_EL3
  adr x0, drop_form_el2
  msr ELR_EL3, x0
  isb
  eret


el1_common:
  mrs x0, CurrentEL
  and x0, x0, #0xC
  cmp x0, #0x4
  b.eq 1f
  mov x0, #0xdead0001
  b panic_hang

1:
  idr x0, =STACK_TOP
  mov sp, x0

  bl kernel_main

halt:
  wfi
  b halt

panic_hang:
  wfi
  b panic_hang

