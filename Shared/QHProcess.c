#include "QHProcess.h"
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double Now(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) {
        return -1;
    }
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}
static void Close(int *fd) {
    if (*fd >= 0) {
        close(*fd);
        *fd = -1;
    }
}
static int Pair(int p[2]) {
    if (pipe(p)) {
        return errno;
    }
    for (int i = 0; i < 2; i++) {
        if (fcntl(p[i], F_SETFD, FD_CLOEXEC) < 0) {
            int e = errno;
            Close(&p[0]);
            Close(&p[1]);
            return e;
        }
    }
    return 0;
}
int QHRunProcess(const char *path, const char *command, const void *input, size_t inputLength, char *output,
                 size_t capacity, size_t *length, int *status, unsigned int seconds) {
    if (!path || !command || !output || !length || !status || (!input && inputLength) || capacity == 0 ||
        seconds == 0) {
        return EINVAL;
    }
    *length = 0;
    *status = -1;
    int in[2] = {-1, -1}, out[2] = {-1, -1}, err = 0;
    pid_t pid = -1;
    posix_spawn_file_actions_t actions;
    bool initialized = false;
    if ((err = Pair(in)) || (err = Pair(out))) {
        goto done;
    }
    if ((err = posix_spawn_file_actions_init(&actions))) {
        goto done;
    }
    initialized = true;
#define ACTION(expr)                                                                                         \
    do {                                                                                                     \
        if ((err = (expr)))                                                                                  \
            goto done;                                                                                       \
    } while (0)
    ACTION(posix_spawn_file_actions_adddup2(&actions, in[0], STDIN_FILENO));
    ACTION(posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO));
    ACTION(posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0));
    ACTION(posix_spawn_file_actions_addclose(&actions, in[1]));
    ACTION(posix_spawn_file_actions_addclose(&actions, out[0]));
    ACTION(posix_spawn_file_actions_addclose(&actions, in[0]));
    ACTION(posix_spawn_file_actions_addclose(&actions, out[1]));
    char *argv[] = {(char *)path, (char *)command, NULL};
    char *env[] = {"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C", NULL};
    err = posix_spawn(&pid, path, &actions, NULL, argv, env);
    if (err) {
        goto done;
    }
    Close(&in[0]);
    Close(&out[1]);
    if (fcntl(in[1], F_SETFL, O_NONBLOCK) < 0 || fcntl(out[0], F_SETFL, O_NONBLOCK) < 0) {
        err = errno;
        goto kill_child;
    }
    // Block SIGPIPE only in this worker thread; never change the process-wide handler.
    sigset_t set, previous;
    sigemptyset(&set);
    sigaddset(&set, SIGPIPE);
    if (pthread_sigmask(SIG_BLOCK, &set, &previous)) {
        err = EIO;
        goto kill_child;
    }
    sigset_t pending;
    sigpending(&pending);
    bool priorPending = sigismember(&pending, SIGPIPE) == 1;
    size_t sent = 0;
    bool eof = false, reaped = false;
    int childStatus = 0;
    double start = Now();
    if (start < 0) {
        err = EIO;
        goto unmask;
    }
    while (!eof || !reaped) {
        if (sent == inputLength) {
            Close(&in[1]);
        }
        double now = Now();
        if (now < 0 || now - start > seconds) {
            err = ETIMEDOUT;
            break;
        }
        struct pollfd fds[2] = {{out[0], POLLIN, 0}, {in[1], POLLOUT, 0}};
        int n = poll(fds, 2, 100);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            err = errno;
            break;
        }
        if (out[0] >= 0 && (fds[0].revents & (POLLIN | POLLHUP | POLLERR))) {
            char buffer[8192];
            ssize_t got = read(out[0], buffer, sizeof(buffer));
            if (got > 0) {
                if ((size_t)got > capacity - *length) {
                    err = EFBIG;
                    break;
                }
                for (ssize_t i = 0; i < got; i++) {
                    output[(*length)++] = buffer[i];
                }
            } else if (got == 0) {
                eof = true;
                Close(&out[0]);
            } else if (errno != EINTR && errno != EAGAIN) {
                err = errno;
                break;
            }
        }
        if (in[1] >= 0 && (fds[1].revents & (POLLOUT | POLLHUP | POLLERR))) {
            size_t remaining = inputLength - sent;
            if (remaining > 65536) {
                remaining = 65536;
            }
            ssize_t wrote = write(in[1], (const char *)input + sent, remaining);
            if (wrote > 0) {
                sent += (size_t)wrote;
            } else if (wrote < 0 && errno != EINTR && errno != EAGAIN) {
                err = errno;
                break;
            }
        }
        if (!reaped) {
            pid_t p = waitpid(pid, &childStatus, WNOHANG);
            if (p == pid) {
                reaped = true;
            } else if (p < 0 && errno != EINTR) {
                err = errno;
                break;
            }
        }
    }
    if (!err) {
        if (sent != inputLength) {
            err = EPIPE;
        } else if (!WIFEXITED(childStatus)) {
            err = EIO;
        } else {
            *status = WEXITSTATUS(childStatus);
        }
    }
unmask:
    if (!priorPending) {
        sigpending(&pending);
        if (sigismember(&pending, SIGPIPE) == 1) {
            int signalNumber = 0;
            sigwait(&set, &signalNumber);
        }
    }
    pthread_sigmask(SIG_SETMASK, &previous, NULL);
    if (reaped) {
        pid = -1;
    }
kill_child:
    Close(&in[1]);
    Close(&out[0]);
    if (pid > 0) {
        if (err) {
            kill(pid, SIGKILL);
        }
        while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {
        }
        pid = -1;
    }
done:
    if (initialized) {
        posix_spawn_file_actions_destroy(&actions);
    }
    Close(&in[0]);
    Close(&in[1]);
    Close(&out[0]);
    Close(&out[1]);
    return err;
}
