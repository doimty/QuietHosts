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

/* QH_ROOTHIDE_ROOTFS_ALIAS_BEGIN
 * Keep the legacy C predicate above byte-for-byte compatible. The Objective-C
 * RootHide caller gets only candidates derived from rootfs(the already brand-
 * checked fixed path), with realpath(primary root) as an additional alias.
 * No link text is canonicalized by this matcher. Callers must additionally
 * verify the resolved directory against their held root/paired-var anchor. */
#include <fcntl.h>
#include <unistd.h>

/* Follow only a previously metadata/text-validated routing link, read-only.
 * This allows different official spellings but never a different object.
 * Caller pins the symlink lstat/text before and after this check. */
static inline int QHPairedLinkTargetMatches(int parentFD, const char *name,
                                            const struct stat *expected) {
    if (!expected || !S_ISDIR(expected->st_mode)) return 0;
    int fd = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return 0;
    struct stat actual;
    int matches = fstat(fd, &actual) == 0 && QHDirectoryAnchorMatches(&actual, expected);
    close(fd);
    return matches;
}
static inline int QHPairedRootPathMatchesCandidate(const char *text, size_t textLength,
                                                   const char *candidate, size_t candidateLength) {
    if (!text || !candidate || candidateLength == 0) return 0;
    if (textLength == candidateLength && memcmp(text, candidate, textLength) == 0) return 1;
    /* Preserve the old single-trailing-slash tolerance, but not // (including
     * the special case where the trusted candidate itself is "/"). */
    return textLength > 1 && text[textLength - 1] == '/' && text[textLength - 2] != '/' &&
           textLength - 1 == candidateLength && memcmp(text, candidate, candidateLength) == 0;
}

static inline int QHPairedRootLinkAllowedWithAliases(
    const struct stat *s, uid_t expectedOwner, const char *text, size_t textLength,
    const char *nativePath, size_t nativeLength, const char *canonicalPath, size_t canonicalLength,
    const char *rootFSDataAlias, size_t rootFSDataAliasLength,
    const char *resolvedPrimaryRoot, size_t resolvedPrimaryRootLength) {
    if (!S_ISLNK(s->st_mode) || s->st_uid != expectedOwner || s->st_nlink != 1 ||
        !text || textLength == 0) return 0;
    return QHPairedRootPathMatchesCandidate(text, textLength, nativePath, nativeLength) ||
           QHPairedRootPathMatchesCandidate(text, textLength, canonicalPath, canonicalLength) ||
           QHPairedRootPathMatchesCandidate(text, textLength, rootFSDataAlias,
                                            rootFSDataAliasLength) ||
           QHPairedRootPathMatchesCandidate(text, textLength, resolvedPrimaryRoot,
                                            resolvedPrimaryRootLength);
}

static inline int QHPathIsNormalizedAbsolute(const char *path, size_t length) {
    if (!path || length == 0 || path[0] != '/') return 0;
    if (length == 1) return 1;
    if (path[length - 1] == '/') return 0;
    size_t start = 1;
    for (size_t i = 1; i <= length; i++) {
        if (i != length && path[i] != '/') continue;
        size_t componentLength = i - start;
        if (componentLength == 0 ||
            (componentLength == 1 && path[start] == '.') ||
            (componentLength == 2 && path[start] == '.' && path[start + 1] == '.')) return 0;
        start = i + 1;
    }
    return 1;
}

static inline int QHBrandComponentValid(const char *brand, size_t length) {
    if (!brand || length != 24 || memcmp(brand, ".jbroot-", 8) != 0) return 0;
    for (size_t i = 8; i < length; i++) {
        char c = brand[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F'))) return 0;
    }
    return 1;
}

static inline int QHBrandedPairDataPath(const char *path, size_t length,
                                        const char **brand, size_t *brandLength) {
    if (!path || length < 29 || memcmp(path + length - 4, "/var", 4) != 0) return 0;
    size_t end = length - 4;
    size_t start = end;
    while (start > 0 && path[start - 1] != '/') start--;
    if (start == 0 || !QHBrandComponentValid(path + start, end - start)) return 0;
    if (brand) *brand = path + start;
    if (brandLength) *brandLength = end - start;
    return 1;
}

static inline int QHBrandedPrimaryRootPath(const char *path, size_t length) {
    if (!path || length < 25 || path[length - 1] == '/') return 0;
    size_t start = length;
    while (start > 0 && path[start - 1] != '/') start--;
    return start > 0 && QHBrandComponentValid(path + start, length - start);
}

static inline int QHBrandedRootFSDataAliasAllowed(const char *alias, size_t aliasLength,
                                                  const char *nativePath, size_t nativeLength) {
    const char *brand = NULL;
    size_t brandLength = 0;
    if (!QHPathIsNormalizedAbsolute(alias, aliasLength) ||
        !QHBrandedPairDataPath(nativePath, nativeLength, &brand, &brandLength)) return 0;
    size_t suffixLength = brandLength + 5; /* "/" + brand + "/var" */
    if (aliasLength < suffixLength) return 0;
    size_t start = aliasLength - suffixLength;
    return alias[start] == '/' && memcmp(alias + start + 1, brand, brandLength) == 0 &&
           memcmp(alias + start + 1 + brandLength, "/var", 4) == 0;
}

#if defined(__OBJC__) && !(defined(QH_ROOTLESS) && QH_ROOTLESS)
#import "../Shared/QHPlatform.h"
#include <limits.h>
#include <stdlib.h>

static inline int QHPairedRootLinkAllowedWithPlatformAliases(
    const struct stat *s, uid_t expectedOwner, const char *text, size_t textLength,
    const char *nativePath, size_t nativeLength, const char *canonicalPath, size_t canonicalLength) {
    if (QHPairedRootLinkAllowed(s, expectedOwner, text, textLength,
                                nativePath, nativeLength, canonicalPath, canonicalLength)) return 1;
    if (!S_ISLNK(s->st_mode) || s->st_uid != expectedOwner || s->st_nlink != 1 ||
        !text || textLength == 0 || !nativePath) return 0;

    if (QHBrandedPairDataPath(nativePath, nativeLength, NULL, NULL)) {
        NSString *native = [[NSString alloc] initWithBytes:nativePath length:nativeLength
                                                  encoding:NSUTF8StringEncoding];
        NSString *alias = native ? QHPlatformRootFSPath(native) : nil;
        const char *aliasBytes = alias.fileSystemRepresentation;
        size_t aliasLength = aliasBytes ? strlen(aliasBytes) : 0;
        if (!aliasBytes || !QHBrandedRootFSDataAliasAllowed(aliasBytes, aliasLength,
                                                            nativePath, nativeLength)) return 0;
        return QHPairedRootLinkAllowedWithAliases(s, expectedOwner, text, textLength,
                                                  nativePath, nativeLength,
                                                  canonicalPath, canonicalLength,
                                                  aliasBytes, aliasLength, NULL, 0);
    }

    if (QHBrandedPrimaryRootPath(nativePath, nativeLength)) {
        NSString *native = [[NSString alloc] initWithBytes:nativePath length:nativeLength
                                                  encoding:NSUTF8StringEncoding];
        NSString *alias = native ? QHPlatformRootFSPath(native) : nil;
        const char *aliasBytes = alias.fileSystemRepresentation;
        size_t aliasLength = aliasBytes ? strlen(aliasBytes) : 0;
        if (aliasBytes && !QHPathIsNormalizedAbsolute(aliasBytes, aliasLength)) return 0;
        char resolved[PATH_MAX];
        BOOL hasResolved = realpath(nativePath, resolved) != NULL;
        return QHPairedRootLinkAllowedWithAliases(s, expectedOwner, text, textLength,
                                                  nativePath, nativeLength,
                                                  canonicalPath, canonicalLength,
                                                  aliasBytes, aliasLength,
                                                  hasResolved ? resolved : NULL,
                                                  hasResolved ? strlen(resolved) : 0);
    }
    return 0;
}
/* Existing QHFileManager call sites remain source-compatible. In RootHide
 * Objective-C builds this dispatches to the exact platform-derived candidates;
 * C policy tests and QH_ROOTLESS builds retain the legacy predicate. */
#define QHPairedRootLinkAllowed(...) QHPairedRootLinkAllowedWithPlatformAliases(__VA_ARGS__)
#endif
/* QH_ROOTHIDE_ROOTFS_ALIAS_END */

#endif
