#include "kernel/uart.h"

void uart_putc(char c){
  while (UART_FR & FR_TXFF) 
    ;
  (UART_DR) = (unsigned char)c;
}

void uart_puts(const char *s){
  while (*s)
    uart_putc(*s++);
}

void uart_hex64(unsigned long val)
{
    static const char hexdigits[] = "0123456789abcdef";

    uart_putc('0');
    uart_putc('x');

    for (int shift = 60; shift >= 0; shift -= 4) {
        unsigned int nibble = (unsigned int)((val >> shift) & 0xF);
        uart_putc(hexdigits[nibble]);
    }
}


