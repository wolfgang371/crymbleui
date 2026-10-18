/* WASI has no dup(); libxml2 uses it only for fd-based output, which Crystal's XML bindings never take (they
 * write through callbacks) - so it fails like a missing feature instead of failing the build. */
#include <errno.h>
static inline int dup(int fd) { (void)fd; errno = ENOTSUP; return -1; }
