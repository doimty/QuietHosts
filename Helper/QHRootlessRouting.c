#include "QHRootlessRouting.h"
#include "QHDirectoryPolicy.h"
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>

static int Protected(int fd, uid_t owner) {
    struct stat st;
    return fstat(fd, &st) == 0 && QHProtectedDirectoryAllowed(&st, owner, 0);
}
static int PathValid(const char *path) {
    if (!path || !path[0] || path[0] == '/' || strlen(path) >= PATH_MAX) return 0;
    const char *part = path;
    for (const char *p = path;; p++) {
        if (*p != '/' && *p != '\0') continue;
        size_t len = (size_t)(p - part);
        if (!len || (len == 1 && part[0] == '.') ||
            (len == 2 && part[0] == '.' && part[1] == '.')) return 0;
        if (!*p) break;
        part = p + 1;
    }
    return 1;
}
/* Every traversed ancestor is protected and opened O_NOFOLLOW. The descriptor
 * walk is read-only, not an atomic namespace lock. Verify is repeated by the
 * file manager before mutation; existing live-to-live guards remain in place. */
static int OpenPath(int base, const char *path, uid_t owner) {
    if (!PathValid(path) || !Protected(base, owner)) return -1;
    int fd = dup(base);
    if (fd < 0) return -1;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) { close(fd); return -1; }
    char copy[PATH_MAX]; memcpy(copy, path, strlen(path) + 1);
    char *part = copy;
    for (;;) {
        char *end = strchr(part, '/');
        if (end) *end = '\0';
        int child = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        struct stat entry, live;
        int valid = child >= 0 && Protected(child, owner) &&
            fstatat(fd, part, &entry, AT_SYMLINK_NOFOLLOW) == 0 &&
            fstat(child, &live) == 0 && QHDirectoryAnchorMatches(&entry, &live);
        close(fd);
        if (!valid) { if (child >= 0) close(child); return -1; }
        fd = child;
        if (!end) return fd;
        part = end + 1;
    }
}
static int AliasSame(const struct stat *a, const struct stat *b) {
    if (a->st_dev != b->st_dev || a->st_ino != b->st_ino ||
        a->st_uid != b->st_uid || a->st_gid != b->st_gid || a->st_mode != b->st_mode)
        return 0;
    if (S_ISDIR(a->st_mode)) return 1;
    if (!S_ISLNK(a->st_mode) || a->st_size != b->st_size) return 0;
#ifdef __APPLE__
    return a->st_ctimespec.tv_sec == b->st_ctimespec.tv_sec &&
        a->st_ctimespec.tv_nsec == b->st_ctimespec.tv_nsec &&
        a->st_mtimespec.tv_sec == b->st_mtimespec.tv_sec &&
        a->st_mtimespec.tv_nsec == b->st_mtimespec.tv_nsec;
#else
    return a->st_ctim.tv_sec == b->st_ctim.tv_sec && a->st_ctim.tv_nsec == b->st_ctim.tv_nsec &&
        a->st_mtim.tv_sec == b->st_mtim.tv_sec && a->st_mtim.tv_nsec == b->st_mtim.tv_nsec;
#endif
}
static const char *Observe(int base, const char *rootPath, const char *rawPath,
    const char *parentPath, const char *name, uid_t owner,
    QHRootlessLayoutSnapshot *layout, struct stat *alias) {
    const char *error = "rootless-unsafe-namespace";
    int root = OpenPath(base, rootPath, owner);
    int raw = OpenPath(base, rawPath, owner);
    int parent = OpenPath(base, parentPath, owner);
    if (root < 0 || raw < 0 || parent < 0) goto cleanup;
    error = QHRootlessInspectLayout(root, raw, owner, layout);
    if (error) goto cleanup;
    error = "rootless-dependency-root-conflict";
    struct stat before, after;
    if (fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW) != 0 || before.st_uid != owner)
        goto cleanup;
    if (S_ISLNK(before.st_mode)) {
        char target[PATH_MAX], wanted[PATH_MAX];
        ssize_t n = readlinkat(parent, name, target, sizeof(target) - 1);
        int size = snprintf(wanted, sizeof(wanted), "/%s", rootPath);
        if (n <= 0 || n >= (ssize_t)sizeof(target) - 1 || size <= 0 || size >= (int)sizeof(wanted))
            goto cleanup;
        target[n] = '\0';
        if (n > 1 && target[n - 1] == '/') target[n - 1] = '\0';
        if (strcmp(target, wanted) != 0) goto cleanup;
    } else if (!QHDirectoryAnchorMatches(&before, &layout->root)) {
        goto cleanup;
    }
    if (fstatat(parent, name, &after, AT_SYMLINK_NOFOLLOW) != 0 || !AliasSame(&before, &after))
        goto cleanup;
    *alias = after;
    error = NULL;
cleanup:
    if (parent >= 0) close(parent);
    if (raw >= 0) close(raw);
    if (root >= 0) close(root);
    return error;
}
const char *QHRootlessRoutingOpen(int base, const char *rootPath, const char *rawPath,
    const char *parentPath, const char *name, uid_t owner, QHRootlessRouting *out) {
    if (!out || !PathValid(rootPath) || !PathValid(rawPath) || !PathValid(parentPath) ||
        !name || !PathValid(name) || strchr(name, '/') || strlen(name) >= sizeof(out->aliasName))
        return "rootless-invalid-preflight";
    QHRootlessRouting value; memset(&value, 0, sizeof(value)); value.baseFD = -1;
    const char *error = Observe(base, rootPath, rawPath, parentPath, name, owner,
                               &value.layout, &value.alias);
    if (error) return error;
    value.baseFD = dup(base);
    if (value.baseFD < 0) return "rootless-unsafe-namespace";
    if (fcntl(value.baseFD, F_SETFD, FD_CLOEXEC) < 0) {
        close(value.baseFD); return "rootless-unsafe-namespace";
    }
    value.owner = owner;
    memcpy(value.rootPath, rootPath, strlen(rootPath) + 1);
    memcpy(value.systemPath, rawPath, strlen(rawPath) + 1);
    memcpy(value.aliasParent, parentPath, strlen(parentPath) + 1);
    memcpy(value.aliasName, name, strlen(name) + 1);
    *out = value;
    return NULL;
}
const char *QHRootlessRoutingVerify(const QHRootlessRouting *routing) {
    if (!routing || routing->baseFD < 0) return "rootless-invalid-preflight";
    QHRootlessLayoutSnapshot now; struct stat alias;
    const char *error = Observe(routing->baseFD, routing->rootPath, routing->systemPath,
        routing->aliasParent, routing->aliasName, routing->owner, &now, &alias);
    if (error) return error;
    if (!AliasSame(&routing->alias, &alias)) return "rootless-dependency-root-conflict";
    if (!QHDirectoryAnchorMatches(&routing->layout.root, &now.root) ||
        !QHDirectoryAnchorMatches(&routing->layout.system, &now.system) ||
        !QHDirectoryAnchorMatches(&routing->layout.etc, &now.etc) ||
        !QHDirectoryAnchorMatches(&routing->layout.var, &now.var) ||
        !QHDirectoryAnchorMatches(&routing->layout.lib, &now.lib)) return "rootless-namespace-changed";
    return NULL;
}
void QHRootlessRoutingClose(QHRootlessRouting *routing) {
    if (!routing) return;
    if (routing->baseFD >= 0) close(routing->baseFD);
    memset(routing, 0, sizeof(*routing)); routing->baseFD = -1;
}
