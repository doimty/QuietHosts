#ifndef QH_ROOTLESS_LAYOUT_H
#define QH_ROOTLESS_LAYOUT_H

#include <sys/stat.h>
#include <sys/types.h>

/* Read-only preflight, NOT a transaction lock or a root/path resolver.
 * Production integration must supply libroot-derived, securely opened fds;
 * command requests must never supply these fds, prefixes or raw paths. */
typedef struct {
    struct stat root, etc, var, lib, system;
} QHRootlessLayoutSnapshot;

/* No RootHide mobile-owned routing exception in the rootless profile. */
int QHRootlessRootAllowed(const struct stat *entry, uid_t owner);
/* NULL = accepted strict flat layout. Error string = explicit refusal.
 * snapshot is written only on success. No mkdir, file write, link follow,
 * helper invocation, DNS restart or external process occurs here. */
const char *QHRootlessInspectLayout(int rootFD, int systemDirFD, uid_t owner,
                                  QHRootlessLayoutSnapshot *snapshot);

#endif
