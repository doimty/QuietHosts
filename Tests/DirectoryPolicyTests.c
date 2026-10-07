#include "../Helper/QHDirectoryPolicy.h"
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#ifdef QH_BASELINE_POLICY
#include "baseline_policy.h"
#define QHContainerRootAllowed QHBaselineRootAllowed
#endif

static unsigned failures;
#define CHECK(condition, name)                                                                               \
    do {                                                                                                     \
        if (!(condition)) {                                                                                  \
            fprintf(stderr, "FAIL: %s\n", name);                                                             \
            failures++;                                                                                      \
        }                                                                                                    \
    } while (0)

int main(void) {
    struct stat s = {0};
    s.st_mode = S_IFDIR | 0755;
    s.st_uid = 0;
    CHECK(QHContainerRootAllowed(&s, 0), "root uid0 allowed");
    s.st_uid = 501;
    CHECK(QHContainerRootAllowed(&s, 0), "container root uid501 allowed");
    CHECK(QHPairedVarAllowed(&s, 0), "validated paired var uid501 allowed");
    CHECK(!QHPairedVarAllowed(&s, 502), "paired var exception only for production owner0");
    CHECK(!QHProtectedDirectoryAllowed(&s, 0, 0), "protected uid501 forbidden");
    CHECK(!QHProtectedDirectoryAllowed(&s, 0, 1), "state uid501 forbidden");
    CHECK(!QHContainerRootAllowed(&s, 502), "mobile exception only for expectedOwner0");
    s.st_uid = 502;
    CHECK(!QHContainerRootAllowed(&s, 0), "other root owner forbidden");
    CHECK(QHContainerRootAllowed(&s, 502), "fixture expectedOwner remains supported");
    CHECK(QHProtectedDirectoryAllowed(&s, 502, 0), "protected fixture owner supported");
    s.st_uid = 0;
    mode_t badModes[] = {02755, 04755, 01755, 01777, 0775, 0757, 0777};
    for (size_t i = 0; i < sizeof(badModes) / sizeof(badModes[0]); i++) {
        s.st_mode = S_IFDIR | badModes[i];
        CHECK(!QHContainerRootAllowed(&s, 0), "root unsafe mode rejected");
        CHECK(!QHProtectedDirectoryAllowed(&s, 0, 0), "protected unsafe mode rejected");
    }
    mode_t badTypes[] = {S_IFREG, S_IFLNK, S_IFIFO, S_IFCHR, S_IFBLK, S_IFSOCK};
    for (size_t i = 0; i < sizeof(badTypes) / sizeof(badTypes[0]); i++) {
        s.st_mode = badTypes[i] | 0755;
        CHECK(!QHContainerRootAllowed(&s, 0), "root nondirectory rejected");
        CHECK(!QHProtectedDirectoryAllowed(&s, 0, 0), "protected nondirectory rejected");
    }
    s.st_mode = S_IFDIR | 0755;
    CHECK(!QHProtectedDirectoryAllowed(&s, 0, 1), "state requires0700");
    s.st_mode = S_IFDIR | 0700;
    CHECK(QHProtectedDirectoryAllowed(&s, 0, 1), "state0700 accepted");
    struct stat original = s;
    CHECK(QHDirectoryAnchorMatches(&s, &original), "identical anchor accepted");
#define CHANGED(field, value)                                                                                \
    do {                                                                                                     \
        s = original;                                                                                        \
        s.field = (value);                                                                                   \
        CHECK(!QHDirectoryAnchorMatches(&s, &original), "anchor " #field " pinned");                         \
    } while (0)
    CHANGED(st_dev, 1);
    CHANGED(st_ino, 1);
    CHANGED(st_uid, 501);
    CHANGED(st_gid, 501);
    CHANGED(st_mode, S_IFDIR | 0755);
    s = original;
    s.st_size = 1024;
    s.st_nlink = 3;
    s.st_mtime = 42;
    CHECK(QHDirectoryAnchorMatches(&s, &original), "own directory content changes permitted");

    s = original;
    s.st_mode = S_IFLNK | 0777;
    s.st_nlink = 1;
    CHECK(QHVarLinkAllowed(&s, 0, "private/var", 11), "normal0777 link accepted");
    CHECK(QHVarLinkAllowed(&s, 0, "private/var/", 12), "observed trailing slash accepted");
    s.st_mode = S_IFLNK | 0755;
    CHECK(QHVarLinkAllowed(&s, 0, "private/var/", 12), "link0755 accepted");
    const char *badLinks[] = {"/private/var",  "../private/var", "private/../var", "private//var",
                              "private/var//", "./private/var",  "private/var/.",  "private/var\n",
                              "private/var\r", "private/var\t",  "other",          ""};
    for (size_t i = 0; i < sizeof(badLinks) / sizeof(badLinks[0]); i++) {
        CHECK(!QHVarLinkAllowed(&s, 0, badLinks[i], strlen(badLinks[i])), "nonexact link rejected");
    }
    CHECK(!QHVarLinkAllowed(&s, 0, "private/var\0x", 13), "embedded NUL not truncated");
    s.st_uid = 501;
    CHECK(!QHVarLinkAllowed(&s, 0, "private/var", 11), "link mobile owner rejected");
    s.st_uid = 0;
    s.st_nlink = 2;
    CHECK(!QHVarLinkAllowed(&s, 0, "private/var", 11), "multilink rejected");
    s.st_nlink = 1;
    s.st_mode = S_IFDIR | 0755;
    CHECK(!QHVarLinkAllowed(&s, 0, "private/var", 11), "nonlink rejected");

    s.st_mode = S_IFLNK | 0777;
    s.st_uid = 0;
    s.st_nlink = 1;
    const char *nativePair = "/var/mobile/Containers/Shared/AppGroup/.jbroot-0123456789ABCDEF/var";
    const char *canonicalPair = "/private/var/mobile/Containers/Shared/AppGroup/.jbroot-0123456789ABCDEF/var";
    const char *canonicalPairSlash =
        "/private/var/mobile/Containers/Shared/AppGroup/.jbroot-0123456789ABCDEF/var/";
    CHECK(QHPairedRootLinkAllowed(&s, 0, nativePair, strlen(nativePair), nativePair, strlen(nativePair),
                                  canonicalPair, strlen(canonicalPair)),
          "native pair target accepted");
    CHECK(QHPairedRootLinkAllowed(&s, 0, canonicalPair, strlen(canonicalPair), nativePair, strlen(nativePair),
                                  canonicalPair, strlen(canonicalPair)),
          "fixed canonical alias accepted");
    CHECK(QHPairedRootLinkAllowed(&s, 0, canonicalPairSlash, strlen(canonicalPairSlash), nativePair,
                                  strlen(nativePair), canonicalPair, strlen(canonicalPair)),
          "single trailing slash accepted");
    const char *badPair[] = {"/rootfs/var/mobile/Containers/Shared/AppGroup/.jbroot-0123456789ABCDEF/var",
                             "/var/mobile/Containers/Shared/AppGroup/.jbroot-OTHER/var",
                             "/var/mobile/Containers/Shared/AppGroup/.jbroot-0123456789ABCDEF/var//",
                             "/var/mobile/Containers/Shared/AppGroup/.jbroot-0123456789ABCDEF/../var"};
    const char nulPair[] = "/var/mobile/Containers/Shared/AppGroup/.jbroot-0123456789ABCDEF/var\0x";
    CHECK(!QHPairedRootLinkAllowed(&s, 0, nulPair, sizeof(nulPair) - 1, nativePair, strlen(nativePair),
                                   canonicalPair, strlen(canonicalPair)),
          "embedded NUL pair not truncated");
    for (size_t i = 0; i < sizeof(badPair) / sizeof(badPair[0]); i++) {
        CHECK(!QHPairedRootLinkAllowed(&s, 0, badPair[i], strlen(badPair[i]), nativePair, strlen(nativePair),
                                       canonicalPair, strlen(canonicalPair)),
              "untrusted pair spelling rejected");
    }
    s.st_uid = 501;
    CHECK(!QHPairedRootLinkAllowed(&s, 0, nativePair, strlen(nativePair), nativePair, strlen(nativePair),
                                   canonicalPair, strlen(canonicalPair)),
          "pair link mobile owner rejected in production");
    s.st_uid = 0;
    s.st_nlink = 2;
    CHECK(!QHPairedRootLinkAllowed(&s, 0, nativePair, strlen(nativePair), nativePair, strlen(nativePair),
                                   canonicalPair, strlen(canonicalPair)),
          "paired var hardlink rejected");
    s.st_nlink = 1;
    s.st_mode = S_IFDIR | 0755;
    CHECK(!QHPairedRootLinkAllowed(&s, 0, nativePair, strlen(nativePair), nativePair, strlen(nativePair),
                                   canonicalPair, strlen(canonicalPair)),
          "paired var directory not a link");

    /* Actual isolated syscall regression probe: baseline's literal var open
     * cannot open the legitimate symlink, regardless of fixture ownership. */
    char directory[] = "/tmp/qh-directory-policy-XXXXXX";
    if (!mkdtemp(directory)) {
        perror("mkdtemp");
        return 2;
    }
    int root = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (root < 0 || mkdirat(root, "private", 0700)) {
        perror("root");
        return 2;
    }
    int privateFD = openat(root, "private", O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (privateFD < 0 || mkdirat(privateFD, "var", 0700) || symlinkat("private/var/", root, "var")) {
        perror("fixture");
        return 2;
    }
    int oldVar = openat(root, "var", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    CHECK(oldVar < 0, "prepatch literal var nofollow rejects legitimate topology");
    if (oldVar >= 0) {
        close(oldVar);
    }
    int fixedVar = openat(privateFD, "var", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    CHECK(fixedVar >= 0, "fixed component nofollow can open fixture");
    if (fixedVar >= 0) {
        close(fixedVar);
    }
    CHECK(unlinkat(root, "var", 0) == 0, "cleanup fixture link");
    CHECK(unlinkat(privateFD, "var", AT_REMOVEDIR) == 0, "cleanup fixture var");
    close(privateFD);
    CHECK(unlinkat(root, "private", AT_REMOVEDIR) == 0, "cleanup fixture private");
    close(root);
    CHECK(rmdir(directory) == 0, "cleanup fixture root");
    printf("DirectoryPolicyTests: %u failures (host predicate/syscall fixtures only)\n", failures);
    return failures ? 1 : 0;
}
