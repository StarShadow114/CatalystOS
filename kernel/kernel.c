#include <kernel/uart.h>
#include <utils/el_utils.h>
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
