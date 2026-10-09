#import <Foundation/Foundation.h>
#import "QHFileManager.h"
#import "QHRootlessPaths.h"
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdlib.h>
#include <limits.h>
#include <errno.h>
#include <stdint.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#if !defined(QH_TESTING) || !QH_TESTING
#error RootlessFileManagerTests requires QH_TESTING=1.
#endif

static NSUInteger checks;
static void Check(BOOL yes, NSString *name) {
    checks++;
    if (!yes) {
        NSLog(@"FAIL: %@", name);
        exit(1);
    }
}
/* Private test seam implemented by QHFileManager.m only under QH_TESTING. */
extern void QHSetDirectoryMutationHook(NSString *point, void (^mutation)(void));

static NSData *CompiledOne(void) {
    /* Same canonical compiled Hosts pair accepted by QHValidateCompiledHosts. */
    return [@"0.0.0.0 ads.example\n::1 ads.example\n" dataUsingEncoding:NSUTF8StringEncoding];
}
static NSData *CompiledTwo(void) {
    return [@"0.0.0.0 tracker.example\n::1 tracker.example\n" dataUsingEncoding:NSUTF8StringEncoding];
}
static NSData *Append(NSData *left, NSData *right) {
    NSMutableData *result = [left mutableCopy];
    [result appendData:right];
    return result;
}
static NSData *LinkData(NSString *path) {
    char text[PATH_MAX];
    ssize_t length = readlink(path.fileSystemRepresentation, text, sizeof(text));
    if (length <= 0 || length >= (ssize_t)sizeof(text)) return nil;
    return [NSData dataWithBytes:text length:(NSUInteger)length];
}
static NSDictionary *CapturePath(NSString *path) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return nil;
    NSMutableDictionary *entry = [@{
        @"dev" : @((uint64_t)st.st_dev), @"ino" : @((uint64_t)st.st_ino),
        @"mode" : @((uint32_t)st.st_mode), @"uid" : @(st.st_uid), @"gid" : @(st.st_gid),
        @"nlink" : @((uint64_t)st.st_nlink), @"size" : @((int64_t)st.st_size),
        @"mtime" : @((int64_t)st.st_mtimespec.tv_sec), @"mtimeNS" : @(st.st_mtimespec.tv_nsec),
        @"ctime" : @((int64_t)st.st_ctimespec.tv_sec), @"ctimeNS" : @(st.st_ctimespec.tv_nsec)
    } mutableCopy];
    if (S_ISREG(st.st_mode)) {
        NSData *bytes = [NSData dataWithContentsOfFile:path];
        Check(bytes != nil, [@"read fixture file: " stringByAppendingString:path.lastPathComponent]);
        entry[@"bytes"] = bytes;
    } else if (S_ISLNK(st.st_mode)) {
        NSData *text = LinkData(path);
        Check(text != nil, [@"read fixture symlink: " stringByAppendingString:path.lastPathComponent]);
        entry[@"link"] = text;
    } else if (S_ISDIR(st.st_mode)) {
        NSArray *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:NULL];
        Check(names != nil, [@"list fixture directory: " stringByAppendingString:path.lastPathComponent]);
        NSMutableDictionary *children = [NSMutableDictionary dictionary];
        for (NSString *name in names) {
            NSDictionary *child = CapturePath([path stringByAppendingPathComponent:name]);
            Check(child != nil, [@"capture fixture entry: " stringByAppendingString:name]);
            children[name] = child;
        }
        entry[@"children"] = children;
    }
    return entry;
}

@interface QHRootlessFixture : NSObject
@property(nonatomic, copy) NSString *base, *root, *raw, *target, *alias, *state, *detachedEtc;
@property(nonatomic, strong) NSData *rawBytes, *originalLink;
@property(nonatomic) ino_t rawInode;
@property(nonatomic, strong) QHFileManager *manager;
- (void)checkRaw:(NSString *)context;
@end
@implementation QHRootlessFixture
- (instancetype)init {
    if ((self = [super init])) {
        char pattern[] = "/tmp/qh-rootless-native-XXXXXX";
        char *created = mkdtemp(pattern);
        Check(created != NULL, @"isolated temp directory");
        char canonical[PATH_MAX];
        Check(realpath(created, canonical) != NULL, @"canonical test directory");
        _base = [NSString stringWithUTF8String:canonical];
        NSFileManager *files = NSFileManager.defaultManager;
        for (NSString *relative in @[
                 @"root", @"root/etc", @"root/var", @"root/var/lib", @"raw", @"alias"
             ]) {
            NSString *path = [_base stringByAppendingPathComponent:relative];
            Check([files createDirectoryAtPath:path withIntermediateDirectories:YES
                                     attributes:@{NSFilePosixPermissions : @0755} error:NULL],
                  @"create protected fixture directory");
            Check(chmod(path.fileSystemRepresentation, 0755) == 0, @"fix protected fixture mode");
        }
        Check(chmod(_base.fileSystemRepresentation, 0755) == 0, @"fix fixture namespace mode");
        _root = [_base stringByAppendingPathComponent:@"root"];
        _raw = [_base stringByAppendingPathComponent:@"raw/hosts"];
        _target = [_root stringByAppendingPathComponent:@"etc/hosts"];
        _alias = [_base stringByAppendingPathComponent:@"alias/jb"];
        _state = [_root stringByAppendingPathComponent:@"var/lib/quiethosts"];
        _rawBytes = [@"127.0.0.1 localhost\n::1 localhost\n" dataUsingEncoding:NSUTF8StringEncoding];
        Check([_rawBytes writeToFile:_raw atomically:YES], @"write isolated raw Hosts fixture");
        struct stat rawStat;
        Check(lstat(_raw.fileSystemRepresentation, &rawStat) == 0, @"stat raw fixture");
        _rawInode = rawStat.st_ino;
        _originalLink = [_raw dataUsingEncoding:NSUTF8StringEncoding];
        Check(symlink("/root", _alias.fileSystemRepresentation) == 0, @"fixed dependency alias");
        Check(symlink(_raw.fileSystemRepresentation, _target.fileSystemRepresentation) == 0,
              @"original system mirror fixture");
        QHRootlessTestingSetNamespace(_base);
        _manager = [[QHFileManager alloc] initWithRoot:_root systemHosts:_raw expectedOwner:getuid()];
    }
    return self;
}
- (void)dealloc {
    QHSetDirectoryMutationHook(nil, nil);
    if (_base) [NSFileManager.defaultManager removeItemAtPath:_base error:NULL];
}
- (void)checkRaw:(NSString *)context {
    struct stat st;
    NSString *inodeLabel = [context stringByAppendingString:@": raw system inode unchanged"];
    NSString *bytesLabel = [context stringByAppendingString:@": raw system bytes unchanged"];
    Check(lstat(_raw.fileSystemRepresentation, &st) == 0 && st.st_ino == _rawInode, inodeLabel);
    Check([[NSData dataWithContentsOfFile:_raw] isEqual:_rawBytes], bytesLabel);
}
@end

static NSDictionary *Status(QHFileManager *manager) {
    return [manager handleCommand:@"status" request:@{}];
}
static NSDictionary *ApplyRequest(QHRootlessFixture *fixture, NSString *revision, NSData *hosts) {
    return [fixture.manager handleCommand:@"apply" request:@{
        @"expectedRevision" : revision,
        @"hostsBase64" : [hosts base64EncodedStringWithOptions:0],
        @"domainCount" : @1
    }];
}
static NSDictionary *Request(QHRootlessFixture *fixture, NSString *command, NSData *hosts) {
    NSDictionary *status = Status(fixture.manager);
    Check([status[@"ok"] boolValue], [@"request preflight: " stringByAppendingString:status.description]);
    if ([command isEqual:@"apply"]) return ApplyRequest(fixture, status[@"revision"], hosts);
    return [fixture.manager handleCommand:command request:@{@"expectedRevision" : status[@"revision"]}];
}
static void TestEnableRestoreAndRevisionCAS(void) {
    QHRootlessFixture *fixture = [QHRootlessFixture new];
    NSDictionary *initial = Status(fixture.manager);
    Check([initial[@"ok"] boolValue] && [initial[@"state"] isEqual:@"unmanaged"],
          @"fresh rootless status is unmanaged");
    NSData *linkBefore = LinkData(fixture.target);
    Check([linkBefore isEqual:fixture.originalLink], @"capture exact original link bytes");
    NSData *snapshot = CompiledOne();
    NSData *expectedActive = Append(fixture.rawBytes, snapshot);
    NSDictionary *applied = ApplyRequest(fixture, initial[@"revision"], snapshot);
    Check([applied[@"ok"] boolValue] && [applied[@"state"] isEqual:@"active"] &&
              [applied[@"changed"] boolValue],
          @"rootless apply commits canonical compiled snapshot");
    Check([[NSData dataWithContentsOfFile:fixture.target] isEqual:expectedActive],
          @"apply target is exact baseline plus compiled snapshot");
    NSString *backup = [fixture.state stringByAppendingPathComponent:@"original.bin"];
    Check([[NSData dataWithContentsOfFile:backup] isEqual:fixture.rawBytes],
          @"apply preserves exact original snapshot");
    [fixture checkRaw:@"after apply"];

    NSDictionary *targetBeforeStale = CapturePath(fixture.target);
    NSDictionary *stateBeforeStale = CapturePath(fixture.state);
    NSDictionary *stale = ApplyRequest(fixture, initial[@"revision"], CompiledTwo());
    Check(![stale[@"ok"] boolValue] && ![stale[@"changed"] boolValue] &&
              [stale[@"errorCode"] isEqual:@"revision-conflict"],
          @"expired expectedRevision is refused");
    Check([targetBeforeStale isEqual:CapturePath(fixture.target)],
          @"stale expectedRevision leaves target entry unchanged");
    Check([stateBeforeStale isEqual:CapturePath(fixture.state)],
          @"stale expectedRevision leaves transaction artifacts unchanged");
    [fixture checkRaw:@"after stale revision"];

    NSDictionary *disabled = Request(fixture, @"disable", nil);
    Check([disabled[@"ok"] boolValue] && [disabled[@"state"] isEqual:@"inactive"] &&
              [disabled[@"changed"] boolValue],
          @"disable restores rootless mirror");
    Check([LinkData(fixture.target) isEqual:linkBefore], @"disable restores exact original link bytes");
    [fixture checkRaw:@"after disable"];

    NSDictionary *enabled = Request(fixture, @"enable", nil);
    Check([enabled[@"ok"] boolValue] && [enabled[@"state"] isEqual:@"active"] &&
              [enabled[@"changed"] boolValue],
          @"enable succeeds from disabled state");
    Check([[NSData dataWithContentsOfFile:fixture.target] isEqual:expectedActive],
          @"disabled-to-enabled restores exact saved snapshot");
    [fixture checkRaw:@"after re-enable"];

    NSDictionary *uninstalled = [fixture.manager handleCommand:@"restore-for-uninstall" request:@{}];
    Check([uninstalled[@"ok"] boolValue] && [uninstalled[@"state"] isEqual:@"inactive"] &&
              [uninstalled[@"changed"] boolValue],
          @"uninstall restore reverts active rootless target");
    Check([LinkData(fixture.target) isEqual:linkBefore],
          @"uninstall restore preserves exact original symlink text");
    Check([[NSData dataWithContentsOfFile:backup] isEqual:fixture.rawBytes],
          @"uninstall restore retains exact baseline backup");
    [fixture checkRaw:@"after uninstall restore"];
}

static void Crash(QHRootlessFixture *fixture, NSDictionary *request, NSString *point) {
    pid_t child = fork();
    Check(child >= 0, @"fork transaction crash fixture");
    if (!child) {
        signal(SIGALRM, SIG_DFL);
        alarm(30);
        QHSetTransactionFault(point);
        @autoreleasepool {
            [fixture.manager handleCommand:@"apply" request:request];
        }
        _exit(87);
    }
    int status = 0;
    pid_t waited;
    do {
        waited = waitpid(child, &status, 0);
    } while (waited < 0 && errno == EINTR);
    Check(waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 86,
          [@"transaction fault reached: " stringByAppendingString:point]);
}
static void TestCrashRecovery(NSString *point) {
    QHRootlessFixture *fixture = [QHRootlessFixture new];
    NSDictionary *initial = Status(fixture.manager);
    Check([initial[@"ok"] boolValue], @"crash fixture starts in proved namespace");
    NSDictionary *request = @{
        @"expectedRevision" : initial[@"revision"],
        @"hostsBase64" : [CompiledOne() base64EncodedStringWithOptions:0],
        @"domainCount" : @1
    };
    Crash(fixture, request, point);
    NSDictionary *recovered = Status(fixture.manager);
    Check([recovered[@"ok"] boolValue] && [recovered[@"state"] isEqual:@"active"] &&
              [recovered[@"domainCount"] unsignedIntegerValue] == 1,
          [@"status recovers transaction at " stringByAppendingString:point]);
    Check([recovered[@"reloadPending"] boolValue], @"replayed transaction records pending reload");
    BOOL hadRenamedTarget = [point isEqual:@"after-rename-before-sync"];
    Check([recovered[@"changed"] boolValue] == !hadRenamedTarget,
          @"recovery reports whether target rename remained");
    NSString *journal = [fixture.state stringByAppendingPathComponent:@"journal.json"];
    Check(![NSFileManager.defaultManager fileExistsAtPath:journal], @"successful recovery clears journal");
    Check([[NSData dataWithContentsOfFile:fixture.target] isEqual:Append(fixture.rawBytes, CompiledOne())],
          @"recovery commits exact original snapshot plus compiled rules");
    Check([[NSData dataWithContentsOfFile:[fixture.state stringByAppendingPathComponent:@"original.bin"]]
              isEqual:fixture.rawBytes],
          @"recovery retains exact original backup artifact");
    [fixture checkRaw:@"after crash recovery"];
}

static void MutateAlias(QHRootlessFixture *fixture) {
    Check(unlink(fixture.alias.fileSystemRepresentation) == 0, @"remove fixture dependency alias");
    Check(symlink("/wrong-root", fixture.alias.fileSystemRepresentation) == 0,
          @"replace fixture dependency alias");
}
static void MutateProtectedEtc(QHRootlessFixture *fixture) {
    fixture.detachedEtc = [fixture.base stringByAppendingPathComponent:@"detached-etc"];
    Check(rename([fixture.root stringByAppendingPathComponent:@"etc"].fileSystemRepresentation,
                 fixture.detachedEtc.fileSystemRepresentation) == 0,
          @"detach protected etc directory");
    NSString *replacement = [fixture.root stringByAppendingPathComponent:@"etc"];
    Check(mkdir(replacement.fileSystemRepresentation, 0755) == 0, @"replace protected etc directory");
}
static void TestPrewriteMutation(BOOL protectedDirectory) {
    QHRootlessFixture *fixture = [QHRootlessFixture new];
    NSDictionary *initial = Status(fixture.manager);
    Check([initial[@"ok"] boolValue], @"prewrite race fixture starts in proved namespace");
    NSDictionary *request = @{
        @"expectedRevision" : initial[@"revision"],
        @"hostsBase64" : [CompiledOne() base64EncodedStringWithOptions:0],
        @"domainCount" : @1
    };
    __block NSDictionary *atMutation = nil;
    QHSetDirectoryMutationHook(@"commit-target", ^{
        if (protectedDirectory) MutateProtectedEtc(fixture);
        else MutateAlias(fixture);
        atMutation = CapturePath(fixture.base);
    });
    NSDictionary *result = [fixture.manager handleCommand:@"apply" request:request];
    QHSetDirectoryMutationHook(nil, nil);
    Check(atMutation != nil, @"test substitutes namespace just before target commit");
    NSString *expectedError = protectedDirectory ? @"rootless-namespace-changed"
                                                 : @"rootless-dependency-root-conflict";
    NSString *refusalLabel = protectedDirectory
                                 ? @"protected directory replacement is refused before target commit"
                                 : @"rootless dependency alias substitution rejected before target commit";
    Check(![result[@"ok"] boolValue] && ![result[@"changed"] boolValue] &&
              [result[@"errorCode"] isEqual:expectedError],
          refusalLabel);
    Check([atMutation isEqual:CapturePath(fixture.base)],
          @"prewrite refusal performs no write or cleanup after substitution");
    NSString *journalPath = [fixture.state stringByAppendingPathComponent:@"journal.json"];
    NSData *journalBytes = [NSData dataWithContentsOfFile:journalPath];
    NSDictionary *journal = journalBytes
                               ? [NSJSONSerialization JSONObjectWithData:journalBytes options:0 error:NULL]
                               : nil;
    Check([journal isKindOfClass:NSDictionary.class] && [journal[@"version"] isEqual:@1],
          @"prewrite refusal retains durable transaction journal");
    NSString *untouchedTarget = protectedDirectory
                                    ? [fixture.detachedEtc stringByAppendingPathComponent:@"hosts"]
                                    : fixture.target;
    Check([LinkData(untouchedTarget) isEqual:fixture.originalLink],
          @"prewrite refusal retains original target link bytes");
    [fixture checkRaw:@"after prewrite namespace refusal"];
}

static void TestExistingNamespaceRefusals(void) {
    QHRootlessFixture *fixture = [QHRootlessFixture new];
    NSDictionary *status = Status(fixture.manager);
    Check([status[@"ok"] boolValue], @"rootless status");
    NSDictionary *applied = ApplyRequest(fixture, status[@"revision"], CompiledOne());
    Check([applied[@"ok"] boolValue], @"apply through proved namespace");
    Check([[NSData dataWithContentsOfFile:fixture.raw] isEqual:fixture.rawBytes],
          @"raw unchanged after apply");
    NSDictionary *disabled = Request(fixture, @"disable", nil);
    Check([disabled[@"ok"] boolValue], @"disable restores mirror");
    Check([LinkData(fixture.target) isEqual:fixture.originalLink], @"original link bytes restored");
    [fixture checkRaw:@"after existing restore assertion"];
    MutateAlias(fixture);
    NSDictionary *bad = Status(fixture.manager);
    Check(![bad[@"ok"] boolValue], @"changed dependency alias rejected");
    [fixture checkRaw:@"after rejected alias status"];
    Check(unlink(fixture.alias.fileSystemRepresentation) == 0 &&
              symlink("/root", fixture.alias.fileSystemRepresentation) == 0,
          @"restore fixture dependency alias");
    NSString *lib = [fixture.root stringByAppendingPathComponent:@"var/lib"];
    Check(chmod(lib.fileSystemRepresentation, 0777) == 0, @"make protected state ancestor writable");
    bad = Status(fixture.manager);
    Check(![bad[@"ok"] boolValue], @"writable state ancestor rejected");
    Check(chmod(lib.fileSystemRepresentation, 0755) == 0, @"restore protected state ancestor mode");
    Check([Status(fixture.manager)[@"ok"] boolValue], @"correct namespace works again");
    [fixture checkRaw:@"after namespace preflight refusals"];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--routing-guard-mutation") == 0) {
            TestPrewriteMutation(NO);
            QHRootlessTestingSetNamespace(nil);
            printf("Rootless routing mutation probe: %lu checks PASS\n", (unsigned long)checks);
            return 0;
        }
        Check(argc == 1, @"no unexpected test arguments");
        TestEnableRestoreAndRevisionCAS();
        TestCrashRecovery(@"after-journal");
        TestCrashRecovery(@"after-rename-before-sync");
        TestPrewriteMutation(NO);
        TestPrewriteMutation(YES);
        TestExistingNamespaceRefusals();
        QHRootlessTestingSetNamespace(nil);
        printf("Rootless Foundation transaction: %lu checks PASS\n", (unsigned long)checks);
    }
    return 0;
}
