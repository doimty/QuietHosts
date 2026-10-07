#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import "../Helper/QHFileManager.h"
#import "../Shared/QHRuleEngine.h"
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <limits.h>
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#if !defined(QH_TESTING) || !QH_TESTING
#error FileManagerTests requires QH_TESTING=1. Never link Helper/main.m into this fixture runner.
#endif
static NSUInteger failures;
static void Check(BOOL condition, NSString *label) {
    if (!condition) {
        failures++;
        NSLog(@"FileManagerTests FAIL: %@", label);
    }
}
static void Require(BOOL condition) {
    if (!condition) {
        abort();
    }
}
static NSData *Text(NSString *text) {
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}
static NSString *SHA(NSData *data) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(hash); i++) {
        [s appendFormat:@"%02x", hash[i]];
    }
    return s;
}
static void Put(NSString *path, NSData *data, mode_t mode) {
    int fd = open(path.fileSystemRepresentation, O_CREAT | O_TRUNC | O_WRONLY | O_NOFOLLOW, 0600);
    Require(fd >= 0);
    const unsigned char *bytes = data.bytes;
    NSUInteger left = data.length;
    while (left) {
        ssize_t n = write(fd, bytes, left);
        if (n < 0 && errno == EINTR) {
            continue;
        }
        Require(n > 0);
        bytes += n;
        left -= n;
    }
    Require(fchmod(fd, mode) == 0);
    Require(close(fd) == 0);
}
static NSDictionary *Capture(NSString *directory) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSArray *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL];
    for (NSString *name in entries) {
        NSString *path = [directory stringByAppendingPathComponent:name];
        struct stat s;
        Require(lstat(path.fileSystemRepresentation, &s) == 0);
        NSMutableDictionary *item =
            [@{@"mode" : @(s.st_mode),
               @"inode" : @(s.st_ino),
               @"nlink" : @(s.st_nlink)} mutableCopy];
        if (S_ISREG(s.st_mode)) {
            item[@"sha"] = SHA([NSData dataWithContentsOfFile:path]);
        } else if (S_ISLNK(s.st_mode)) {
            char b[PATH_MAX + 1];
            ssize_t n = readlink(path.fileSystemRepresentation, b, PATH_MAX);
            Require(n > 0);
            b[n] = 0;
            item[@"link"] = [NSString stringWithUTF8String:b];
        } else if (S_ISDIR(s.st_mode)) {
            item[@"children"] = Capture(path);
        }
        out[name] = item;
    }
    return out;
}
@interface QHFixture : NSObject
@property(nonatomic, copy) NSString *directory, *root, *raw, *target, *state, *rawHash;
@property(nonatomic) ino_t rawInode;
@property(nonatomic, strong) QHFileManager *manager;
- (instancetype)initWithMirror:(BOOL)mirror baseline:(NSString *)baseline;
- (NSDictionary *)status;
- (NSDictionary *)apply:(NSData *)data count:(NSUInteger)count revision:(NSString *)revision;
- (NSDictionary *)command:(NSString *)command;
- (void)checkRaw;
@end
@implementation QHFixture
- (instancetype)initWithMirror:(BOOL)mirror baseline:(NSString *)baseline {
    if ((self = [super init])) {
        NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:@"qh-fixture-XXXXXX"];
        char *buffer = strdup(template.fileSystemRepresentation);
        Require(buffer != NULL);
        Require(mkdtemp(buffer) != NULL);
        char real[PATH_MAX];
        Require(realpath(buffer, real) != NULL);
        free(buffer);
        _directory = [NSString stringWithUTF8String:real];
        _root = [_directory stringByAppendingPathComponent:@"mapped"];
        for (NSString *relative in @[ @"mapped/etc", @"mapped/var/lib", @"raw" ]) {
            Require([NSFileManager.defaultManager
                      createDirectoryAtPath:[_directory stringByAppendingPathComponent:relative]
                withIntermediateDirectories:YES
                                 attributes:@{NSFilePosixPermissions : @0700}
                                      error:NULL]);
        }
        _raw = [_directory stringByAppendingPathComponent:@"raw/hosts"];
        _target = [_root stringByAppendingPathComponent:@"etc/hosts"];
        _state = [_root stringByAppendingPathComponent:@"var/lib/quiethosts"];
        Put(_raw, Text(baseline), 0644);
        _rawHash = SHA(Text(baseline));
        struct stat st;
        Require(lstat(_raw.fileSystemRepresentation, &st) == 0);
        _rawInode = st.st_ino;
        if (mirror) {
            Require(symlink(_raw.fileSystemRepresentation, _target.fileSystemRepresentation) == 0);
        }
        _manager = [[QHFileManager alloc] initWithRoot:_root systemHosts:_raw expectedOwner:getuid()];
    }
    return self;
}
- (void)dealloc {
    if (_directory) {
        [NSFileManager.defaultManager removeItemAtPath:_directory error:NULL];
    }
}
- (NSDictionary *)status {
    return [_manager handleCommand:@"status" request:@{}];
}
- (NSDictionary *)apply:(NSData *)data count:(NSUInteger)count revision:(NSString *)revision {
    return [_manager handleCommand:@"apply"
                           request:@{
                               @"expectedRevision" : revision,
                               @"hostsBase64" : [data base64EncodedStringWithOptions:0],
                               @"domainCount" : @(count)
                           }];
}
- (NSDictionary *)command:(NSString *)command {
    return [_manager handleCommand:command request:@{@"expectedRevision" : [self status][@"revision"]}];
}
- (void)checkRaw {
    struct stat st;
    Check(lstat(_raw.fileSystemRepresentation, &st) == 0 && st.st_ino == _rawInode,
          @"raw system inode unchanged");
    Check([SHA([NSData dataWithContentsOfFile:_raw]) isEqual:_rawHash], @"raw system SHA-256 unchanged");
}
@end
static NSString *const Original =
    @"# fixture baseline\n127.0.0.1 localhost\n::1 localhost\n192.0.2.9 local-fixture\n";
static NSData *Blocks(void) {
    return Text(@"0.0.0.0 ads.example\n::1 ads.example\n");
}
static QHFixture *Fixture(BOOL mirror) {
    return [[QHFixture alloc] initWithMirror:mirror baseline:Original];
}
static void Basic(BOOL mirror) {
    QHFixture *f = Fixture(mirror);
    NSDictionary *s = f.status;
    Check([s[@"ok"] boolValue] && [s[@"state"] isEqual:@"unmanaged"] && ![s[@"hasBaseline"] boolValue],
          @"fresh status unmanaged");
    Check(![NSFileManager.defaultManager fileExistsAtPath:f.state], @"status never creates state");
    Check([[f command:@"disable"][@"changed"] boolValue] == NO, @"unmanaged disable no-op");
    Check(![NSFileManager.defaultManager fileExistsAtPath:f.state],
          @"unmanaged disable does not create state");
    NSDictionary *r = [f apply:Blocks() count:1 revision:s[@"revision"]];
    Check([r[@"ok"] boolValue] && [r[@"state"] isEqual:@"active"] && [r[@"changed"] boolValue] &&
              [r[@"hasBaseline"] boolValue],
          @"takeover commits active state");
    Check(![r[@"reloadRequested"] boolValue], @"core has no DNS side effects");
    struct stat st;
    Check(lstat(f.target.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode) &&
              (st.st_mode & 0777) == 0644,
          @"target is regular 0644 not mirror write-through");
    NSData *combined =
        Text([Original stringByAppendingString:[[NSString alloc] initWithData:Blocks()
                                                                     encoding:NSUTF8StringEncoding]]);
    Check([[NSData dataWithContentsOfFile:f.target] isEqual:combined],
          @"baseline bytes prefix preserved with both families");
    NSString *backup = [f.state stringByAppendingPathComponent:@"original.bin"];
    Check([[NSData dataWithContentsOfFile:backup] isEqual:Text(Original)], @"immutable original bytes exact");
    Check(lstat(backup.fileSystemRepresentation, &st) == 0 && (st.st_mode & 0777) == 0400 && st.st_nlink == 1,
          @"backup 0400 single link");
    Check(lstat(f.state.fileSystemRepresentation, &st) == 0 && (st.st_mode & 0777) == 0700,
          @"private state 0700");
    NSDictionary *before = Capture(f.state);
    NSDictionary *targetBefore = Capture([f.target stringByDeletingLastPathComponent]);
    r = [f apply:Blocks() count:1 revision:r[@"revision"]];
    Check([r[@"ok"] boolValue] && ![r[@"changed"] boolValue], @"identical apply no-op");
    r = [f command:@"enable"];
    Check([r[@"ok"] boolValue] && ![r[@"changed"] boolValue], @"repeated enable no-op");
    r = [f command:@"reload"];
    Check([r[@"ok"] boolValue] && ![r[@"changed"] boolValue] && ![r[@"reloadRequested"] boolValue],
          @"core reload is only checked query");
    Check([before isEqual:Capture(f.state)] &&
              [targetBefore isEqual:Capture([f.target stringByDeletingLastPathComponent])],
          @"no-op commands do not rewrite artifacts");
    r = [f command:@"disable"];
    Check([r[@"ok"] boolValue] && [r[@"changed"] boolValue] && [r[@"state"] isEqual:@"inactive"] &&
              [r[@"domainCount"] unsignedIntegerValue] == 1,
          @"disable retains reenable snapshot");
    if (mirror) {
        char text[PATH_MAX + 1];
        ssize_t n = readlink(f.target.fileSystemRepresentation, text, PATH_MAX);
        if (n >= 0) {
            text[n] = 0;
        }
        Check(n > 0 && !strcmp(text, f.raw.fileSystemRepresentation),
              @"disable restores exact original symlink text");
    } else {
        Check(lstat(f.target.fileSystemRepresentation, &st) < 0 && errno == ENOENT,
              @"disable restores absent entry");
    }
    r = [f command:@"disable"];
    Check([r[@"ok"] boolValue] && ![r[@"changed"] boolValue], @"repeated disable no-op");
    r = [f command:@"enable"];
    Check([r[@"ok"] boolValue] && [r[@"changed"] boolValue] &&
              [[NSData dataWithContentsOfFile:f.target] isEqual:combined],
          @"enable reconstructs exact saved rules");
    r = [f.manager handleCommand:@"restore-for-uninstall" request:@{}];
    Check([r[@"ok"] boolValue] && [r[@"state"] isEqual:@"inactive"],
          @"restricted uninstall restore without CAS");
    Check([[NSData dataWithContentsOfFile:backup] isEqual:Text(Original)],
          @"uninstall retains immutable backup");
    [f checkRaw];
}

static void InvalidRequests(void) {
    QHFixture *f = Fixture(YES);
    NSString *rev = f.status[@"revision"];
    NSDictionary *good = @{
        @"expectedRevision" : rev,
        @"hostsBase64" : [Blocks() base64EncodedStringWithOptions:0],
        @"domainCount" : @1
    };
    NSArray *bad = @[
        @{},
        @{@"expectedRevision" : @1}, @{@"expectedRevision" : NSNull.null},
        @{@"expectedRevision" : rev,
          @"hostsBase64" : @"?",
          @"domainCount" : @1},
        @{@"expectedRevision" : rev,
          @"hostsBase64" : @"Zg=",
          @"domainCount" : @1},
        @{@"expectedRevision" : rev,
          @"hostsBase64" : @12,
          @"domainCount" : @1},
        @{@"expectedRevision" : rev,
          @"hostsBase64" : @"",
          @"domainCount" : @YES},
        @{@"expectedRevision" : rev,
          @"hostsBase64" : @"",
          @"domainCount" : @1.5},
        @{@"expectedRevision" : rev,
          @"hostsBase64" : @"",
          @"domainCount" : @(-1)},
        @{@"expectedRevision" : rev,
          @"hostsBase64" : @"",
          @"domainCount" : @300001},
        @{@"expectedRevision" : rev,
          @"hostsBase64" : @"",
          @"domainCount" : @1},
        @{@"expectedRevision" : @"stale",
          @"hostsBase64" : good[@"hostsBase64"],
          @"domainCount" : @1}
    ];
    NSDictionary *original = Capture([f.target stringByDeletingLastPathComponent]);
    for (id request in bad) {
        NSDictionary *r = [f.manager handleCommand:@"apply" request:request];
        Check(![r[@"ok"] boolValue] && ![r[@"changed"] boolValue] &&
                  [r[@"errorCode"] isKindOfClass:NSString.class],
              @"invalid apply rejected with stable error");
        Check(![NSFileManager.defaultManager fileExistsAtPath:f.state], @"invalid apply never creates state");
        Check([original isEqual:Capture([f.target stringByDeletingLastPathComponent])],
              @"invalid apply never partially alters target");
    }
    NSMutableDictionary *extra = [good mutableCopy];
    extra[@"path"] = f.raw;
    Check(![[f.manager handleCommand:@"apply" request:extra][@"ok"] boolValue],
          @"arbitrary extra path forbidden");
    Check(![[f.manager handleCommand:@"status" request:@{@"expectedRevision" : rev}][@"ok"] boolValue],
          @"status exact empty schema");
    Check(![[f.manager handleCommand:@"copy" request:@{}][@"ok"] boolValue], @"unknown command forbidden");
    Check(![[f.manager handleCommand:@"disable" request:@{}][@"ok"] boolValue],
          @"UI mutation requires revision");
    Check(![[f.manager handleCommand:@"restore-for-uninstall" request:@{
        @"force" : @YES
    }][@"ok"] boolValue],
          @"uninstall has no force option");
    Check([[f command:@"enable"][@"errorCode"] isEqual:@"no-snapshot"], @"enable cannot invent snapshot");
    NSArray *invalidHosts = @[
        @"ads.example\n", @"0.0.0.0 ads.example\n", @"0.0.0.0 localhost\n::1 localhost\n",
        @"0.0.0.0 ads.example\n::1 other.example\n", @"0.0.0.0 ads.example\n::1 ads.example"
    ];
    for (NSString *hosts in invalidHosts) {
        Check([[[f apply:Text(hosts) count:1
                  revision:rev] objectForKey:@"errorCode"] isEqual:@"invalid-hosts"],
              @"noncanonical compiled input rejected");
    }
    NSDictionary *r = [f apply:Blocks() count:1 revision:rev];
    NSDictionary *state = Capture(f.state), *target = Capture([f.target stringByDeletingLastPathComponent]);
    Check([[f apply:NSData.data count:0 revision:rev][@"errorCode"] isEqual:@"revision-conflict"],
          @"stale approved revision cannot overwrite");
    Check([state isEqual:Capture(f.state)] &&
              [target isEqual:Capture([f.target stringByDeletingLastPathComponent])],
          @"stale CAS writes nothing");
    r = [f apply:NSData.data count:0 revision:r[@"revision"]];
    Check([r[@"ok"] boolValue] && [r[@"domainCount"] unsignedIntegerValue] == 0, @"empty compiled set valid");
    [f checkRaw];
}
static void Refusals(void) {
    for (NSString *kind in @[
             @"regular", @"secondary", @"symlink", @"dangling", @"relative", @"hardlink", @"fifo",
             @"state-mode", @"state-link", @"lock-link", @"lock-hardlink", @"etc-link", @"var-link",
             @"wrong-owner", @"root-alias"
         ]) {
        @autoreleasepool {
            QHFixture *f = Fixture(YES);
            NSString *revision = f.status[@"revision"];
            NSString *external = [f.directory stringByAppendingPathComponent:@"foreign"];
            Put(external, Text(@"foreign bytes"), 0600);
            if ([@[ @"regular", @"symlink", @"dangling", @"relative", @"hardlink", @"fifo" ]
                    containsObject:kind]) {
                Require(unlink(f.target.fileSystemRepresentation) == 0);
            }
            if ([kind isEqual:@"regular"]) {
                Put(f.target, Text(@"foreign hosts"), 0644);
            }
            if ([kind isEqual:@"secondary"]) {
                Put([[f.target stringByDeletingLastPathComponent]
                        stringByAppendingPathComponent:@"hosts.lmb"],
                    Text(@"secondary"), 0644);
            }
            if ([kind isEqual:@"symlink"]) {
                Require(symlink(external.fileSystemRepresentation, f.target.fileSystemRepresentation) == 0);
            }
            if ([kind isEqual:@"dangling"]) {
                Require(symlink("/does-not-exist-qh-fixture", f.target.fileSystemRepresentation) == 0);
            }
            if ([kind isEqual:@"relative"]) {
                Require(symlink("hosts", f.target.fileSystemRepresentation) == 0);
            }
            if ([kind isEqual:@"hardlink"]) {
                Require(link(external.fileSystemRepresentation, f.target.fileSystemRepresentation) == 0);
            }
            if ([kind isEqual:@"fifo"]) {
                Require(mkfifo(f.target.fileSystemRepresentation, 0600) == 0);
            }
            if ([kind hasPrefix:@"state-"] || [kind hasPrefix:@"lock-"]) {
                if ([kind isEqual:@"state-link"]) {
                    Require(symlink([f.raw stringByDeletingLastPathComponent].fileSystemRepresentation,
                                    f.state.fileSystemRepresentation) == 0);
                } else {
                    Require(mkdir(f.state.fileSystemRepresentation,
                                  [kind isEqual:@"state-mode"] ? 0755 : 0700) == 0);
                    NSString *lock = [f.state stringByAppendingPathComponent:@"lock"];
                    if ([kind isEqual:@"lock-link"]) {
                        Require(symlink(external.fileSystemRepresentation, lock.fileSystemRepresentation) ==
                                0);
                    }
                    if ([kind isEqual:@"lock-hardlink"]) {
                        Require(link(external.fileSystemRepresentation, lock.fileSystemRepresentation) == 0);
                    }
                }
            }
            if ([kind isEqual:@"etc-link"] || [kind isEqual:@"var-link"]) {
                NSString *part = [kind isEqual:@"etc-link"] ? @"etc" : @"var";
                NSString *old = [f.root stringByAppendingPathComponent:part],
                         *moved = [f.directory stringByAppendingPathComponent:part];
                Require(rename(old.fileSystemRepresentation, moved.fileSystemRepresentation) == 0);
                Require(symlink(moved.fileSystemRepresentation, old.fileSystemRepresentation) == 0);
            }
            if ([kind isEqual:@"wrong-owner"]) {
                f.manager = [[QHFileManager alloc] initWithRoot:f.root
                                                    systemHosts:f.raw
                                                  expectedOwner:getuid() + 1];
            }
            if ([kind isEqual:@"root-alias"]) {
                NSString *raw = [[f.target stringByDeletingLastPathComponent]
                    stringByAppendingPathComponent:@"raw-hosts"];
                Put(raw, Text(Original), 0644);
                f.manager = [[QHFileManager alloc] initWithRoot:f.root
                                                    systemHosts:raw
                                                  expectedOwner:getuid()];
            }
            NSDictionary *before = Capture(f.root);
            NSDictionary *r = [f apply:Blocks() count:1 revision:revision];
            Check(![r[@"ok"] boolValue] && ![r[@"changed"] boolValue],
                  [NSString stringWithFormat:@"unsafe fixture refused: %@", kind]);
            Check([before isEqual:Capture(f.root)], @"conflict preserves all entries");
            Check([[NSData dataWithContentsOfFile:external] isEqual:Text(@"foreign bytes")],
                  @"foreign link target never overwritten");
            [f checkRaw];
        }
    }
}

static void BaselinesAndCorruption(void) {
    for (NSString *baseline in @[
             @"192.0.2.1 ads.example\n", @"127.0.0.1 Ads.Example.\n", @"0.0.0.0 ads.example\n",
             @"::1 alias ads.example\n"
         ]) {
        QHFixture *f = [[QHFixture alloc] initWithMirror:YES baseline:baseline];
        NSDictionary *r = [f apply:Blocks() count:1 revision:f.status[@"revision"]];
        Check([r[@"errorCode"] isEqual:@"baseline-conflict"],
              @"any existing baseline mapping overlaps explicitly");
        Check(![NSFileManager.defaultManager fileExistsAtPath:f.state],
              @"baseline conflict precedes all writes");
        [f checkRaw];
    }
    QHFixture *relative = Fixture(YES);
    Require(unlink(relative.target.fileSystemRepresentation) == 0);
    Require(symlink("../../raw/hosts", relative.target.fileSystemRepresentation) == 0);
    Check([[relative apply:Blocks() count:1 revision:relative.status[@"revision"]][@"ok"] boolValue],
          @"verified relative mirror accepted");
    Check([[relative command:@"disable"][@"ok"] boolValue], @"relative mirror restored");
    char linkText[64];
    ssize_t n = readlink(relative.target.fileSystemRepresentation, linkText, 63);
    if (n >= 0) {
        linkText[n] = 0;
    }
    Check(n > 0 && !strcmp(linkText, "../../raw/hosts"), @"relative original spelling retained");
    [relative checkRaw];
    for (NSString *corruption in @[
             @"json", @"version", @"active-type", @"baseline", @"snapshot", @"state-symlink",
             @"backup-symlink", @"raw-changed", @"target-replaced", @"inactive-mirror", @"secondary-after"
         ]) {
        @autoreleasepool {
            QHFixture *f = Fixture(YES);
            Check([[f apply:Blocks() count:1 revision:f.status[@"revision"]][@"ok"] boolValue],
                  @"corruption setup apply");
            NSString *state = [f.state stringByAppendingPathComponent:@"state.json"],
                     *backup = [f.state stringByAppendingPathComponent:@"original.bin"];
            NSDictionary *metadata =
                [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:state]
                                                options:0
                                                  error:NULL];
            if ([corruption isEqual:@"json"]) {
                Put(state, Text(@"{broken"), 0600);
            }
            if ([corruption isEqual:@"version"] || [corruption isEqual:@"active-type"]) {
                NSMutableDictionary *bad = [metadata mutableCopy];
                bad[[corruption isEqual:@"version"] ? @"version" : @"active"] = @2;
                Put(state, [NSJSONSerialization dataWithJSONObject:bad options:0 error:NULL], 0600);
            }
            if ([corruption isEqual:@"baseline"]) {
                Require(chmod(backup.fileSystemRepresentation, 0600) == 0);
                Put(backup, Text(@"corrupted baseline"), 0400);
            }
            if ([corruption isEqual:@"snapshot"]) {
                Put([f.state stringByAppendingPathComponent:[metadata[@"slot"] boolValue]
                                                                ? @"snapshot-b.bin"
                                                                : @"snapshot-a.bin"],
                    NSData.data, 0600);
            }
            if ([corruption isEqual:@"state-symlink"] || [corruption isEqual:@"backup-symlink"]) {
                NSString *path = [corruption isEqual:@"state-symlink"] ? state : backup;
                Require(unlink(path.fileSystemRepresentation) == 0);
                Require(symlink(f.raw.fileSystemRepresentation, path.fileSystemRepresentation) == 0);
            }
            if ([corruption isEqual:@"raw-changed"]) {
                Put(f.raw, Text(@"127.0.0.1 changed-raw\n"), 0644);
            }
            if ([corruption isEqual:@"target-replaced"]) {
                Require(unlink(f.target.fileSystemRepresentation) == 0);
                Put(f.target, Text(@"foreign after apply"), 0644);
            }
            if ([corruption isEqual:@"inactive-mirror"]) {
                Check([[f command:@"disable"][@"ok"] boolValue], @"inactive corruption setup");
                Require(unlink(f.target.fileSystemRepresentation) == 0);
                Require(symlink("hosts", f.target.fileSystemRepresentation) == 0);
            }
            if ([corruption isEqual:@"secondary-after"]) {
                Put([[f.target stringByDeletingLastPathComponent]
                        stringByAppendingPathComponent:@"hosts.lmb"],
                    Text(@"foreign secondary"), 0644);
            }
            NSDictionary *before = Capture(f.root);
            NSData *rawBefore = [NSData dataWithContentsOfFile:f.raw];
            NSDictionary *r = [f.manager handleCommand:@"restore-for-uninstall" request:@{}];
            Check(![r[@"ok"] boolValue] && ![r[@"changed"] boolValue],
                  [NSString stringWithFormat:@"corruption refuses even uninstall: %@", corruption]);
            Check([before isEqual:Capture(f.root)] &&
                      [rawBefore isEqual:[NSData dataWithContentsOfFile:f.raw]],
                  @"corrupt state and foreign artifacts preserved");
            if (![corruption isEqual:@"raw-changed"]) {
                [f checkRaw];
            }
        }
    }
    QHFixture *f = Fixture(YES);
    NSDictionary *s = f.status;
    [f apply:Blocks() count:1 revision:s[@"revision"]];
    NSString *lock = [f.state stringByAppendingPathComponent:@"lock"];
    int fd = open(lock.fileSystemRepresentation, O_RDWR);
    Require(fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0);
    NSDictionary *before = Capture(f.root);
    Check([f.status[@"errorCode"] isEqual:@"busy"], @"parallel command returns bounded busy");
    Check([before isEqual:Capture(f.root)], @"busy transaction writes nothing");
    close(fd);
    Check([f.status[@"ok"] boolValue], @"every command reopens and releases lock");
}
static void Crash(QHFixture *f, NSString *command, NSDictionary *request, NSString *point) {
    pid_t pid = fork();
    Require(pid >= 0);
    if (!pid) {
        signal(SIGALRM, SIG_DFL);
        alarm(30);
        QHSetTransactionFault(point);
        [f.manager handleCommand:command request:request];
        _exit(87);
    }
    int status = 0;
    pid_t got;
    do {
        got = waitpid(pid, &status, 0);
    } while (got < 0 && errno == EINTR);
    Check(got == pid && WIFEXITED(status) && WEXITSTATUS(status) == 86,
          [NSString stringWithFormat:@"fault point reached: %@", point]);
}
static NSDictionary *ApplyRequest(QHFixture *f) {
    return @{
        @"expectedRevision" : f.status[@"revision"],
        @"hostsBase64" : [Blocks() base64EncodedStringWithOptions:0],
        @"domainCount" : @1
    };
}
static void CrashRecovery(void);
NSUInteger RunFileManagerTests(void) {
    failures = 0;
    @autoreleasepool {
        Basic(YES);
        Basic(NO);
    }
    @autoreleasepool {
        InvalidRequests();
        Refusals();
        BaselinesAndCorruption();
    }
    @autoreleasepool {
        CrashRecovery();
    }
    NSLog(@"FileManagerTests: %lu failures", (unsigned long)failures);
    return failures;
}
static void CrashRecovery(void) {
    NSArray *points = @[
        @"after-journal", @"after-backup", @"after-rename-before-sync", @"after-target", @"recoverstate",
        @"after-state", @"after-journal-clear"
    ];
    for (NSNumber *mirror in @[ @NO, @YES ]) {
        for (NSString *point in points) {
            @autoreleasepool {
                QHFixture *f = Fixture(mirror.boolValue);
                Crash(f, @"apply", ApplyRequest(f), point);
                NSDictionary *r = f.status;
                Check([r[@"ok"] boolValue] && [r[@"state"] isEqual:@"active"] &&
                          [r[@"domainCount"] unsignedIntegerValue] == 1,
                      @"journal replay completes valid transaction");
                Check(![r[@"reloadRequested"] boolValue], @"status recovery never requests DNS");
                if ([point isEqual:@"after-journal"] || [point isEqual:@"after-backup"]) {
                    Check([r[@"changed"] boolValue], @"recovery reports actual target rename");
                } else {
                    Check(![r[@"changed"] boolValue], @"already renamed recovery is not a new target change");
                }
                if (![point isEqual:@"after-journal-clear"]) {
                    Check([r[@"reloadPending"] boolValue],
                          @"replayed journal signals unconfirmed DNS reload");
                }
                Check(![NSFileManager.defaultManager
                          fileExistsAtPath:[f.state stringByAppendingPathComponent:@"journal.json"]],
                      @"successful replay clears journal");
                NSDictionary *state = Capture(f.state),
                             *target = Capture([f.target stringByDeletingLastPathComponent]);
                Check(![f.status[@"changed"] boolValue], @"second recovery query is no-op");
                Check([state isEqual:Capture(f.state)] &&
                          [target isEqual:Capture([f.target stringByDeletingLastPathComponent])],
                      @"replay is idempotent");
                Check([[f command:@"disable"][@"ok"] boolValue], @"recovered baseline supports disable");
                [f checkRaw];
            }
        }
    }
    for (NSNumber *mirror in @[ @NO, @YES ]) {
        for (NSString *point in points) {
            @autoreleasepool {
                QHFixture *f = Fixture(mirror.boolValue);
                [f apply:Blocks() count:1 revision:f.status[@"revision"]];
                Crash(f, @"disable", @{@"expectedRevision" : f.status[@"revision"]}, point);
                NSDictionary *r = f.status;
                struct stat st;
                Check([r[@"ok"] boolValue] && [r[@"state"] isEqual:@"inactive"],
                      @"disable crash recovers inactive state");
                if (mirror.boolValue) {
                    Check(lstat(f.target.fileSystemRepresentation, &st) == 0 && S_ISLNK(st.st_mode),
                          @"disable recovery restores mirror");
                } else {
                    Check(lstat(f.target.fileSystemRepresentation, &st) < 0 && errno == ENOENT,
                          @"disable recovery restores absence");
                }
                Check([[f command:@"enable"][@"ok"] boolValue],
                      @"disable recovery preserves enable snapshot");
                [f checkRaw];
            }
        }
    }
}
