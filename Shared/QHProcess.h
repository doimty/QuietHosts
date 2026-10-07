#ifndef QH_PROCESS_H
#define QH_PROCESS_H
#include <stddef.h>
// Fixed-path callers only. Child gets only a minimal environment, standard input,
// bounded stdout, and stderr=/dev/null. Return0 means child reaped, not command success.
// status is exit status (normal exit only); nonzero transport failure is errno-style.
int QHRunProcess(const char *path, const char *command, const void *input, size_t inputLength, char *output,
                 size_t outputCapacity, size_t *outputLength, int *status, unsigned int timeoutSeconds);
#endif
