/* A C function returning a struct by value: what the patch's wasm32 ABI fix (StructRet) is about. */
typedef struct { int a; double b; int c; } triple;
triple make_triple(int a, double b, int c) { triple t = { a * 2, b * 2.0, c * 2 }; return t; }
