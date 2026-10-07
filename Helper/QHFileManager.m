#import "QHFileManager.h"
#import "../Shared/QHRuleEngine.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <arpa/inet.h>
#include <limits.h>
#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static const NSUInteger MaxHosts = 32u * 1024u * 1024u;
static const NSUInteger MaxBaseline = 1024u * 1024u;
static const NSUInteger MaxMetadata = 64u * 1024u;
static NSString *const FailureName = @"QHTransactionFailure";
#ifdef QH_TESTING
static NSString *FaultPoint;
void QHSetTransactionFault(NSString *point) {
    FaultPoint = [point copy];
}
static void Fault(NSString *point) {
    if ([FaultPoint isEqual:point]) {
        _exit(86);
    }
}
#else
static void Fault(__unused NSString *point) {
}
#endif
static void Fail(NSString *code) {
    @throw [NSException exceptionWithName:FailureName reason:code userInfo:nil];
}
static NSString *Digest(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    char text[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) {
        snprintf(text + i * 2, 3, "%02x", bytes[i]);
    }
    return [NSString stringWithUTF8String:text];
}
static BOOL String(id x, NSUInteger max) {
    return [x isKindOfClass:NSString.class] && [x length] <= max;
}
static BOOL Integer(id x, unsigned long long max) {
    if (![x isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)x) == CFBooleanGetTypeID()) {
        return NO;
    }
    double d = [x doubleValue];
    return d >= 0 && d <= max && d == (double)[x unsignedLongLongValue];
}
static BOOL Keys(NSDictionary *d, NSArray *keys) {
    return [d isKindOfClass:NSDictionary.class] &&
           [[NSSet setWithArray:d.allKeys] isEqual:[NSSet setWithArray:keys]];
}
static NSData *JSON(id object) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:NULL];
    if (!d || d.length > MaxMetadata) {
        Fail(@"metadata-invalid");
    }
    return d;
}
static void SyncDir(int fd) {
    if (fsync(fd) == 0) {
        return;
    }
    /* Darwin reports EINVAL/ENOTSUP for directory fsync on some mounts.
       Never swallow EIO, ENOSPC, EBADF, or permissions errors. */
#if defined(__APPLE__)
    if (errno == EINVAL || errno == ENOTSUP) {
        return;
    }
#endif
    Fail(@"directory-sync-failed");
}
static void SyncFile(int fd) {
    if (fsync(fd)) {
        Fail(@"file-sync-failed");
    }
#if defined(__APPLE__) && defined(F_FULLFSYNC)
    if (fcntl(fd, F_FULLFSYNC) && errno != EINVAL && errno != ENOTSUP) {
        Fail(@"file-sync-failed");
    }
#endif
}
static BOOL SameStat(struct stat a, struct stat b) {
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode && a.st_uid == b.st_uid &&
           a.st_gid == b.st_gid && a.st_nlink == b.st_nlink && a.st_size == b.st_size &&
           a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec &&
           a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
           a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec;
}
static void CheckDir(int fd, uid_t owner, BOOL privateDir) {
    struct stat s;
    if (fd < 0 || fstat(fd, &s) || !S_ISDIR(s.st_mode) || s.st_uid != owner || (s.st_mode & 0022) ||
        (privateDir && (s.st_mode & 0777) != 0700)) {
        Fail(@"unsafe-directory");
    }
}
static void CheckFile(struct stat s, uid_t owner, NSUInteger cap, mode_t exactMode) {
    if (!S_ISREG(s.st_mode) || s.st_uid != owner || s.st_nlink != 1 || s.st_size < 0 ||
        (unsigned long long)s.st_size > cap || (s.st_mode & 07022) ||
        (exactMode && (s.st_mode & 0777) != exactMode)) {
        Fail(@"unsafe-file");
    }
}
static NSData *ReadFile(int dir, NSString *name, uid_t owner, NSUInteger cap, mode_t mode, BOOL optional) {
    int fd = openat(dir, name.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) {
        if (optional && errno == ENOENT) {
            return nil;
        }
        Fail(@"unsafe-file");
    }
    NSMutableData *data = [NSMutableData data];
    @try {
        struct stat before, after;
        if (fstat(fd, &before)) {
            Fail(@"read-failed");
        }
        CheckFile(before, owner, cap, mode);
        unsigned char buffer[65536];
        for (;;) {
            ssize_t n = read(fd, buffer, sizeof(buffer));
            if (n < 0 && errno == EINTR) {
                continue;
            }
            if (n < 0) {
                Fail(@"read-failed");
            }
            if (!n) {
                break;
            }
            if ((NSUInteger)n > cap - data.length) {
                Fail(@"size-limit");
            }
            [data appendBytes:buffer length:(NSUInteger)n];
        }
        if (fstat(fd, &after) || !SameStat(before, after) || data.length != (NSUInteger)after.st_size) {
            Fail(@"file-raced");
        }
        struct stat entry;
        if (fstatat(dir, name.fileSystemRepresentation, &entry, AT_SYMLINK_NOFOLLOW) ||
            !SameStat(after, entry)) {
            Fail(@"file-raced");
        }
    } @finally {
        close(fd);
    }
    return data;
}
static NSDictionary *ReadJSON(int dir, NSString *name, uid_t owner) {
    NSData *d = ReadFile(dir, name, owner, MaxMetadata, 0600, YES);
    if (!d) {
        return nil;
    }
    id o = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![o isKindOfClass:NSDictionary.class]) {
        Fail(@"metadata-invalid");
    }
    return o;
}
static NSString *NewTemp(void) {
    return [@".qh-" stringByAppendingString:NSUUID.UUID.UUIDString];
}
static BOOL TempName(id name) {
    if (!String(name, 40) || [name length] != 40 || ![name hasPrefix:@".qh-"]) {
        return NO;
    }
    return [[NSUUID alloc] initWithUUIDString:[name substringFromIndex:4]] != nil;
}
static NSString *WriteTemp(int dir, NSData *data, mode_t mode, uid_t owner) {
    NSString *name = NewTemp();
    int fd = openat(dir, name.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                    0600);
    if (fd < 0) {
        Fail(@"write-failed");
    }
    @try {
        const unsigned char *p = data.bytes;
        NSUInteger left = data.length;
        while (left) {
            ssize_t n = write(fd, p, left > 65536 ? 65536 : left);
            if (n < 0 && errno == EINTR) {
                continue;
            }
            if (n <= 0) {
                Fail(@"write-failed");
            }
            p += n;
            left -= (NSUInteger)n;
            Fault(@"partial-write");
        }
        struct stat s;
        if (fstat(fd, &s) || s.st_uid != owner || s.st_nlink != 1 || fchmod(fd, mode)) {
            Fail(@"write-failed");
        }
        SyncFile(fd);
    } @catch (NSException *e) {
        unlinkat(dir, name.fileSystemRepresentation, 0);
        @throw e;
    } @finally {
        close(fd);
    }
    return name;
}
static void AtomicData(int dir, NSString *name, NSData *data, uid_t owner, mode_t mode) {
    /* Validate any old entry before replacing it. Caller holds our flock. */
    ReadFile(dir, name, owner, MaxHosts, mode, YES);
    NSString *tmp = WriteTemp(dir, data, mode, owner);
    if (renameat(dir, tmp.fileSystemRepresentation, dir, name.fileSystemRepresentation)) {
        Fail(@"rename-failed");
    }
    SyncDir(dir);
}
static NSDictionary *Fingerprint(int dir, NSString *name, uid_t owner, NSUInteger cap) {
    struct stat s, after;
    if (fstatat(dir, name.fileSystemRepresentation, &s, AT_SYMLINK_NOFOLLOW)) {
        if (errno == ENOENT) {
            return @{@"kind" : @"missing"};
        }
        Fail(@"target-unreadable");
    }
    if (s.st_uid != owner || s.st_nlink != 1) {
        Fail(@"unsafe-target");
    }
    NSString *kind, *hash, *text = @"";
    if (S_ISREG(s.st_mode)) {
        kind = @"regular";
        hash = Digest(ReadFile(dir, name, owner, cap, 0, NO));
    } else if (S_ISLNK(s.st_mode)) {
        char buf[PATH_MAX + 1];
        ssize_t n = readlinkat(dir, name.fileSystemRepresentation, buf, PATH_MAX);
        if (n <= 0 || n >= PATH_MAX) {
            Fail(@"unsafe-target");
        }
        text = [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding];
        if (!text || [text rangeOfString:@"\0"].location != NSNotFound) {
            Fail(@"unsafe-target");
        }
        kind = @"symlink";
        hash = Digest([text dataUsingEncoding:NSUTF8StringEncoding]);
    } else {
        Fail(@"unsafe-target");
    }
    if (fstatat(dir, name.fileSystemRepresentation, &after, AT_SYMLINK_NOFOLLOW) || !SameStat(s, after)) {
        Fail(@"file-raced");
    }
    return @{
        @"kind" : kind,
        @"hash" : hash,
        @"text" : text,
        @"dev" : @((uint64_t)s.st_dev),
        @"ino" : @((uint64_t)s.st_ino),
        @"uid" : @(s.st_uid),
        @"gid" : @(s.st_gid),
        @"mode" : @(s.st_mode),
        @"size" : @((uint64_t)s.st_size),
        @"nlink" : @(s.st_nlink),
        @"mtime" : @((int64_t)s.st_mtimespec.tv_sec),
        @"mtimeNS" : @(s.st_mtimespec.tv_nsec)
    };
}

static void ValidateFP(id f) {
    if (![f isKindOfClass:NSDictionary.class]) {
        Fail(@"metadata-invalid");
    }
    if ([f[@"kind"] isEqual:@"missing"]) {
        if (!Keys(f, @[ @"kind" ])) {
            Fail(@"metadata-invalid");
        }
        return;
    }
    if (!Keys(f,
              @[
                  @"kind", @"hash", @"text", @"dev", @"ino", @"uid", @"gid", @"mode", @"size", @"nlink",
                  @"mtime", @"mtimeNS"
              ]) ||
        ![@[ @"regular", @"symlink" ] containsObject:f[@"kind"]] || !String(f[@"hash"], 64) ||
        [f[@"hash"] length] != 64 || !String(f[@"text"], PATH_MAX)) {
        Fail(@"metadata-invalid");
    }
    for (NSString *key in
         @[ @"dev", @"ino", @"uid", @"gid", @"mode", @"size", @"nlink", @"mtime", @"mtimeNS" ]) {
        if (!Integer(f[key], ULLONG_MAX)) {
            Fail(@"metadata-invalid");
        }
    }
}
static void ValidateState(id s) {
    if (!Keys(s,
              @[
                  @"version", @"revision", @"active", @"domainCount", @"slot", @"snapshotHash",
                  @"baselineHash", @"original", @"system", @"target"
              ]) ||
        ![s[@"version"] isEqual:@1] || !String(s[@"revision"], 64) ||
        ![[NSUUID alloc] initWithUUIDString:s[@"revision"]] || !Integer(s[@"domainCount"], 300000) ||
        !Integer(s[@"slot"], 1) || ![s[@"active"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)s[@"active"]) != CFBooleanGetTypeID() ||
        !String(s[@"snapshotHash"], 64) || [s[@"snapshotHash"] length] != 64 ||
        !String(s[@"baselineHash"], 64) || [s[@"baselineHash"] length] != 64) {
        Fail(@"metadata-invalid");
    }
    ValidateFP(s[@"original"]);
    ValidateFP(s[@"system"]);
    ValidateFP(s[@"target"]);
    if (![@[ @"missing", @"symlink" ] containsObject:s[@"original"][@"kind"]] ||
        ![s[@"system"][@"kind"] isEqual:@"regular"] ||
        ([s[@"active"] boolValue] && ![s[@"target"][@"kind"] isEqual:@"regular"]) ||
        (![s[@"active"] boolValue] && ![s[@"target"][@"kind"] isEqual:s[@"original"][@"kind"]])) {
        Fail(@"metadata-invalid");
    }
}
static NSString *Slot(id s) {
    return [s[@"slot"] unsignedIntegerValue] ? @"snapshot-b.bin" : @"snapshot-a.bin";
}
static NSData *Overlay(NSData *baseline, NSData *compiled) {
    NSString *base = [[NSString alloc] initWithData:baseline encoding:NSUTF8StringEncoding];
    if (!base || memchr(baseline.bytes, 0, baseline.length)) {
        Fail(@"baseline-invalid");
    }
    NSString *rules = [[NSString alloc] initWithData:compiled encoding:NSUTF8StringEncoding];
    NSArray *lines = [rules componentsSeparatedByString:@"\n"];
    NSMutableSet *domains = [NSMutableSet set];
    for (NSUInteger i = 0; i + 1 < lines.count; i += 2) {
        [domains addObject:[lines[i] substringFromIndex:8]];
    }
    NSCharacterSet *white = NSCharacterSet.whitespaceCharacterSet;
    for (NSString *line in [base componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        @autoreleasepool {
            NSString *body = [[line componentsSeparatedByString:@"#"] firstObject];
            NSMutableArray *tokens = [NSMutableArray array];
            for (NSString *t in [body componentsSeparatedByCharactersInSet:white]) {
                if (t.length) {
                    [tokens addObject:t];
                }
            }
            if (!tokens.count) {
                continue;
            }
            if (tokens.count < 2) {
                Fail(@"baseline-invalid");
            }
            unsigned char address[16];
            NSString *ip = tokens[0];
            BOOL v4 = inet_pton(AF_INET, ip.UTF8String, address) == 1;
            BOOL v6 = !v4 && inet_pton(AF_INET6, ip.UTF8String, address) == 1;
            if (!v4 && !v6) {
                Fail(@"baseline-invalid");
            }
            /* Even an existing blocking mapping is baseline-owned. Never
             * broaden/change its address-family semantics implicitly. */
            for (NSUInteger i = 1; i < tokens.count; i++) {
                NSString *domain = [tokens[i] lowercaseString];
                if ([domain hasSuffix:@"."]) {
                    domain = [domain substringToIndex:domain.length - 1];
                }
                if ([domains containsObject:domain]) {
                    Fail(@"baseline-conflict");
                }
            }
        }
    }
    NSMutableData *out = [baseline mutableCopy];
    if (out.length && ((const unsigned char *)out.bytes)[out.length - 1] != '\n') {
        [out appendBytes:"\n" length:1];
    }
    for (NSString *line in lines) {
        @autoreleasepool {
            if (!line.length) {
                continue;
            }
            NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
            if (d.length > MaxHosts - out.length) {
                Fail(@"size-limit");
            }
            [out appendData:d];
        }
    }
    return out;
}

@interface QHTransaction : NSObject
@property(nonatomic) int rootFD, etcFD, rawFD, varFD, libFD, stateFD, lockFD;
@property(nonatomic) uid_t owner;
@property(nonatomic, copy) NSString *rootPath, *systemPath, *rawName, *canonicalSystem;
@property(nonatomic) BOOL recovered, actualChanged;
@property(nonatomic, strong) NSDictionary *state, *target, *system;
@property(nonatomic, strong) NSData *baseline, *snapshot;
- (instancetype)initWithRoot:(NSString *)root system:(NSString *)system owner:(uid_t)owner;
- (void)openState:(BOOL)create;
- (void)anchors;
- (void)load;
- (void)recover;
- (NSDictionary *)response;
- (BOOL)transact:(NSData *)snapshot active:(BOOL)active count:(NSUInteger)count;
@end
@implementation QHTransaction
- (instancetype)initWithRoot:(NSString *)root system:(NSString *)system owner:(uid_t)owner {
    if ((self = [super init])) {
        _rootFD = _etcFD = _rawFD = _varFD = _libFD = _stateFD = _lockFD = -1;
        _owner = owner;
        _rootPath = [root copy];
        _systemPath = [system copy];
        _rawName = system.lastPathComponent;
        _rootFD = open(root.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        CheckDir(_rootFD, owner, NO);
        _etcFD = openat(_rootFD, "etc", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        CheckDir(_etcFD, owner, NO);
        char resolved[PATH_MAX];
        if (!root.isAbsolutePath || !system.isAbsolutePath ||
            !realpath(system.stringByDeletingLastPathComponent.fileSystemRepresentation, resolved)) {
            Fail(@"unsafe-system-directory");
        }
        NSString *rawParent = [NSString stringWithUTF8String:resolved];
        _canonicalSystem = [rawParent stringByAppendingPathComponent:_rawName];
        _rawFD = open(rawParent.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        CheckDir(_rawFD, owner, NO);
        struct stat a, b;
        fstat(_etcFD, &a);
        fstat(_rawFD, &b);
        if (a.st_dev == b.st_dev && a.st_ino == b.st_ino) {
            Fail(@"root-alias");
        }
        fstat(_rootFD, &a);
        fstat(_rawFD, &b);
        if (a.st_dev == b.st_dev && a.st_ino == b.st_ino) {
            Fail(@"root-alias");
        }
    }
    return self;
}
- (void)dealloc {
    int fds[] = {_lockFD, _stateFD, _libFD, _varFD, _rawFD, _etcFD, _rootFD};
    for (NSUInteger i = 0; i < sizeof(fds) / sizeof(fds[0]); i++) {
        if (fds[i] >= 0) {
            close(fds[i]);
        }
    }
}
- (void)openState:(BOOL)create {
    if (_varFD < 0) {
        _varFD = openat(_rootFD, "var", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    }
    CheckDir(_varFD, _owner, NO);
    if (_libFD < 0) {
        _libFD = openat(_varFD, "lib", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    }
    CheckDir(_libFD, _owner, NO);
    if (create) {
        if (mkdirat(_libFD, "quiethosts", 0700) && errno != EEXIST) {
            Fail(@"state-create-failed");
        }
        SyncDir(_libFD);
    }
    if (_stateFD < 0) {
        _stateFD = openat(_libFD, "quiethosts", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    }
    if (_stateFD < 0 && errno == ENOENT && !create) {
        return;
    }
    CheckDir(_stateFD, _owner, YES);
    if (_lockFD >= 0) {
        [self anchors];
        return;
    }
    _lockFD =
        openat(_stateFD, "lock", O_RDWR | (create ? O_CREAT : 0) | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
    if (_lockFD < 0 && errno == ENOENT && !create) {
        return;
    }
    if (_lockFD < 0) {
        Fail(@"lock-failed");
    }
    struct stat s;
    if (fstat(_lockFD, &s)) {
        Fail(@"lock-failed");
    }
    CheckFile(s, _owner, 0, 0600);
    if (flock(_lockFD, LOCK_EX | LOCK_NB)) {
        Fail(@"busy");
    }
    [self anchors];
}
- (void)anchors {
    int f = open(_rootPath.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    @try {
        CheckDir(f, _owner, NO);
        struct stat a, b;
        char resolved[PATH_MAX];
        if (!realpath(_systemPath.stringByDeletingLastPathComponent.fileSystemRepresentation, resolved) ||
            ![[_canonicalSystem stringByDeletingLastPathComponent]
                isEqual:[NSString stringWithUTF8String:resolved]]) {
            Fail(@"system-directory-changed");
        }
        if (stat(resolved, &a) || fstat(_rawFD, &b) || !S_ISDIR(a.st_mode) || a.st_uid != _owner ||
            (a.st_mode & 0022) || a.st_dev != b.st_dev || a.st_ino != b.st_ino) {
            Fail(@"system-directory-changed");
        }
        if (fstat(f, &a) || fstat(_rootFD, &b) || a.st_dev != b.st_dev || a.st_ino != b.st_ino) {
            Fail(@"directory-raced");
        }
        const char *names[] = {"etc", "var", "lib", "quiethosts"};
        int parents[] = {_rootFD, _rootFD, _varFD, _libFD};
        int children[] = {_etcFD, _varFD, _libFD, _stateFD};
        for (NSUInteger i = 0; i < 4; i++) {
            if (children[i] < 0) {
                continue;
            }
            CheckDir(children[i], _owner, i == 3);
            if (fstatat(parents[i], names[i], &a, AT_SYMLINK_NOFOLLOW) || fstat(children[i], &b) ||
                !S_ISDIR(a.st_mode) || a.st_dev != b.st_dev || a.st_ino != b.st_ino) {
                Fail(@"directory-raced");
            }
        }
        if (_lockFD >= 0 &&
            (fstat(_lockFD, &b) || fstatat(_stateFD, "lock", &a, AT_SYMLINK_NOFOLLOW) || !SameStat(a, b))) {
            Fail(@"lock-raced");
        }
        if (fstatat(_etcFD, "hosts.lmb", &a, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT) {
            Fail(@"secondary-conflict");
        }
    } @finally {
        if (f >= 0) {
            close(f);
        }
    }
}
- (void)verifyLinkText:(NSString *)text {
    if (!text.length ||
        [text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        Fail(@"mirror-conflict");
    }
    if (text.isAbsolutePath) {
        /* Only the fixed raw path and its canonical /etc directory alias. */
        if (![text isEqual:_systemPath] && ![text isEqual:_canonicalSystem]) {
            Fail(@"mirror-conflict");
        }
        return;
    }
    NSArray<NSString *> *parts = [text componentsSeparatedByString:@"/"];
    if (![[parts lastObject] isEqual:_rawName]) {
        Fail(@"mirror-conflict");
    }
    int dir = dup(_etcFD);
    @try {
        CheckDir(dir, _owner, NO);
        for (NSUInteger i = 0; i + 1 < parts.count; i++) {
            NSString *part = parts[i];
            if (!part.length || [part isEqual:@"."]) {
                continue;
            }
            int next =
                openat(dir, part.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (next < 0) {
                Fail(@"mirror-conflict");
            }
            close(dir);
            dir = next;
            CheckDir(dir, _owner, NO);
        }
        struct stat a, b;
        if (fstat(dir, &a) || fstat(_rawFD, &b) || a.st_dev != b.st_dev || a.st_ino != b.st_ino) {
            Fail(@"mirror-conflict");
        }
    } @finally {
        if (dir >= 0) {
            close(dir);
        }
    }
}
- (void)verifyMirror:(NSDictionary *)entry {
    if ([entry[@"kind"] isEqual:@"missing"]) {
        return;
    }
    if (![entry[@"kind"] isEqual:@"symlink"]) {
        Fail(@"unmanaged-target");
    }
    [self verifyLinkText:entry[@"text"]];
    if (![entry isEqual:Fingerprint(_etcFD, @"hosts", _owner, MaxHosts)] ||
        ![_system isEqual:Fingerprint(_rawFD, _rawName, _owner, MaxBaseline)]) {
        Fail(@"file-raced");
    }
}
- (NSData *)baselineForState:(NSDictionary *)state allowPending:(BOOL)pending {
    NSData *d = ReadFile(_stateFD, @"original.bin", _owner, MaxBaseline, 0400, YES);
    if (!d && pending) {
        d = ReadFile(_stateFD, @"original.pending", _owner, MaxBaseline, 0400, NO);
    }
    if (!d || ![Digest(d) isEqual:state[@"baselineHash"]]) {
        Fail(@"backup-corrupt");
    }
    return d;
}
- (NSData *)snapshotForState:(NSDictionary *)state {
    NSData *d = ReadFile(_stateFD, Slot(state), _owner, MaxHosts, 0600, NO);
    NSUInteger count = 0;
    if (![Digest(d) isEqual:state[@"snapshotHash"]] || !QHValidateCompiledHosts(d, &count, NULL) ||
        count != [state[@"domainCount"] unsignedIntegerValue]) {
        Fail(@"snapshot-corrupt");
    }
    return d;
}
- (void)validateContents:(NSDictionary *)state baseline:(NSData *)baseline snapshot:(NSData *)snapshot {
    if (![state[@"system"] isEqual:_system] || ![Digest(baseline) isEqual:_system[@"hash"]]) {
        Fail(@"system-changed");
    }
    if ([state[@"original"][@"kind"] isEqual:@"symlink"]) {
        [self verifyLinkText:state[@"original"][@"text"]];
    }
    if ([state[@"active"] boolValue]) {
        NSData *combined = Overlay(baseline, snapshot);
        if (![Digest(combined) isEqual:state[@"target"][@"hash"]]) {
            Fail(@"metadata-invalid");
        }
    } else if ([state[@"original"][@"kind"] isEqual:@"symlink"] &&
               ![state[@"original"][@"text"] isEqual:state[@"target"][@"text"]]) {
        Fail(@"metadata-invalid");
    }
}
- (void)load {
    [self anchors];
    _system = Fingerprint(_rawFD, _rawName, _owner, MaxBaseline);
    if (![_system[@"kind"] isEqual:@"regular"]) {
        Fail(@"unsafe-system-file");
    }
    [self recover];
    _target = Fingerprint(_etcFD, @"hosts", _owner, MaxHosts);
    _state = _stateFD >= 0 ? ReadJSON(_stateFD, @"state.json", _owner) : nil;
    if (!_state) {
        if (_stateFD >= 0) {
            if (ReadFile(_stateFD, @"original.bin", _owner, MaxBaseline, 0400, YES)) {
                Fail(@"orphan-backup");
            }
            /* No provenance exists before the first journal. Never replace a
             * pending original/slot with today's raw file and call it recovery. */
            if (ReadFile(_stateFD, @"original.pending", _owner, MaxBaseline, 0400, YES) ||
                ReadFile(_stateFD, @"snapshot-a.bin", _owner, MaxHosts, 0600, YES) ||
                ReadFile(_stateFD, @"snapshot-b.bin", _owner, MaxHosts, 0600, YES)) {
                Fail(@"orphan-preparation");
            }
        }
        [self verifyMirror:_target];
        _baseline = ReadFile(_rawFD, _rawName, _owner, MaxBaseline, 0, NO);
        if (![Digest(_baseline) isEqual:_system[@"hash"]]) {
            Fail(@"file-raced");
        }
        Overlay(_baseline, NSData.data); // reject malformed originals before takeover
        return;
    }
    if (_lockFD < 0) {
        Fail(@"lock-missing");
    }
    ValidateState(_state);
    _baseline = [self baselineForState:_state allowPending:NO];
    _snapshot = [self snapshotForState:_state];
    [self validateContents:_state baseline:_baseline snapshot:_snapshot];
    if (![_target isEqual:_state[@"target"]]) {
        Fail(@"target-conflict");
    }
    if (![_state[@"active"] boolValue]) {
        [self verifyMirror:_target];
    }
}
- (void)recover {
    if (_stateFD < 0) {
        return;
    }
    NSDictionary *j = ReadJSON(_stateFD, @"journal.json", _owner);
    if (!j) {
        return;
    }
    if (_lockFD < 0) {
        Fail(@"lock-missing");
    }
    [self anchors];
    if (!Keys(j, @[ @"version", @"before", @"after", @"beforeTarget", @"afterTarget", @"stagedName" ]) ||
        ![j[@"version"] isEqual:@1] || !String(j[@"stagedName"], 40)) {
        Fail(@"journal-invalid");
    }
    NSDictionary *after = j[@"after"], *before = j[@"before"];
    ValidateState(after);
    ValidateFP(j[@"beforeTarget"]);
    ValidateFP(j[@"afterTarget"]);
    if (![after[@"target"] isEqual:j[@"afterTarget"]]) {
        Fail(@"journal-invalid");
    }
    if ((id)before != NSNull.null) {
        ValidateState(before);
        if (![before[@"target"] isEqual:j[@"beforeTarget"]] ||
            ![before[@"original"] isEqual:after[@"original"]] ||
            ![before[@"baselineHash"] isEqual:after[@"baselineHash"]] ||
            ![before[@"system"] isEqual:after[@"system"]] ||
            [before[@"revision"] isEqual:after[@"revision"]]) {
            Fail(@"journal-invalid");
        }
    } else if (![after[@"original"] isEqual:j[@"beforeTarget"]]) {
        Fail(@"journal-invalid");
    }
    NSDictionary *diskState = ReadJSON(_stateFD, @"state.json", _owner);
    if (diskState) {
        ValidateState(diskState);
    }
    if (!((!diskState && (id)before == NSNull.null) || [diskState isEqual:before] ||
          [diskState isEqual:after])) {
        Fail(@"journal-lineage");
    }
    NSDictionary *now = Fingerprint(_etcFD, @"hosts", _owner, MaxHosts);
    BOOL isBefore = [now isEqual:j[@"beforeTarget"]], isAfter = [now isEqual:j[@"afterTarget"]];
    if (!isBefore && !isAfter) {
        Fail(@"recovery-conflict");
    }
    NSData *base = [self baselineForState:after allowPending:YES], *snapshot = [self snapshotForState:after];
    [self validateContents:after baseline:base snapshot:snapshot];
    NSString *tmp = j[@"stagedName"];
    BOOL missing = [j[@"afterTarget"][@"kind"] isEqual:@"missing"];
    if ((missing && tmp.length) || (!missing && !TempName(tmp))) {
        Fail(@"journal-invalid");
    }
    if (isBefore && !isAfter && !missing &&
        ![Fingerprint(_etcFD, tmp, _owner, MaxHosts) isEqual:j[@"afterTarget"]]) {
        Fail(@"staging-conflict");
    }
    /* No writes above this line. Foreign target means preserve every artifact.
     * Replaying an already-renamed target still leaves DNS reload unconfirmed. */
    _recovered = ![j[@"beforeTarget"] isEqual:j[@"afterTarget"]] || _recovered;
    if (!ReadFile(_stateFD, @"original.bin", _owner, MaxBaseline, 0400, YES)) {
        if (renameat(_stateFD, "original.pending", _stateFD, "original.bin")) {
            Fail(@"backup-commit-failed");
        }
        SyncDir(_stateFD);
    }
    Fault(@"after-backup");
    if (isBefore && !isAfter) {
        [self anchors];
        if (![Fingerprint(_rawFD, _rawName, _owner, MaxBaseline) isEqual:_system] ||
            ![Fingerprint(_etcFD, @"hosts", _owner, MaxHosts) isEqual:j[@"beforeTarget"]]) {
            Fail(@"target-conflict");
        }
        if (missing) {
            if (unlinkat(_etcFD, "hosts", 0)) {
                Fail(@"rename-failed");
            }
        } else if (renameat(_etcFD, tmp.fileSystemRepresentation, _etcFD, "hosts")) {
            Fail(@"rename-failed");
        }
        _actualChanged = YES;
        Fault(@"after-rename-before-sync");
        SyncDir(_etcFD);
    }
    SyncDir(_etcFD); // also sync an already-renamed target during replay
    Fault(@"after-target");
    if (![Fingerprint(_etcFD, @"hosts", _owner, MaxHosts) isEqual:j[@"afterTarget"]]) {
        Fail(@"target-conflict");
    }
    Fault(@"recoverstate");
    AtomicData(_stateFD, @"state.json", JSON(after), _owner, 0600);
    Fault(@"after-state");
    if (unlinkat(_stateFD, "journal.json", 0)) {
        Fail(@"journal-remove-failed");
    }
    SyncDir(_stateFD);
    Fault(@"after-journal-clear");
}
- (NSDictionary *)response {
    /* load has proved metadata against the current entry and raw baseline. */
    NSString *revision =
        _state ? _state[@"revision"] : Digest(JSON(@{@"target" : _target, @"system" : _system}));
    return @{
        @"ok" : @YES,
        @"state" : _state ? ([_state[@"active"] boolValue] ? @"active" : @"inactive") : @"unmanaged",
        @"revision" : revision,
        @"domainCount" : _state ? _state[@"domainCount"] : @0,
        @"changed" : @(_actualChanged),
        @"reloadRequested" : @NO,
        @"reloadPending" : @(_recovered),
        @"hasBaseline" : @(_state != nil)
    };
}
- (BOOL)transact:(NSData *)snapshot active:(BOOL)active count:(NSUInteger)count {
    if (!_state && !active) {
        return NO;
    }
    if (_state && [_state[@"active"] boolValue] == active && [_snapshot isEqual:snapshot]) {
        return NO;
    }
    [self anchors];
    NSData *combined = active ? Overlay(_baseline, snapshot) : nil;
    NSDictionary *original = _state ? _state[@"original"] : _target;
    NSUInteger slot = _state ? 1 - [_state[@"slot"] unsignedIntegerValue] : 0;
    NSMutableDictionary *next = [@{
        @"version" : @1,
        @"revision" : NSUUID.UUID.UUIDString,
        @"active" : @(active),
        @"domainCount" : @(count),
        @"slot" : @(slot),
        @"snapshotHash" : Digest(snapshot),
        @"baselineHash" : Digest(_baseline),
        @"original" : original,
        @"system" : _system
    } mutableCopy];
    /* Prepare data, never overwrite the slot referenced by the committed state. */
    AtomicData(_stateFD, Slot(next), snapshot, _owner, 0600);
    if (!_state) {
        AtomicData(_stateFD, @"original.pending", _baseline, _owner, 0400);
    }
    Fault(@"after-prepared");
    NSString *tmp = @"";
    if (active) {
        tmp = WriteTemp(_etcFD, combined, 0644, _owner);
    } else if ([original[@"kind"] isEqual:@"symlink"]) {
        tmp = NewTemp();
        if (symlinkat([original[@"text"] fileSystemRepresentation], _etcFD, tmp.fileSystemRepresentation)) {
            Fail(@"write-failed");
        }
        /* Verify the restored link resolves to the exact fixed raw system inode. */
        int f = openat(_etcFD, tmp.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
        struct stat s;
        BOOL valid = f >= 0 && fstat(f, &s) == 0 && S_ISREG(s.st_mode) && s.st_uid == _owner &&
                     (uint64_t)s.st_dev == [_system[@"dev"] unsignedLongLongValue] &&
                     (uint64_t)s.st_ino == [_system[@"ino"] unsignedLongLongValue];
        if (f >= 0) {
            close(f);
        }
        if (!valid) {
            Fail(@"mirror-conflict");
        }
    }
    next[@"target"] = tmp.length ? Fingerprint(_etcFD, tmp, _owner, MaxHosts) : @{@"kind" : @"missing"};
    SyncDir(_etcFD);
    Fault(@"before-journal");
    if (![Fingerprint(_etcFD, @"hosts", _owner, MaxHosts) isEqual:_target] ||
        ![Fingerprint(_rawFD, _rawName, _owner, MaxBaseline) isEqual:_system]) {
        Fail(@"target-conflict");
    }
    NSDictionary *journal = @{
        @"version" : @1,
        @"before" : _state ?: (id)NSNull.null,
        @"after" : next,
        @"beforeTarget" : _target,
        @"afterTarget" : next[@"target"],
        @"stagedName" : tmp
    };
    AtomicData(_stateFD, @"journal.json", JSON(journal), _owner, 0600);
    Fault(@"after-journal");
    [self recover];
    [self load];
    return YES;
}
@end

/* Production paths are supplied only by main; never taken from JSON. Holding
 * no descriptor between requests prevents stale observations / stale flocks. */
@interface QHFileManager ()
@property(nonatomic, copy) NSString *mappedRoot, *rawSystem;
@property(nonatomic) uid_t expectedOwner;
@end
@implementation QHFileManager
- (instancetype)initWithRoot:(NSString *)mappedJbroot
                 systemHosts:(NSString *)rawSystemPath
               expectedOwner:(uid_t)uid {
    if ((self = [super init])) {
        _mappedRoot = [mappedJbroot copy];
        _rawSystem = [rawSystemPath copy];
        _expectedOwner = uid;
    }
    return self;
}
- (NSDictionary *)handleCommand:(NSString *)command request:(NSDictionary *)request {
    QHTransaction *t = nil;
    NSDictionary *observed = nil;
    @try {
        if (![@[ @"status", @"apply", @"enable", @"disable", @"reload", @"restore-for-uninstall" ]
                containsObject:command ?: @""]) {
            Fail(@"invalid-command");
        }
        BOOL status = [command isEqual:@"status"], uninstall = [command isEqual:@"restore-for-uninstall"];
        BOOL apply = [command isEqual:@"apply"];
        NSArray *keys = (status || uninstall)
                            ? @[]
                            : (apply ? @[ @"expectedRevision", @"hostsBase64", @"domainCount" ]
                                     : @[ @"expectedRevision" ]);
        if (!Keys(request, keys)) {
            Fail(@"invalid-request");
        }
        if (!status && !uninstall &&
            (!String(request[@"expectedRevision"], 64) || ![request[@"expectedRevision"] length])) {
            Fail(@"invalid-request");
        }
#ifndef QH_TESTING
        if (uninstall && getuid() != 0) {
            Fail(@"permission-denied");
        }
#endif
        NSData *candidate = nil;
        NSUInteger count = 0;
        if (apply) {
            if (!String(request[@"hostsBase64"], 4 * ((MaxHosts + 2) / 3)) ||
                !Integer(request[@"domainCount"], QHMaximumDomains)) {
                Fail(@"invalid-request");
            }
            candidate = [[NSData alloc] initWithBase64EncodedString:request[@"hostsBase64"] options:0];
            if (!candidate || candidate.length > MaxHosts ||
                ![[candidate base64EncodedStringWithOptions:0] isEqual:request[@"hostsBase64"]]) {
                Fail(@"invalid-base64");
            }
            /* Do not use the 16MiB source parser for a 32MiB compiled document. */
            if (!QHValidateCompiledHosts(candidate, &count, NULL)) {
                Fail(@"invalid-hosts");
            }
            if (count != [request[@"domainCount"] unsignedIntegerValue]) {
                Fail(@"domain-count-mismatch");
            }
        }
        t = [[QHTransaction alloc] initWithRoot:_mappedRoot system:_rawSystem owner:_expectedOwner];
        [t openState:NO];
        [t load];
        observed = [t response];
        if (status) {
            return observed;
        }
        if (!uninstall && ![request[@"expectedRevision"] isEqual:observed[@"revision"]]) {
            Fail(@"revision-conflict");
        }
        if ([command isEqual:@"reload"]) {
            return observed; // only main can request DNS restart
        }
        BOOL active = apply || [command isEqual:@"enable"];
        if (active && !apply && !t.state) {
            Fail(@"no-snapshot");
        }
        if (!apply) {
            candidate = t.snapshot ?: NSData.data;
            count = [t.state[@"domainCount"] unsignedIntegerValue];
        }
        if ((!t.state && !active) ||
            (t.state && [t.state[@"active"] boolValue] == active && [t.snapshot isEqual:candidate])) {
            return observed;
        }
        if (active) {
            Overlay(t.baseline, candidate); // reject overlap/size BEFORE any state creation
        }
        if (t.lockFD < 0) {
            /* First takeover: both optimistic CAS and post-lock CAS are needed.
             * A competing helper may create state between these observations. */
            [t openState:YES];
            [t load];
            observed = [t response];
            if (!uninstall && ![request[@"expectedRevision"] isEqual:observed[@"revision"]]) {
                Fail(@"revision-conflict");
            }
        }
        observed = nil; // a failure during commit cannot claim the old state is current
        [t transact:candidate active:active count:count];
        return [t response];
    } @catch (NSException *exception) {
        /* Never emit exception descriptions, arbitrary metadata, or host paths. */
        NSString *code = [exception.name isEqual:FailureName] ? exception.reason : @"internal-error";
        NSSet *requestErrors = [NSSet setWithArray:@[
            @"invalid-command", @"invalid-request", @"invalid-base64", @"invalid-hosts",
            @"domain-count-mismatch", @"permission-denied", @"revision-conflict", @"no-snapshot",
            @"baseline-conflict", @"size-limit", @"busy"
        ]];
        NSMutableDictionary *result = observed ? [observed mutableCopy] : [@{
            @"state" : [requestErrors containsObject:code] || [code isEqual:@"internal-error"] ? @"error"
                                                                                               : @"conflict",
            @"revision" : @"",
            @"domainCount" : @0,
            @"hasBaseline" : @NO
        } mutableCopy];
        struct stat s;
        if (t && t.stateFD >= 0 && fstatat(t.stateFD, "original.bin", &s, AT_SYMLINK_NOFOLLOW) == 0 &&
            S_ISREG(s.st_mode)) {
            result[@"hasBaseline"] = @YES;
        }
        result[@"ok"] = @NO;
        result[@"errorCode"] = code ?: @"internal-error";
        result[@"changed"] = @(t && t.actualChanged);
        result[@"reloadRequested"] = @NO;
        result[@"reloadPending"] = @(t && t.recovered);
        return result;
    }
}
@end
