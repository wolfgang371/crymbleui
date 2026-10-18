/* bdwgc only includes setjmp for fault-probing paths the EMSCRIPTEN config does not take; trap if one does. */
#ifndef WASM_SETJMP_STUB
#define WASM_SETJMP_STUB
typedef long jmp_buf[1];
typedef long sigjmp_buf[1];
#define setjmp(b) 0
#define sigsetjmp(b, s) 0
#define longjmp(b, v) __builtin_trap()
#define siglongjmp(b, v) __builtin_trap()
#endif
