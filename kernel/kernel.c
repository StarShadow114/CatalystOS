#include <kernel/uart.h>
#include <kernel/trap.h>
#include <arch/aarch64/sysregs.h>
#include <kernel/kernel.h>
void kernel_main(void)
{
    uart_puts("CatalystOS: stage 2b alive\r\n");

    uart_puts("CurrentEL = ");  uart_hex64(get_current_el());  uart_puts("\r\n");
    uart_puts("VBAR_EL1  = ");  uart_hex64(read_sysreg(VBAR_EL1)); uart_puts("\r\n");
    uart_puts("SCTLR_EL1 = ");  uart_hex64(read_sysreg(SCTLR_EL1));
    uart_puts("  (bit0=M/MMU bit1=A/Align bit2=C/Cache)\r\n");

    /* ★ 故意触发 Data Abort: 碰一个没映射的地址 */
    uart_puts("\r\n[*] touching 0xdeadbeef ...\r\n");
    volatile unsigned long *bad = (volatile unsigned long *)0xdeadbeefUL;
    *bad = 0x1234;

    /* 走到这里 = VBAR 没生效, 异常没被接住, 这是 bug */
    uart_puts("!!! 不该看到这行: 异常未被捕获 !!!\r\n");
    for (;;) wfi();
}
