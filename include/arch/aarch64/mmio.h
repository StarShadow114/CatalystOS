#ifndef ARCH_AARCH64_MMIO_H
#define ARCH_AARCH64_MMIO_H

/*===========================================================================
 * 内存映射设备地址 — 纯 #define, C 和 .S 都能 include
 * ⚠ 本文件严禁出现: void/static/struct/return/inline/函数声明
 *   (汇编器过完 cpp 就不认这些, 会报 unexpected token)
 *=========================================================================*/

/*---- QEMU virt 机器内存映射 ----*/
#define UART0_BASE      0x09000000
#define UART0_DR        (UART0_BASE + 0x00)   /* Data Register  (读/写) */
#define UART0_FR        (UART0_BASE + 0x18)   /* Flag Register  (只读) */

#define FR_TXFF         (1U << 5)     /* Transmit FIFO full  — 为1就别写 */
#define FR_RXFE         (1U << 4)     /* Receive  FIFO empty — 为1就没数据 */
#define FR_BUSY         (1U << 3)     /* UART 正在发送 */

/*---- GIC (2B 先备着, 3B 接中断时用) ----*/
#define GICD_BASE       0x08000000
#define GICC_BASE       0x08010000

#endif /* ARCH_AARCH64_MMIO_H */
