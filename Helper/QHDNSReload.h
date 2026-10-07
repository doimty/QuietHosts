#ifndef QH_DNS_RELOAD_H
#define QH_DNS_RELOAD_H
#include <signal.h>
#include <sys/types.h>
typedef enum {
    QHDNSReloadOK,
    QHDNSReloadPrepare,
    QHDNSReloadFork,
    QHDNSReloadCredentials,
    QHDNSReloadExec,
    QHDNSReloadWait,
    QHDNSReloadTimeout,
    QHDNSReloadExit,
    QHDNSReloadSignal
} QHDNSReloadStage;
typedef struct {
    QHDNSReloadStage stage;
    int systemError;
    int exitStatus;
    int termSignal;
} QHDNSReloadResult;
/* Internal fixed-purpose runner, NOT a command request API. Production main
 * supplies only its verified jbroot('/usr/bin/killall'). The parent retains its
 * real UID for cancellation; ONLY the child becomes real/effective root.
 * argv is always {-9,mDNSResponder,mDNSResponderHelper}, environment minimal.
 * No Foundation/Objective-C calls occur between fork and exec. */
QHDNSReloadResult QHRunDNSReload(const char *verifiedToolPath, unsigned timeoutSeconds,
                                 volatile sig_atomic_t *watchedChild);
#endif
