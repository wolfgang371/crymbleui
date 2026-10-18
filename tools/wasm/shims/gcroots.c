/* Static data (Crystal class vars, constants) lies between the linker symbols __global_base and __heap_base;
 * bdwgc's EMSCRIPTEN config registers no static roots of its own. */
extern char __global_base, __heap_base;
void GC_add_roots(void *low, void *high_plus_1);
void wasm_gc_add_data_roots(void) { GC_add_roots(&__global_base, &__heap_base); }

/* wasi-libc's sbrk aborts unless the increment is a whole 64 KiB wasm page; bdwgc asks for HBLK multiples.
 * Round up: the result stays page-aligned (wasi-libc's break is always the memory end), the rest is slack. */
#include <unistd.h>
void *gc_wasm_sbrk(intptr_t n) {
  if (n <= 0) return sbrk(n);
  return sbrk((n + 65535) & ~(intptr_t)65535);
}
