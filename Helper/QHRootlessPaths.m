#import "QHRootlessPaths.h"
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <unistd.h>
#ifdef QH_TESTING
static NSString *QHTestNamespace;
void QHRootlessTestingSetNamespace(NSString *base) {
    QHTestNamespace = [base copy];
}
#endif

static NSString *CanonicalDirectory(NSString *path) {
    if (![path isAbsolutePath] || path.length >= PATH_MAX) return nil;
    char result[PATH_MAX];
    if (!realpath(path.fileSystemRepresentation, result)) return nil;
    return [NSString stringWithUTF8String:result];
}

NSString *QHRootlessResolvePaths(NSString *dynamicRoot, NSString **root,
                               NSString **systemHosts) {
    if (!root || !systemHosts) return @"rootless-invalid-path";
    NSString *canonical = CanonicalDirectory(dynamicRoot);
    NSString *rawDirectory = CanonicalDirectory(@"/etc");
    if (!canonical || [canonical isEqual:@"/"] || !rawDirectory)
        return @"rootless-invalid-path";
    // realpath alone is not trust. OpenRuntime then opens every canonical
    // directory component with O_NOFOLLOW and checks protected ownership.
    NSString *hosts = [rawDirectory stringByAppendingPathComponent:@"hosts"];
    QHRootlessRouting proof;
    const char *error = QHRootlessRoutingOpenRuntime(canonical, hosts, 0, &proof);
    if (error) return [NSString stringWithUTF8String:error];
    QHRootlessRoutingClose(&proof);
    *root = canonical;
    *systemHosts = hosts;
    return nil;
}

const char *QHRootlessRoutingOpenRuntime(NSString *root, NSString *systemHosts,
                                       uid_t owner, QHRootlessRouting *out) {
    NSString *rawDirectory = [systemHosts stringByDeletingLastPathComponent];
#ifdef QH_TESTING
    if (QHTestNamespace) {
        NSString *basePath = CanonicalDirectory(QHTestNamespace);
        NSString *prefix = [basePath stringByAppendingString:@"/"];
        if (!basePath || ![root hasPrefix:prefix] || ![rawDirectory hasPrefix:prefix] ||
            ![root isEqual:CanonicalDirectory(root)] ||
            ![rawDirectory isEqual:CanonicalDirectory(rawDirectory)] ||
            ![systemHosts.lastPathComponent isEqual:@"hosts"])
            return "rootless-invalid-path";
        int base = open(basePath.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (base < 0) return "unsafe-directory";
        const char *error = QHRootlessRoutingOpen(base,
            [root substringFromIndex:prefix.length].fileSystemRepresentation,
            [rawDirectory substringFromIndex:prefix.length].fileSystemRepresentation,
            "alias", "jb", owner, out);
        close(base);
        return error;
    }
#endif
    if (owner != 0) return "rootless-invalid-owner";
    NSString *aliasDirectory = CanonicalDirectory(@"/var");
    if (![root isEqual:CanonicalDirectory(root)] ||
        ![rawDirectory isEqual:CanonicalDirectory(rawDirectory)] ||
        ![systemHosts.lastPathComponent isEqual:@"hosts"] ||
        root.length < 2 || rawDirectory.length < 2 || !aliasDirectory)
        return "rootless-invalid-path";
    int base = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (base < 0) return "unsafe-directory";
    const char *error = QHRootlessRoutingOpen(base,
        [root substringFromIndex:1].fileSystemRepresentation,
        [rawDirectory substringFromIndex:1].fileSystemRepresentation,
        [aliasDirectory substringFromIndex:1].fileSystemRepresentation,
        "jb", owner, out);
    close(base);
    return error;
}
