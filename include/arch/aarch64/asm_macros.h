#ifndef ARCH_AARCH64_ASM_MACROS_H
#define ARCH_AARCH64_ASM_MACROS_H

/*===========================================================================
 * 纯 cpp 层定义 — C 和汇编 (.S) 都能 include
 * 规则: 只许 #define / .equ / 数字常量, 严禁 C 语法
 *=========================================================================*/

#include <arch/aarch64/mmio.h>      /* UART/GIC 地址 (纯宏) */

/*---- CurrentEL ----*/
#define CURRENT_EL_SHIFT   2
#define CURRENT_EL_MASK    0x3

/*---- SCTLR_EL1 ----*/
#define SCTLR_M     (1 << 0)
#define SCTLR_A     (1 << 1)
#define SCTLR_C     (1 << 2)
#define SCTLR_SA    (1 << 3)
#define SCTLR_I     (1 << 12)

/*---- HCR_EL2 ----*/
#define HCR_RW      (1 << 31)
#define HCR_TGE     (1 << 27)

/*---- SPSR ----*/
#define SPSR_M_EL1h   0x5
#define SPSR_M_EL0t   0x0
#define SPSR_D      (1 << 9)
#define SPSR_A      (1 << 8)
#define SPSR_I      (1 << 7)
#define SPSR_F      (1 << 6)
#define SPSR_DAIF   (SPSR_D | SPSR_A | SPSR_I | SPSR_F)
#define SPSR_EL1h   (SPSR_M_EL1h | SPSR_DAIF)

/*---- ESR_EL1 ----*/
#define ESR_EC_SHIFT   26
#define ESR_EC_MASK    0x3F
#define ESR_IL        (1 << 25)
#define ESR_ISS        0x00FFFFFF

#define EC_UNKNOWN        0x00
#define EC_WFI_WFE        0x01
#define EC_MRC            0x05
#define EC_SVC_32         0x11
#define EC_SVC_64         0x15
#define EC_HVC_64         0x16
#define EC_IABORT_LOWER   0x20
#define EC_IABORT_CUREL   0x21
#define EC_PC_ALIGN       0x22
#define EC_DABORT_LOWER   0x24
#define EC_DABORT_CUREL   0x25
#define EC_SP_ALIGN       0x26
#define EC_FP_TRAP        0x2C
#define EC_SERROR         0x2F
#define EC_BRK            0x3C

/*---- 内核布局 ----*/
#define STACK_TOP      0x00088000

#endif /* ARCH_AARCH64_ASM_MACROS_H */
