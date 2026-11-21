#ifndef CATALYST_KERNEL_UART_H
#define CATALYST_KERNEL_UART_H

/*
 * PL011 UART 驱动接口 (QEMU virt: 0x09000000)
 * ⚠ 本文件含 C 函数声明, 不许被 .S include → 那边用 <arch/aarch64/mmio.h>
 */
#include <arch/aarch64/mmio.h>

void uart_init(void);
void uart_putc(char c);
void uart_puts(const char *s);
void uart_hex64(unsigned long v);

#endif /* CATALYST_KERNEL_UART_H */
