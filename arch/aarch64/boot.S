//CatalystOS启动汇编
.section .text.boot
.global _start

_start:
  ldr x0 , =0x8000
  mov sp , x0
  bl kernel_main

halt:
  wfi
  b halt
