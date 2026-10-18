/* bdwgc's EMSCRIPTEN config asks for the stack base; under wasm-ld it is the linker symbol __stack_high. */
extern char __stack_high;
static inline void *emscripten_stack_get_base(void) { return &__stack_high; }
