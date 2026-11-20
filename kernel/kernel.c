#include <kernel/uart.h>
#include <arch/aarch64/sysregs.h>
#include <kernel/kernel.h>
void kernel_main(void)
{
    uart_puts("CatalystOS: stage 1 alive\r\n");
    uart_puts("CurrentEL = ");
    uart_hex64(get_current_el());
    uart_puts("\r\n");

    for (;;)
        ;
}
