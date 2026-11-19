#ifndef CATALYST_KERNEL_UART_H
#define CATALYST_KERNEL_UART_H
//#include "arch/aarch64/mmio.h"

#define UART0_BASE   0x09000000UL
#define UART_FR      (*(volatile unsigned int  *)(UART0_BASE + 0x18))
#define UART_DR      (*(volatile unsigned char *)(UART0_BASE + 0x00))
#define FR_TXFF      (1u << 5)

void uart_putc(char c);
void uart_puts(const char *s);
void uart_hex64(unsigned long val);


#endif // CATALYST_KERNEL_UART_H
