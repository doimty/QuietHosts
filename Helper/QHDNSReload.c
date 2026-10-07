#include "QHDNSReload.h"
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double Now(void) {
    struct timespec t;
    return clock_gettime(CLOCK_MONOTONIC, &t) == 0 ? (double)t.tv_sec + (double)t.tv_nsec / 1e9 : -1;
}
static void ChildFailure(int fd, QHDNSReloadStage stage, int error) {
    int value[2] = {(int)stage, error};
    ssize_t n;
    do {
        n = write(fd, value, sizeof(value));
    } while (n < 0 && errno == EINTR);
    _exit(126);
}
QHDNSReloadResult QHRunDNSReload(const char *path, unsigned seconds, volatile sig_atomic_t *watchedChild) {
    QHDNSReloadResult result = {QHDNSReloadPrepare, 0, -1, 0};
    if (!path || path[0] != '/' || !seconds || !watchedChild) {
        result.systemError = EINVAL;
        return result;
    }
    *watchedChild = 0;
    if (geteuid() != 0) {
        result.stage = QHDNSReloadCredentials;
        result.systemError = EPERM;
        return result;
    }
    double began = Now();
    if (began < 0) {
        result.systemError = errno;
        return result;
    }
    int pipeFD[2];
    if (pipe(pipeFD)) {
        result.systemError = errno;
        return result;
    }
    if (fcntl(pipeFD[0], F_SETFD, FD_CLOEXEC) < 0 || fcntl(pipeFD[1], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(pipeFD[0], F_SETFL, O_NONBLOCK) < 0) {
        result.systemError = errno;
        close(pipeFD[0]);
        close(pipeFD[1]);
        return result;
    }
    pid_t child = fork();
    if (child < 0) {
        result.stage = QHDNSReloadFork;
        result.systemError = errno;
        close(pipeFD[0]);
        close(pipeFD[1]);
        return result;
    }
    if (child == 0) {
        // C/syscalls only: never call Foundation in a post-fork child.
        close(pipeFD[0]);
        if (setpgid(0, 0)) {
            ChildFailure(pipeFD[1], QHDNSReloadPrepare, errno);
        }
        signal(SIGALRM, SIG_DFL);
        signal(SIGPIPE, SIG_DFL);
        alarm(seconds);
        sigset_t empty;
        sigemptyset(&empty);
        if (sigprocmask(SIG_SETMASK, &empty, NULL)) {
            ChildFailure(pipeFD[1], QHDNSReloadPrepare, errno);
        }
        const gid_t rootGroup = 0;
        if (setgroups(1, &rootGroup) || setgid(0) || setuid(0) || getuid() != 0 || geteuid() != 0 ||
            getgid() != 0 || getegid() != 0) {
            ChildFailure(pipeFD[1], QHDNSReloadCredentials, errno ? errno : EPERM);
        }
        int nullFD = open("/dev/null", O_RDWR);
        if (nullFD < 0) {
            ChildFailure(pipeFD[1], QHDNSReloadPrepare, errno);
        }
        for (int fd = 0; fd <= 2; fd++) {
            if (dup2(nullFD, fd) < 0) {
                ChildFailure(pipeFD[1], QHDNSReloadPrepare, errno);
            }
        }
        if (nullFD > 2) {
            close(nullFD);
        }
        char *argv[] = {(char *)path, "-9", "mDNSResponder", "mDNSResponderHelper", NULL};
        char *environment[] = {"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C", NULL};
        execve(path, argv, environment);
        ChildFailure(pipeFD[1], QHDNSReloadExec, errno);
    }
    close(pipeFD[1]);
    *watchedChild = (sig_atomic_t)child;
    int status = 0;
    for (;;) {
        pid_t waited = waitpid(child, &status, WNOHANG);
        if (waited == child) {
            break;
        }
        if (waited < 0 && errno != EINTR) {
            result.stage = QHDNSReloadWait;
            result.systemError = errno;
            close(pipeFD[0]);
            *watchedChild = 0;
            return result;
        }
        double now = Now();
        if (now < 0 || now - began >= seconds) {
            kill(-child, SIGKILL);
            kill(child, SIGKILL);
            while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
            }
            result.stage = QHDNSReloadTimeout;
            result.systemError = ETIMEDOUT;
            close(pipeFD[0]);
            *watchedChild = 0;
            return result;
        }
        poll(NULL, 0, 20);
    }
    int setup[2];
    ssize_t n;
    do {
        n = read(pipeFD[0], setup, sizeof(setup));
    } while (n < 0 && errno == EINTR);
    close(pipeFD[0]);
    *watchedChild = 0;
    if (n == (ssize_t)sizeof(setup)) {
        result.stage = (QHDNSReloadStage)setup[0];
        result.systemError = setup[1];
        return result;
    }
    if (n != 0) {
        result.stage = QHDNSReloadWait;
        result.systemError = EIO;
        return result;
    }
    if (!WIFEXITED(status)) {
        result.stage = QHDNSReloadSignal;
        result.termSignal = WIFSIGNALED(status) ? WTERMSIG(status) : 0;
        return result;
    }
    result.exitStatus = WEXITSTATUS(status);
    result.stage = result.exitStatus == 0 ? QHDNSReloadOK : QHDNSReloadExit;
    return result;
}
