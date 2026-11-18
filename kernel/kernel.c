#define UART0_BASE   0x09000000UL
#define UART_FR      (*(volatile unsigned int *)(UART0_BASE + 0x18))
#define UART_DR      (*(volatile unsigned char *)(UART0_BASE + 0x00))

#define FR_TXFF      (1u << 5)

static void uart_putc(char c)
{
    while (UART_FR & FR_TXFF)
        ;
    UART_DR = (unsigned char)c;
}

static void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

/* 
*把 val 以 16 位十六进制、带 0x 前缀的形式打到串口
*例: uart_hex64(0x1F2E3D4C5B6A7988)  ->  "0x1f2e3d4c5b6a7988"
*例: uart_hex64(0)                  ->  "0x0000000000000000"
*要求: 小写, 定宽 16 位, 前导零必须打, 结尾不换行
*/
void uart_hex64(unsigned long val)
{
  static const char hexdigits[] = "0123456789abcdef";
  uart_putc("0");
  uart_putc("x");
  for (int shift =??? ; shift >=??? ;shift ???){
    unsigned int nibble = (unsigned int)((val >> shift) & ???);
    uart_putc(hexdigits[???]);
  }
}

static inline unsigned long get_current_el(void){
  unsigned long el;
  __asm__ volatile ("mrs" : "=r"(el));
  return (el >> 2) & 3;
}
void kernel_main(void)
{
  uart_puts("CatalystOS: stage 1 alive\r\n");
  uart_putc(get_current_el());

  for (;;);
}
