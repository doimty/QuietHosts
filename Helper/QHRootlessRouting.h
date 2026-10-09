#ifndef QH_ROOTLESS_ROUTING_H
#define QH_ROOTLESS_ROUTING_H
#include "QHRootlessLayout.h"
#include <limits.h>

/* Paths are relative to a trusted base fd ("/" in production). They are never
 * command arguments. No links are followed; only the final dependency alias
 * may be a root-owned symlink spelling the absolute physical root exactly. */
typedef struct {
    int baseFD;
    uid_t owner;
    char rootPath[PATH_MAX], systemPath[PATH_MAX], aliasParent[PATH_MAX], aliasName[64];
    QHRootlessLayoutSnapshot layout;
    struct stat alias;
} QHRootlessRouting;
const char *QHRootlessRoutingOpen(int baseFD, const char *rootPath,
    const char *systemPath, const char *aliasParent, const char *aliasName,
    uid_t owner, QHRootlessRouting *out);
const char *QHRootlessRoutingVerify(const QHRootlessRouting *routing);
void QHRootlessRoutingClose(QHRootlessRouting *routing);
#endif
