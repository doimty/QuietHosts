#ifndef QH_PLATFORM_H
#define QH_PLATFORM_H

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

/* Scheme selection is compile-time, never selected by an IPC request. */
#if defined(QH_ROOTLESS) && QH_ROOTLESS
#import <rootless.h>
/* libroot's C macro uses a static buffer. Use its NSString conversion with
 * a stack-local buffer so concurrent App bridge requests do not race it. */
#define QH_PLATFORM_PATH(path) [ROOT_PATH_NS_VAR([NSString stringWithUTF8String:(path)]) fileSystemRepresentation]
#else
#define QH_PLATFORM_PATH(path) jbroot(path)
#if defined(QH_TESTING) && QH_TESTING
/* The host Foundation fixture supplies a deterministic test double. */
NSString *QHPlatformRootFSPathForTesting(NSString *path);
static inline NSString *QHPlatformRootFSPath(NSString *path) {
    if (![path isAbsolutePath]) return nil;
    return QHPlatformRootFSPathForTesting(path);
}
#else
#import <roothide.h>
/* rootfs(const char *) returns a library-managed C string. Copy it immediately
 * so a later libroot call cannot change the candidate while checks are live. */
static inline NSString *QHPlatformRootFSPath(NSString *path) {
    if (![path isAbsolutePath]) return nil;
    const char *mapped = rootfs(path.fileSystemRepresentation);
    if (!mapped || mapped[0] != '/') return nil;
    return [[NSString alloc] initWithUTF8String:mapped];
}
#endif
#endif

#endif
