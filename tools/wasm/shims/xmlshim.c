/* Crystal's libxml2 bindings call the thread-safe accessors; this single-threaded build exposes plain
 * globals. No libxml2 headers here: they #define these names as calls to the accessors, which made the
 * first version of this shim call itself forever. */
extern void *xmlGenericError, *xmlGenericErrorContext, *xmlStructuredError, *xmlStructuredErrorContext;
void **__xmlGenericError(void) { return &xmlGenericError; }
void **__xmlGenericErrorContext(void) { return &xmlGenericErrorContext; }
void **__xmlStructuredError(void) { return &xmlStructuredError; }
void **__xmlStructuredErrorContext(void) { return &xmlStructuredErrorContext; }
