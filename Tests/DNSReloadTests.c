#include "../Helper/QHDNSReload.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static unsigned checks;
#define CHECK(x)                                                                                             \
    do {                                                                                                     \
        checks++;                                                                                            \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "DNS fixture failure line%d: %s\n", __LINE__, #x);                               \
            exit(1);                                                                                         \
        }                                                                                                    \
    } while (0)
static void Copy(const char *source, const char *target) {
    int in = open(source, O_RDONLY), out = open(target, O_WRONLY | O_CREAT | O_EXCL, 0755);
    assert(in >= 0 && out >= 0);
    char b[8192];
    ssize_t n;
    while ((n = read(in, b, sizeof(b))) > 0) {
        assert(write(out, b, (size_t)n) == n);
    }
    assert(n == 0);
    close(in);
    close(out);
}
int main(int argc, char **argv) {
    if (argc == 4) {
        if (strcmp(argv[1], "-9") || strcmp(argv[2], "mDNSResponder") ||
            strcmp(argv[3], "mDNSResponderHelper")) {
            return 90;
        }
        gid_t groups[2] = {0};
        int groupCount = getgroups(2, groups);
        char file[4096];
        if (snprintf(file, sizeof(file), "%s.receipt", argv[0]) >= (int)sizeof(file)) {
            return 93;
        }
        int fd = open(file, O_CREAT | O_EXCL | O_WRONLY, 0600);
        if (fd < 0) {
            return 94;
        }
        char text[256];
        int length = snprintf(text, sizeof(text), "uid=%u/%u gid=%u/%u groups=%d [%u,%u] sentinel=%d dyld=%d",
                              (unsigned)getuid(), (unsigned)geteuid(), (unsigned)getgid(),
                              (unsigned)getegid(), groupCount, (unsigned)groups[0], (unsigned)groups[1],
                              getenv("QH_TEST_SENTINEL") != NULL, getenv("DYLD_INSERT_LIBRARIES") != NULL);
        if (length < 0 || (size_t)length >= sizeof(text) || write(fd, text, (size_t)length) != length) {
            close(fd);
            return 95;
        }
        close(fd);
        if (getuid() != 0 || geteuid() != 0 || getgid() != 0 || getegid() != 0) {
            return 91;
        }
        if (getenv("QH_TEST_SENTINEL") || getenv("DYLD_INSERT_LIBRARIES")) {
            return 92;
        }
        if (strstr(argv[0], "tool-fail")) {
            return 7;
        }
        if (strstr(argv[0], "tool-stall")) {
            for (;;) {
                pause();
            }
        }
        return 0;
    }
    volatile sig_atomic_t watched = 0;
    if (argc == 2 && !strcmp(argv[1], "--ordinary")) {
        if (geteuid() == 0) {
            puts("SKIP ordinary denial (root host; privileged fixtures run separately)");
            return 0;
        }
        QHDNSReloadResult r = QHRunDNSReload("/must-not-run", 1, &watched);
        CHECK(r.stage == QHDNSReloadCredentials && r.systemError == EPERM && watched == 0);
        printf("DNS ordinary denial: %u checks passed\n", checks);
        return 0;
    }
    if (argc != 2 || strcmp(argv[1], "--privileged") || geteuid() != 0) {
        return 2;
    }
    char directory[] = "/tmp/qh-dns-mock-XXXXXX";
    CHECK(mkdtemp(directory) != NULL);
    char ok[4096], fail[4096], stall[4096], missing[4096];
    snprintf(ok, sizeof(ok), "%s/tool-ok", directory);
    snprintf(fail, sizeof(fail), "%s/tool-fail", directory);
    snprintf(stall, sizeof(stall), "%s/tool-stall", directory);
    snprintf(missing, sizeof(missing), "%s/missing", directory);
    Copy(argv[0], ok);
    Copy(argv[0], fail);
    Copy(argv[0], stall);
    setenv("QH_TEST_SENTINEL", "synthetic-fixture", 1);
    CHECK(setreuid(501, 0) == 0);
    CHECK(setregid(501, 0) == 0);
    uid_t real = getuid(), effective = geteuid();
    gid_t group = getgid(), egroup = getegid();
    QHDNSReloadResult r = QHRunDNSReload(ok, 3, &watched);
    if (r.stage != QHDNSReloadOK || r.exitStatus != 0 || watched != 0) {
        fprintf(stderr, "DNS mock result stage=%d errno=%d exit=%d signal=%d watched=%d\n", r.stage,
                r.systemError, r.exitStatus, r.termSignal, (int)watched);
        char receiptPath[4096], details[512];
        snprintf(receiptPath, sizeof(receiptPath), "%s.receipt", ok);
        int fd = open(receiptPath, O_RDONLY);
        ssize_t n = fd >= 0 ? read(fd, details, sizeof(details) - 1) : -1;
        if (fd >= 0) {
            close(fd);
        }
        if (n > 0) {
            details[n] = 0;
            fprintf(stderr, "DNS mock child credentials: %s\n", details);
        }
    }
    CHECK(r.stage == QHDNSReloadOK && r.exitStatus == 0 && watched == 0);
    CHECK(getuid() == real && geteuid() == effective && getgid() == group && getegid() == egroup);
    r = QHRunDNSReload(fail, 3, &watched);
    CHECK(r.stage == QHDNSReloadExit && r.exitStatus == 7 && watched == 0);
    r = QHRunDNSReload(missing, 3, &watched);
    CHECK(r.stage == QHDNSReloadExec && r.systemError == ENOENT && watched == 0);
    r = QHRunDNSReload(stall, 1, &watched);
    CHECK(r.stage == QHDNSReloadTimeout || (r.stage == QHDNSReloadSignal && r.termSignal == SIGALRM));
    CHECK(watched == 0 && getuid() == 501 && geteuid() == 0);
    r = QHRunDNSReload("relative", 3, &watched);
    CHECK(r.stage == QHDNSReloadPrepare && r.systemError == EINVAL);
    CHECK(setreuid(0, 0) == 0);
    CHECK(setregid(0, 0) == 0);
    const char *tools[] = {ok, fail, stall};
    char receipt[4096];
    for (size_t i = 0; i < 3; i++) {
        snprintf(receipt, sizeof(receipt), "%s.receipt", tools[i]);
        CHECK(unlink(receipt) == 0);
        CHECK(unlink(tools[i]) == 0);
    }
    CHECK(rmdir(directory) == 0);
    printf("DNS fixed-child identity: %u checks passed (mock tools; no DNS signals)\n", checks);
    return 0;
}
