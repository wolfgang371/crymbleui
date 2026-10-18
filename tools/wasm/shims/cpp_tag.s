# The WebAssembly exception tag llvm.wasm.throw uses (tag 0, the C++ ABI's): normally defined by libc++abi,
# which a Crystal program does not link.
.globl __cpp_exception
.tagtype __cpp_exception i32
__cpp_exception:
