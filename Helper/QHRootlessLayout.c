#include "QHRootlessLayout.h"
#include "QHDirectoryPolicy.h"
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

int QHRootlessRootAllowed(const struct stat *entry, uid_t owner) {
    return entry && QHProtectedDirectoryAllowed(entry, owner, 0);
}
static int SameIdentity(const struct stat *a, const struct stat *b) {
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino;
}
static int ReadProtected(int fd, uid_t owner, struct stat *out) {
    return fstat(fd, out) == 0 && QHProtectedDirectoryAllowed(out, owner, 0);
}
static int OpenChild(int parent, const char *name, uid_t owner, struct stat *anchor) {
    struct stat before, after;
    if (fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW) ||
        !QHProtectedDirectoryAllowed(&before, owner, 0)) return -1;
    int child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (child < 0) return -1;
    if (!ReadProtected(child, owner, anchor) ||
        !QHDirectoryAnchorMatches(&before, anchor) ||
        fstatat(parent, name, &after, AT_SYMLINK_NOFOLLOW) ||
        !QHDirectoryAnchorMatches(&before, &after)) {
        close(child);
        return -1;
    }
    return child;
}
static int ChildStillMatches(int parent, const char *name, int child, uid_t owner,
                             const struct stat *anchor) {
    struct stat pathname, descriptor;
    return !fstatat(parent, name, &pathname, AT_SYMLINK_NOFOLLOW) &&
           ReadProtected(child, owner, &descriptor) &&
           QHDirectoryAnchorMatches(&pathname, anchor) &&
           QHDirectoryAnchorMatches(&descriptor, anchor);
}
const char *QHRootlessInspectLayout(int rootFD, int systemDirFD, uid_t owner,
                                  QHRootlessLayoutSnapshot *snapshot) {
    if (!snapshot) return "rootless-invalid-preflight";
    QHRootlessLayoutSnapshot found;
    int etcFD = -1, varFD = -1, libFD = -1;
    const char *failure = "rootless-unsafe-root";
    if (fstat(rootFD, &found.root) || !QHRootlessRootAllowed(&found.root, owner)) goto done;
    failure = "rootless-unsafe-system-directory";
    if (!ReadProtected(systemDirFD, owner, &found.system)) goto done;
    failure = "root-alias";
    if (SameIdentity(&found.root, &found.system)) goto done;
    failure = "rootless-unsupported-etc-layout";
    etcFD = OpenChild(rootFD, "etc", owner, &found.etc);
    if (etcFD < 0) goto done;
    failure = "root-alias";
    if (SameIdentity(&found.etc, &found.system)) goto done;
    /* Unknown var symlinks are deliberately refused, not realpath-followed.
     * Support for another official topology requires its own anchored proof. */
    failure = "rootless-unsupported-var-layout";
    varFD = OpenChild(rootFD, "var", owner, &found.var);
    if (varFD < 0) goto done;
    failure = "rootless-unsafe-state-parent";
    libFD = OpenChild(varFD, "lib", owner, &found.lib);
    if (libFD < 0) goto done;
    struct stat secondary;
    errno = 0;
    int secondaryResult = fstatat(etcFD, "hosts.lmb", &secondary, AT_SYMLINK_NOFOLLOW);
    failure = "secondary-conflict";
    if (secondaryResult == 0 || errno != ENOENT) goto done;
    /* Recheck after traversal. This is evidence about this observation only;
     * QHFileManager must still guard every actual transaction write. */
    struct stat liveRoot, liveSystem;
    failure = "directory-raced";
    if (fstat(rootFD, &liveRoot) || fstat(systemDirFD, &liveSystem) ||
        !QHDirectoryAnchorMatches(&liveRoot, &found.root) ||
        !QHDirectoryAnchorMatches(&liveSystem, &found.system) ||
        !ChildStillMatches(rootFD, "etc", etcFD, owner, &found.etc) ||
        !ChildStillMatches(rootFD, "var", varFD, owner, &found.var) ||
        !ChildStillMatches(varFD, "lib", libFD, owner, &found.lib)) goto done;
    *snapshot = found;
    failure = 0;
done:
    if (libFD >= 0) close(libFD);
    if (varFD >= 0) close(varFD);
    if (etcFD >= 0) close(etcFD);
    return failure;
}
