#include "../Shared/QHProcess.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static int checks;
#define CHECK(x)                                                                                             \
    do {                                                                                                     \
        checks++;                                                                                            \
        fprintf(stderr, "Process check %d\n", checks);                                                       \
        if (!(x)) {                                                                                          \
            fprintf(stderr, "Failed line %d: %s\n", __LINE__, #x);                                           \
            exit(1);                                                                                         \
        }                                                                                                    \
    } while (0)
int main(int argc, char **argv) {
    if (argc == 2) {
        if (!strcmp(argv[1], "echo")) {
            char b[1000];
            ssize_t n;
            while ((n = read(0, b, sizeof(b))) > 0) {
                if (write(1, b, (size_t)n) != n) {
                    return 9;
                }
            }
            return 0;
        }
        if (!strcmp(argv[1], "error")) {
            return 7;
        }
        if (!strcmp(argv[1], "large")) {
            char b[10000];
            memset(b, 'z', sizeof(b));
            for (int i = 0; i < 100; i++) {
                if (write(1, b, sizeof(b)) < 0) {
                    break;
                }
            }
            return 0;
        }
        if (!strcmp(argv[1], "stall")) {
            for (;;) {
                pause();
            }
        }
        if (!strcmp(argv[1], "environment")) {
            return getenv("QH_TEST_SECRET") || getenv("DYLD_INSERT_LIBRARIES") ? 8 : 0;
        }
        return 4;
    }
    char output[65536];
    size_t n = 0;
    int status = -1;
    setenv("QH_TEST_SECRET", "synthetic-sentinel", 1);
    CHECK(!QHRunProcess(argv[0], "echo", "abc", 3, output, sizeof(output), &n, &status, 2));
    CHECK(n == 3 && !memcmp(output, "abc", 3) && status == 0);
    char *input = malloc(1000000);
    CHECK(input != NULL);
    memset(input, 'a', 1000000);
    char *big = malloc(1000000);
    CHECK(big != NULL);
    CHECK(!QHRunProcess(argv[0], "echo", input, 1000000, big, 1000000, &n, &status, 4));
    CHECK(n == 1000000 && status == 0 && !memcmp(input, big, n));
    free(big);
    free(input);
    CHECK(!QHRunProcess(argv[0], "error", NULL, 0, output, sizeof(output), &n, &status, 2) && status == 7);
    CHECK(QHRunProcess(argv[0], "large", NULL, 0, output, sizeof(output), &n, &status, 2) == EFBIG);
    CHECK(QHRunProcess(argv[0], "stall", NULL, 0, output, sizeof(output), &n, &status, 1) == ETIMEDOUT);
    CHECK(!QHRunProcess(argv[0], "environment", NULL, 0, output, sizeof(output), &n, &status, 2) &&
          status == 0);
    CHECK(QHRunProcess("/this-path-must-not-exist/quiethosts", "status", NULL, 0, output, sizeof(output), &n,
                       &status, 2) == ENOENT);
    CHECK(QHRunProcess(NULL, "echo", NULL, 0, output, sizeof(output), &n, &status, 2) == EINVAL);
    printf("Process transport: %d checks passed\n", checks);
    return 0;
}
