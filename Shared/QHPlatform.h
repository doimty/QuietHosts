#ifndef QH_PLATFORM_H
#define QH_PLATFORM_H

/* Scheme selection is compile-time, never selected by an IPC request. */
#if defined(QH_ROOTLESS) && QH_ROOTLESS
#import <rootless.h>
/* libroot's C macro uses a static buffer. Use its NSString conversion with
 * a stack-local buffer so concurrent App bridge requests do not race it. */
#define QH_PLATFORM_PATH(path) [ROOT_PATH_NS_VAR([NSString stringWithUTF8String:(path)]) fileSystemRepresentation]
#else
#import <roothide.h>
#define QH_PLATFORM_PATH(path) jbroot(path)
#endif

#endif
