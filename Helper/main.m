#import <Foundation/Foundation.h>
#import "QHFileManager.h"
#include "QHDNSReload.h"
#import "../Shared/QHPlatform.h"
#if defined(QH_ROOTLESS) && QH_ROOTLESS
#import "QHRootlessPaths.h"
#endif
#include <sys/stat.h>
#include <sys/wait.h>
#include <poll.h>
#include <spawn.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <string.h>
#include <stdlib.h>
#include <notify.h>

static const NSUInteger InputLimit = 48u * 1024u * 1024u;
static volatile sig_atomic_t DNSChild;
static void Watchdog(int signalNumber) {
    (void)signalNumber;
    if (DNSChild > 0) {
        kill(-(pid_t)DNSChild, SIGKILL);
        kill((pid_t)DNSChild, SIGKILL);
    }
    _exit(124); // no unbounded Foundation or stdout work inside the signal handler
}
static double Monotonic(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts)) {
        return 0;
    }
    return ts.tv_sec + ts.tv_nsec / 1e9;
}
static NSDictionary *Failure(NSString *code) {
    return @{
        @"ok" : @NO,
        @"state" : @"error",
        @"revision" : @"",
        @"domainCount" : @0,
        @"changed" : @NO,
        @"reloadRequested" : @NO,
        @"hasBaseline" : @NO,
        @"errorCode" : code
    };
}
static NSDictionary *ReadRequest(BOOL optional, NSString **failure) {
    if (optional && isatty(STDIN_FILENO)) {
        return @{};
    }
    NSMutableData *input = [NSMutableData data];
    double deadline = Monotonic() + 15;
    int flags = fcntl(STDIN_FILENO, F_GETFL);
    if (flags < 0) {
        if (optional && errno == EBADF) {
            return @{};
        }
        *failure = @"input-failed";
        return nil;
    }
    if (fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)) {
        *failure = @"input-failed";
        return nil;
    }
    for (;;) {
        double remaining = deadline - Monotonic();
        if (remaining <= 0) {
            *failure = @"input-timeout";
            return nil;
        }
        struct pollfd p = {.fd = STDIN_FILENO, .events = POLLIN};
        int ready = poll(&p, 1, (int)(remaining * 1000) + 1);
        if (ready < 0 && errno == EINTR) {
            continue;
        }
        if (ready < 0 || (p.revents & (POLLERR | POLLNVAL))) {
            *failure = @"input-failed";
            return nil;
        }
        if (!ready) {
            continue;
        }
        unsigned char bytes[65536];
        ssize_t n = read(STDIN_FILENO, bytes, sizeof(bytes));
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) {
            continue;
        }
        if (n < 0) {
            *failure = @"input-failed";
            return nil;
        }
        if (!n) {
            break;
        }
        if ((NSUInteger)n > InputLimit - input.length) {
            *failure = @"input-too-large";
            return nil;
        }
        [input appendBytes:bytes length:(NSUInteger)n];
    }
    if (!input.length && optional) {
        return @{};
    }
    if (!input.length) {
        *failure = @"input-required";
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:input options:0 error:NULL];
    if (![object isKindOfClass:NSDictionary.class]) {
        *failure = @"invalid-json";
        return nil;
    }
    return object;
}

/* Fixed executable + fixed arguments + fixed environment only. There is no
 * general process runner here and no caller-supplied path/argument expansion. */
static NSString *RestartDNS(QHDNSReloadResult *diagnostic) {
    const char *mapped = QH_PLATFORM_PATH("/usr/bin/killall");
    if (!mapped || mapped[0] != '/') {
        return @"reload-unavailable";
    }
    char *path = strdup(mapped);
    if (!path) {
        return @"reload-unavailable";
    }
    struct stat st;
    if (lstat(path, &st) || !S_ISREG(st.st_mode) || st.st_uid != 0 || (st.st_mode & 0022) ||
        !(st.st_mode & 0111)) {
        free(path);
        return @"reload-unavailable";
    }
    *diagnostic = QHRunDNSReload(path, 15, &DNSChild);
    free(path);
    switch (diagnostic->stage) {
        case QHDNSReloadOK: return nil;
        case QHDNSReloadCredentials: return @"reload-credentials-failed";
        case QHDNSReloadPrepare:
        case QHDNSReloadFork: return @"reload-spawn-failed";
        case QHDNSReloadExec: return @"reload-exec-failed";
        case QHDNSReloadWait: return @"reload-wait-failed";
        case QHDNSReloadTimeout: return @"reload-timeout";
        case QHDNSReloadExit:
        case QHDNSReloadSignal: return @"reload-exit-failed";
    }
    return @"reload-exit-failed";
}

static int Emit(NSDictionary *result) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
    if (!data || data.length > 65535) {
        data = [NSJSONSerialization dataWithJSONObject:Failure(@"internal-error") options:0 error:NULL];
    }
    NSMutableData *line = [data mutableCopy];
    [line appendBytes:"\n" length:1];
    const unsigned char *bytes = line.bytes;
    NSUInteger remaining = line.length;
    while (remaining) {
        ssize_t n = write(STDOUT_FILENO, bytes, remaining);
        if (n < 0 && errno == EINTR) {
            continue;
        }
        if (n <= 0) {
            return 1;
        }
        bytes += n;
        remaining -= (NSUInteger)n;
    }
    return [result[@"ok"] boolValue] ? 0 : 1;
}
int main(int argc, char *argv[]) {
    /* Keep real uid 501 when launched by mobile. The caller can cancel its
     * helper; only effective uid must be root. No setuid(0)/setgid(0). */
    signal(SIGPIPE, SIG_IGN);
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = Watchdog;
    sigemptyset(&action.sa_mask);
    sigaction(SIGALRM, &action, NULL);
    alarm(75);
    umask(077);
    @autoreleasepool {
        @try {
            if (geteuid() != 0 || (getuid() != 0 && getuid() != 501)) {
                return Emit(Failure(@"permission-denied"));
            }
            if (argc != 2 || !argv[1]) {
                return Emit(Failure(@"invalid-command"));
            }
            NSString *command = [NSString stringWithUTF8String:argv[1]];
            if (!command ||
                ![@[ @"status", @"apply", @"enable", @"disable", @"reload", @"restore-for-uninstall" ]
                    containsObject:command]) {
                return Emit(Failure(@"invalid-command"));
            }
            BOOL status = [command isEqual:@"status"], uninstall = [command isEqual:@"restore-for-uninstall"];
            if (uninstall && getuid() != 0) {
                return Emit(Failure(@"permission-denied"));
            }
            NSString *error = nil;
            NSDictionary *request = ReadRequest(status || uninstall, &error);
            if (!request) {
                return Emit(Failure(error ?: @"invalid-request"));
            }
#if defined(QH_ROOTLESS) && QH_ROOTLESS
            NSString *rootPath = nil, *systemHosts = nil;
            NSString *pathError = QHRootlessResolvePaths(
                [NSString stringWithUTF8String:QH_PLATFORM_PATH("/")], &rootPath, &systemHosts);
            if (pathError) return Emit(Failure(pathError));
            QHFileManager *manager = [[QHFileManager alloc] initWithRoot:rootPath
                                                             systemHosts:systemHosts
                                                           expectedOwner:0];
#else
            const char *root = jbroot("/");
            if (!root || root[0] != '/') {
                return Emit(Failure(@"root-unavailable"));
            }
            NSString *rootPath = [NSString stringWithUTF8String:root];
            while (rootPath.length > 1 && [rootPath hasSuffix:@"/"]) {
                rootPath = [rootPath substringToIndex:rootPath.length - 1];
            }
            NSString *brandName =
                [NSString stringWithFormat:@".jbroot-%016llX", (unsigned long long)jbrand()];
            if (!rootPath || ![rootPath.lastPathComponent isEqual:brandName]) {
                return Emit(Failure(@"paired-root-conflict"));
            }
            /* Official Bootstrap pairs this exact brand beneath the fixed
             * AppGroup parent. Never infer a secondary root from link text. */
            NSString *pairedDataRoot = [[@"/var/mobile/Containers/Shared/AppGroup"
                stringByAppendingPathComponent:brandName] stringByAppendingPathComponent:@"var"];
            QHFileManager *manager = [[QHFileManager alloc] initWithRoot:rootPath
                                                             systemHosts:@"/etc/hosts"
                                                           expectedOwner:0
                                                          pairedDataRoot:pairedDataRoot];
#endif
            NSMutableDictionary *result = [[manager handleCommand:command request:request] mutableCopy];
            BOOL changed = [result[@"changed"] boolValue];
            if (!status && (changed || ([result[@"ok"] boolValue] && [command isEqual:@"reload"]))) {
                QHDNSReloadResult reload = {QHDNSReloadPrepare, 0, -1, 0};
                NSString *reloadError = RestartDNS(&reload);
                result[@"reloadRequested"] = @(reloadError == nil);
                result[@"reloadPending"] = @(reloadError != nil);
                if (reloadError) {
                    result[@"reloadError"] = reloadError; // files remain committed, no false rollback
                    result[@"reloadErrno"] = @(reload.systemError);
                    result[@"reloadExitStatus"] = @(reload.exitStatus);
                    result[@"reloadSignal"] = @(reload.termSignal);
                }
            }
            if (changed) {
                notify_post("com.doimty.quiethosts.changed");
            }
            return Emit(result);
        } @catch (__unused NSException *exception) {
            return Emit(Failure(@"internal-error"));
        }
    }
}
