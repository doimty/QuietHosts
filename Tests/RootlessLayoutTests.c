#include "../Helper/QHRootlessLayout.h"
#include "../Helper/QHDirectoryPolicy.h"
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned checks, failures;
static void check(int condition, const char *name) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", name); }
}
static void expect(int root, int raw, const char *wanted) {
    QHRootlessLayoutSnapshot snapshot, untouched;
    memset(&snapshot, 0xA5, sizeof(snapshot)); untouched = snapshot;
    const char *got = QHRootlessInspectLayout(root, raw, geteuid(), &snapshot);
    check(wanted ? (got && strcmp(got, wanted) == 0) : got == NULL,
          wanted ? wanted : "valid protected flat layout accepted");
    if (wanted) check(memcmp(&snapshot, &untouched, sizeof(snapshot)) == 0,
                      "failed inspection does not publish partial snapshot");
    else check(S_ISDIR(snapshot.root.st_mode) && S_ISDIR(snapshot.etc.st_mode) &&
               S_ISDIR(snapshot.var.st_mode) && S_ISDIR(snapshot.lib.st_mode),
               "accepted snapshot contains protected directory identities");
}
static void setup(int condition) {
    if (!condition) { perror("fixture setup"); exit(2); }
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    int base = open(argv[1], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    setup(base >= 0);
    setup(mkdirat(base, "managed", 0755) == 0);
    setup(mkdirat(base, "raw", 0755) == 0);
    int root = openat(base, "managed", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int raw = openat(base, "raw", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    setup(root >= 0 && raw >= 0);
    setup(mkdirat(root, "etc", 0755) == 0 && mkdirat(root, "var", 0755) == 0);
    int etc = openat(root, "etc", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int var = openat(root, "var", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    setup(etc >= 0 && var >= 0);
    setup(mkdirat(var, "lib", 0755) == 0);
    int lib = openat(var, "lib", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    setup(lib >= 0);
    expect(root, raw, NULL);
    expect(-1, raw, "rootless-unsafe-root");
    expect(root, -1, "rootless-unsafe-system-directory");
    expect(root, root, "root-alias");
    expect(root, etc, "root-alias");
    check(strcmp(QHRootlessInspectLayout(root, raw, geteuid(), NULL),
                 "rootless-invalid-preflight") == 0, "NULL output rejected");
    struct stat synthetic = {0};
    synthetic.st_mode = S_IFDIR | 0755; synthetic.st_uid = 0;
    check(QHRootlessRootAllowed(&synthetic, 0), "numeric root directory accepted");
    synthetic.st_uid = 501;
    check(QHContainerRootAllowed(&synthetic, 0), "RootHide retains its separate mobile exception");
    check(!QHRootlessRootAllowed(&synthetic, 0), "rootless rejects mobile-owned root");
    synthetic.st_uid = 0; synthetic.st_mode |= 0020;
    check(!QHRootlessRootAllowed(&synthetic, 0), "rootless rejects group-writable root");
    synthetic.st_mode = S_IFLNK | 0777;
    check(!QHRootlessRootAllowed(&synthetic, 0), "rootless rejects unanchored symlink root");
    check(!QHRootlessRootAllowed(NULL, 0), "NULL stat rejected");
    setup(fchmod(root, 0775) == 0); expect(root, raw, "rootless-unsafe-root");
    setup(fchmod(root, 0755) == 0);
    setup(fchmod(raw, 0777) == 0); expect(root, raw, "rootless-unsafe-system-directory");
    setup(fchmod(raw, 0755) == 0);
    setup(fchmod(etc, 0775) == 0); expect(root, raw, "rootless-unsupported-etc-layout");
    setup(fchmod(etc, 0755) == 0);
    setup(renameat(root, "etc", root, "etc.saved") == 0);
    expect(root, raw, "rootless-unsupported-etc-layout");
    setup(symlinkat("etc.saved", root, "etc") == 0);
    expect(root, raw, "rootless-unsupported-etc-layout");
    setup(unlinkat(root, "etc", 0) == 0 && renameat(root, "etc.saved", root, "etc") == 0);
    setup(fchmod(var, 0775) == 0); expect(root, raw, "rootless-unsupported-var-layout");
    setup(fchmod(var, 0755) == 0);
    setup(renameat(root, "var", root, "var.saved") == 0);
    expect(root, raw, "rootless-unsupported-var-layout");
    setup(symlinkat("var.saved", root, "var") == 0);
    expect(root, raw, "rootless-unsupported-var-layout");
    setup(unlinkat(root, "var", 0) == 0);
    setup(symlinkat("private/var", root, "var") == 0);
    expect(root, raw, "rootless-unsupported-var-layout");
    setup(unlinkat(root, "var", 0) == 0 && renameat(root, "var.saved", root, "var") == 0);
    setup(fchmod(lib, 0775) == 0); expect(root, raw, "rootless-unsafe-state-parent");
    setup(fchmod(lib, 0755) == 0);
    setup(renameat(var, "lib", var, "lib.saved") == 0);
    setup(symlinkat("lib.saved", var, "lib") == 0);
    expect(root, raw, "rootless-unsafe-state-parent");
    setup(unlinkat(var, "lib", 0) == 0 && renameat(var, "lib.saved", var, "lib") == 0);
    int file = openat(etc, "hosts.lmb", O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    setup(file >= 0); close(file);
    expect(root, raw, "secondary-conflict");
    setup(unlinkat(etc, "hosts.lmb", 0) == 0);
    setup(symlinkat("missing", etc, "hosts.lmb") == 0);
    expect(root, raw, "secondary-conflict");
    setup(unlinkat(etc, "hosts.lmb", 0) == 0);
    /* Pure preflight must neither create state nor own the caller's fds. */
    struct stat state;
    check(fstatat(lib, "quiethosts", &state, AT_SYMLINK_NOFOLLOW) != 0,
          "preflight has not created a state directory");
    int lowest = dup(base); setup(lowest >= 0); close(lowest);
    for (unsigned i = 0; i < 128; i++) expect(root, raw, NULL);
    int again = dup(base); setup(again >= 0);
    check(again == lowest, "128 observations leak no descriptors"); close(again);
    check(fcntl(root, F_GETFD) >= 0 && fcntl(raw, F_GETFD) >= 0,
          "caller descriptors remain open");
    close(lib); close(var); close(etc); close(raw); close(root); close(base);
    printf("RootlessLayout: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
