#ifndef QH_DIRECTORY_POLICY_H
#define QH_DIRECTORY_POLICY_H

#include <sys/stat.h>
#include <stddef.h>
#include <string.h>

/* Only the helper-computed, trusted jbroot container has the mobile exception.
 * Its protected children must still belong to expectedOwner (production: 0).
 * Never use this predicate for etc, private, var, lib, state or mirror traversal. */
static inline int QHContainerRootAllowed(const struct stat *s, uid_t expectedOwner) {
    return S_ISDIR(s->st_mode) && !(s->st_mode & 07022) &&
           (s->st_uid == expectedOwner || (expectedOwner == 0 && s->st_uid == 501));
}

/* Only the independently derived and paired-data-root-validated var entry.
 * This is a routing directory, not the protected var/lib/state children. */
static inline int QHPairedVarAllowed(const struct stat *s, uid_t expectedOwner) {
    return S_ISDIR(s->st_mode) && !(s->st_mode & 07022) &&
           (s->st_uid == expectedOwner || (expectedOwner == 0 && s->st_uid == 501));
}

static inline int QHProtectedDirectoryAllowed(const struct stat *s, uid_t expectedOwner,
                                              int privateDirectory) {
    return S_ISDIR(s->st_mode) && s->st_uid == expectedOwner && !(s->st_mode & 07022) &&
           (!privateDirectory || (s->st_mode & 0777) == 0700);
}

/* Directory timestamps/size/nlink change during our own state creation. Pin the
 * identity and security metadata, not those expected content-change counters. */
static inline int QHDirectoryAnchorMatches(const struct stat *a, const struct stat *b) {
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino && a->st_mode == b->st_mode &&
           a->st_uid == b->st_uid && a->st_gid == b->st_gid;
}

/* A symlink normally reports 0777: directory write-bit policy does NOT apply.
 * Callers must also pin the full lstat snapshot (including mode and times) and
 * re-read its text. This does not authorize following the supplied link text. */
static inline int QHVarLinkAllowed(const struct stat *s, uid_t expectedOwner, const char *text,
                                   size_t length) {
    return S_ISLNK(s->st_mode) && s->st_uid == expectedOwner && s->st_nlink == 1 &&
           ((length == 11 && memcmp(text, "private/var", 11) == 0) ||
            (length == 12 && memcmp(text, "private/var/", 12) == 0));
}

/* The second split-root link is accepted only against trusted, precomputed
 * paths. A single trailing slash is the only textual variation. */
static inline int QHPairedRootLinkAllowed(const struct stat *s, uid_t expectedOwner, const char *text,
                                          size_t length, const char *nativePath, size_t nativeLength,
                                          const char *canonicalPath, size_t canonicalLength) {
    if (!S_ISLNK(s->st_mode) || s->st_uid != expectedOwner || s->st_nlink != 1 || length == 0) {
        return 0;
    }
    size_t coreLength = length;
    if (text[coreLength - 1] == '/') {
        coreLength--;
    }
    return (coreLength == nativeLength && memcmp(text, nativePath, coreLength) == 0) ||
           (coreLength == canonicalLength && memcmp(text, canonicalPath, coreLength) == 0);
}

#endif
