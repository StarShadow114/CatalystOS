#ifndef CATALYST_UTILS_EL_UTILS_H
#define CATALYST_UTILS_EL_UTILS_H
inline unsigned long get_current_el(void){
  unsigned long el;
  __asm__ volatile ("mrs %0, CurrentEL" : "=r"(el));
  return (el >> 2) & 3;
}
#endif // CATALYST_UTILS_EL_UTILS_H
