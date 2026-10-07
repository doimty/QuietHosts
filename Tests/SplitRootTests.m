#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import "../Helper/QHFileManager.h"
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
#error SplitRootTests require QH_TESTING=1 and isolated fixtures.
#endif

/* This suite calls only QHFileManager's Foundation core. It never invokes the
 * native helper executable, filesystem paths outside its own fixture, or DNS. */
static NSUInteger SplitRootFailures;
static NSUInteger SplitRootChecks;
static void SRCheck(BOOL condition, NSString *label) {
    SplitRootChecks++;
    if (!condition) {
        SplitRootFailures++;
        NSLog(@"SplitRootTests FAIL: %@", label);
    }
}
static void SRRequireAt(BOOL condition, int line, const char *expression) {
    if (!condition) {
        fprintf(stderr, "SplitRoot fixture failed line %d errno=%d: %s\n", line, errno, expression);
        abort();
    }
}
#define SRRequire(...) SRRequireAt((__VA_ARGS__), __LINE__, #__VA_ARGS__)
static NSData *SRText(NSString *text) {
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}
static NSString *SRSHA(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < sizeof(digest); i++) {
        [out appendFormat:@"%02x", digest[i]];
    }
    return out;
}
static void SRSetOwner(NSString *path, uid_t uid, gid_t gid) {
    SRRequire(chown(path.fileSystemRepresentation, uid, gid) == 0);
}
static void SRDirectory(NSString *path, mode_t mode, uid_t uid, gid_t gid) {
    SRRequire(mkdir(path.fileSystemRepresentation, mode) == 0);
    SRSetOwner(path, uid, gid);
    SRRequire(chmod(path.fileSystemRepresentation, mode) == 0);
}
static void SRWrite(NSString *path, NSData *data, mode_t mode, uid_t uid, gid_t gid) {
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    SRRequire(fd >= 0);
    const unsigned char *bytes = data.bytes;
    NSUInteger left = data.length;
    while (left) {
        ssize_t n = write(fd, bytes, left);
        if (n < 0 && errno == EINTR) {
            continue;
        }
        SRRequire(n > 0);
        bytes += n;
        left -= (NSUInteger)n;
    }
    SRRequire(fchown(fd, uid, gid) == 0);
    SRRequire(fchmod(fd, mode) == 0);
    SRRequire(close(fd) == 0);
}
static NSDictionary *SRCapture(NSString *directory) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL];
    SRRequire(entries != nil);
    for (NSString *name in entries) {
        NSString *path = [directory stringByAppendingPathComponent:name];
        struct stat st;
        SRRequire(lstat(path.fileSystemRepresentation, &st) == 0);
        NSMutableDictionary *item = [@{
            @"mode" : @(st.st_mode),
            @"uid" : @(st.st_uid),
            @"gid" : @(st.st_gid),
            @"inode" : @(st.st_ino),
            @"nlink" : @(st.st_nlink)
        } mutableCopy];
        if (S_ISREG(st.st_mode)) {
            NSData *bytes = [NSData dataWithContentsOfFile:path];
            SRRequire(bytes != nil);
            item[@"sha"] = SRSHA(bytes);
        } else if (S_ISLNK(st.st_mode)) {
            char text[PATH_MAX + 1];
            ssize_t n = readlink(path.fileSystemRepresentation, text, PATH_MAX);
            SRRequire(n >= 0 && n < PATH_MAX);
            text[n] = 0;
            item[@"link"] = [NSString stringWithUTF8String:text];
        } else if (S_ISDIR(st.st_mode)) {
            item[@"children"] = SRCapture(path);
        }
        result[name] = item;
    }
    return result;
}

/* About 210 bytes, deliberately different from the raw system fixture. The
 * active-map grammar permits only these three conventional mappings and
 * comments/blank lines. */
static NSString *const SRDefaultHosts =
    @"# Default hosts fixture: comments, spacing, and this sentence must be saved byte-for-byte; it is not "
    @"the raw system file.\n"
     "# This second comment makes the original a realistic roughly-200-byte file.\n"
     "\n"
     "127.0.0.1 localhost\n"
     "255.255.255.255 broadcasthost\n"
     "::1 localhost\n";
static NSString *const SRRawHosts =
    @"# Raw system baseline is intentionally distinct from the mapped entry.\n"
     "127.0.0.1 localhost\n"
     "::1 localhost\n"
     "192.0.2.19 raw-only.example\n";
static NSData *SRBlocks(void) {
    return SRText(@"0.0.0.0 ads.example\n::1 ads.example\n");
}
static NSString *const SRBrand = @".jbroot-0123456789ABCDEF";

@interface QHSplitRootFixture : NSObject
@property(nonatomic, copy) NSString *directory;
@property(nonatomic, copy) NSString *root;
@property(nonatomic, copy) NSString *etc;
@property(nonatomic, copy) NSString *privateDirectory;
@property(nonatomic, copy) NSString *raw;
@property(nonatomic, copy) NSString *pairedParent;
@property(nonatomic, copy) NSString *pairedRoot;
@property(nonatomic, copy) NSString *pairedVar;
@property(nonatomic, copy) NSString *pairedLib;
@property(nonatomic, copy) NSString *state;
@property(nonatomic, copy) NSString *target;
@property(nonatomic, copy) NSString *rawHash;
@property(nonatomic) uid_t expectedOwner;
@property(nonatomic) gid_t expectedGroup;
@property(nonatomic) BOOL mixedUID;
@property(nonatomic, strong) QHFileManager *manager;
- (instancetype)initWithMixedUID:(BOOL)mixedUID;
- (NSDictionary *)status;
- (NSDictionary *)apply:(BOOL)consent revision:(NSString *)revision;
- (NSDictionary *)command:(NSString *)command;
- (NSDictionary *)applyRequestWithConsent:(id)consent
                                 revision:(NSString *)revision
                                    extra:(NSDictionary *)extra;
- (void)checkRaw;
@end

@implementation QHSplitRootFixture
- (instancetype)initWithMixedUID:(BOOL)mixedUID {
    if ((self = [super init])) {
        _mixedUID = mixedUID;
        _expectedOwner = mixedUID ? 0 : getuid();
        _expectedGroup = mixedUID ? 0 : getgid();
        NSString *home = NSHomeDirectory();
        char canonicalHome[PATH_MAX];
        SRRequire(realpath(home.fileSystemRepresentation, canonicalHome) != NULL);
        NSString *template = [[NSString stringWithUTF8String:canonicalHome]
            stringByAppendingPathComponent:@".qh-splitroot-fixture-XXXXXX"];
        char *buffer = strdup(template.fileSystemRepresentation);
        SRRequire(buffer != NULL && mkdtemp(buffer) != NULL);
        char canonicalFixture[PATH_MAX];
        SRRequire(realpath(buffer, canonicalFixture) != NULL);
        _directory = [NSString stringWithUTF8String:canonicalFixture];
        free(buffer);
        SRRequire(chmod(_directory.fileSystemRepresentation, 0700) == 0);

        _root = [[[_directory stringByAppendingPathComponent:@"primary"]
            stringByAppendingPathComponent:SRBrand] copy];
        NSString *primaryStore = [_directory stringByAppendingPathComponent:@"primary"];
        _pairedParent = [_directory stringByAppendingPathComponent:@"paired-parent"];
        NSString *rawDirectory = [_directory stringByAppendingPathComponent:@"raw"];
        SRDirectory(primaryStore, 0700, getuid(), getgid());
        SRDirectory(_pairedParent, 0700, getuid(), getgid());
        SRDirectory(rawDirectory, 0755, _expectedOwner, _expectedGroup);

        uid_t mobileUID = mixedUID ? (uid_t)501 : _expectedOwner;
        gid_t mobileGID = mixedUID ? (gid_t)501 : _expectedGroup;
        SRDirectory(_root, 0755, mobileUID, mobileGID);
        _etc = [_root stringByAppendingPathComponent:@"etc"];
        _privateDirectory = [_root stringByAppendingPathComponent:@"private"];
        SRDirectory(_etc, 0755, _expectedOwner, _expectedGroup);
        SRDirectory(_privateDirectory, 0755, _expectedOwner, _expectedGroup);

        _pairedRoot = [_pairedParent stringByAppendingPathComponent:SRBrand];
        SRDirectory(_pairedRoot, 0755, _expectedOwner, _expectedGroup);
        _pairedVar = [_pairedRoot stringByAppendingPathComponent:@"var"];
        SRDirectory(_pairedVar, 0755, mobileUID, mobileGID);
        _pairedLib = [_pairedVar stringByAppendingPathComponent:@"lib"];
        SRDirectory(_pairedLib, 0755, _expectedOwner, _expectedGroup);

        NSString *privateVar = [_privateDirectory stringByAppendingPathComponent:@"var"];
        SRRequire(symlink(_pairedVar.fileSystemRepresentation, privateVar.fileSystemRepresentation) == 0);
        SRRequire(symlink(@"private/var/".fileSystemRepresentation,
                          [_root stringByAppendingPathComponent:@"var"].fileSystemRepresentation) == 0);
        SRRequire(symlink(_root.fileSystemRepresentation,
                          [_pairedRoot stringByAppendingPathComponent:@".jbroot"].fileSystemRepresentation) ==
                  0);

        _raw = [rawDirectory stringByAppendingPathComponent:@"hosts"];
        SRWrite(_raw, SRText(SRRawHosts), 0644, _expectedOwner, _expectedGroup);
        _rawHash = SRSHA(SRText(SRRawHosts));
        _target = [_etc stringByAppendingPathComponent:@"hosts"];
        SRWrite(_target, SRText(SRDefaultHosts), 0644, _expectedOwner, _expectedGroup);
        _state = [_pairedLib stringByAppendingPathComponent:@"quiethosts"];
        _manager = [[QHFileManager alloc] initWithRoot:_root
                                           systemHosts:_raw
                                         expectedOwner:_expectedOwner
                                        pairedDataRoot:_pairedVar];
    }
    return self;
}
- (void)dealloc {
    if (_directory.length) {
        /* The fixture root is unique, created by this suite, and is the only
         * tree this test removes, including mixed-UID child fixtures. */
        [NSFileManager.defaultManager removeItemAtPath:_directory error:NULL];
    }
}
- (NSDictionary *)status {
    return [_manager handleCommand:@"status" request:@{}];
}
- (NSDictionary *)applyRequestWithConsent:(id)consent
                                 revision:(NSString *)revision
                                    extra:(NSDictionary *)extra {
    NSMutableDictionary *request = [@{
        @"expectedRevision" : revision ?: @"",
        @"hostsBase64" : [SRBlocks() base64EncodedStringWithOptions:0],
        @"domainCount" : @1
    } mutableCopy];
    if (consent) {
        request[@"adoptExistingHosts"] = consent;
    }
    [request addEntriesFromDictionary:extra ?: @{}];
    return [_manager handleCommand:@"apply" request:request];
}
- (NSDictionary *)apply:(BOOL)consent revision:(NSString *)revision {
    return [self applyRequestWithConsent:@(consent) revision:revision extra:nil];
}
- (NSDictionary *)command:(NSString *)command {
    return [_manager handleCommand:command request:@{@"expectedRevision" : self.status[@"revision"] ?: @""}];
}
- (void)checkRaw {
    NSData *raw = [NSData dataWithContentsOfFile:_raw];
    SRCheck(raw != nil && [SRSHA(raw) isEqual:_rawHash], @"raw system hosts exact hash unchanged");
}
@end

static BOOL SRTargetBytes(QHSplitRootFixture *f, NSData *expected) {
    struct stat st;
    NSData *actual = [NSData dataWithContentsOfFile:f.target];
    return lstat(f.target.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode) && actual &&
           [actual isEqual:expected];
}
static void SRCheckNoState(QHSplitRootFixture *f, NSString *label) {
    SRCheck(lstat(f.state.fileSystemRepresentation, &(struct stat){0}) < 0 && errno == ENOENT, label);
}
static NSDictionary *SRStatusNoSideEffects(QHSplitRootFixture *f) {
    NSDictionary *before = SRCapture(f.directory);
    NSDictionary *status = f.status;
    SRCheck([before isEqual:SRCapture(f.directory)], @"status does not alter fixture artifacts");
    return status;
}

static void SRValidLayoutAndOwnership(BOOL mixedUID) {
    QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
    NSDictionary *status = SRStatusNoSideEffects(f);
    SRCheck([status[@"ok"] boolValue] && [status[@"state"] isEqual:@"unmanaged"] &&
                [status[@"requiresAdoption"] boolValue] && ![status[@"hasBaseline"] boolValue],
            mixedUID ? @"root: primary uid501 plus paired-var uid501 accepted"
                     : @"ordinary-user split-root fixture uses current UID throughout");
    SRCheckNoState(f, @"status before adoption creates no state directory");
    [f checkRaw];
    if (![status[@"ok"] boolValue]) {
        return;
    }
    struct stat st;
    SRCheck(lstat(f.root.fileSystemRepresentation, &st) == 0 && st.st_uid == (mixedUID ? 501 : getuid()),
            @"primary container owner matches split-root role");
    SRCheck(lstat(f.pairedVar.fileSystemRepresentation, &st) == 0 && st.st_uid == (mixedUID ? 501 : getuid()),
            @"paired var owner matches split-root role");
    for (NSString *protectedPath in
         @[ f.etc, f.privateDirectory, f.pairedRoot, f.pairedLib, f.raw.stringByDeletingLastPathComponent ]) {
        SRCheck(lstat(protectedPath.fileSystemRepresentation, &st) == 0 && st.st_uid == f.expectedOwner,
                @"protected split-root directory is expected-owner owned");
    }
    SRCheck(lstat(f.raw.fileSystemRepresentation, &st) == 0 && st.st_uid == f.expectedOwner,
            @"raw hosts fixture is expected-owner owned");
    [f checkRaw];
}

static void SRRegularAdoptionAndRestore(BOOL mixedUID) {
    QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
    if (mixedUID) {
        SRSetOwner(f.target, f.expectedOwner, 501); // restore original GID, not helper's GID
    }
    struct stat originalStat;
    SRRequire(lstat(f.target.fileSystemRepresentation, &originalStat) == 0);
    NSData *original = SRText(SRDefaultHosts);
    NSDictionary *beforeDirectory = SRCapture(f.etc);
    NSDictionary *status = f.status;
    SRCheck([status[@"ok"] boolValue] && [status[@"requiresAdoption"] boolValue] &&
                [status[@"existingHostsBytes"] unsignedIntegerValue] == original.length &&
                [status[@"existingHostsHash"] isEqual:SRSHA(original)],
            @"only default regular mappings expose explicit adoption preview");
    SRCheck([beforeDirectory isEqual:SRCapture(f.etc)], @"adoption preview is read-only");
    SRCheckNoState(f, @"adoption preview creates no state artifacts");

    NSDictionary *refused = [f applyRequestWithConsent:nil revision:status[@"revision"] extra:nil];
    SRCheck(![refused[@"ok"] boolValue] && [refused[@"errorCode"] isEqual:@"adoption-required"] &&
                ![refused[@"changed"] boolValue],
            @"apply without explicit consent refuses takeover");
    SRCheck([beforeDirectory isEqual:SRCapture(f.etc)], @"unconfirmed adoption leaves target byte-for-byte");
    SRCheckNoState(f, @"unconfirmed adoption creates no state or backup");

    NSDictionary *applied = [f apply:YES revision:status[@"revision"]];
    NSMutableData *combined = [original mutableCopy];
    [combined appendData:SRBlocks()];
    SRCheck([applied[@"ok"] boolValue] && [applied[@"state"] isEqual:@"active"] &&
                [applied[@"changed"] boolValue] && [applied[@"hasBaseline"] boolValue],
            @"explicitly confirmed regular takeover commits active state");
    SRCheck(SRTargetBytes(f, combined), @"active target is exact original bytes plus canonical rules");
    NSString *backup = [f.state stringByAppendingPathComponent:@"original.bin"];
    NSData *saved = [NSData dataWithContentsOfFile:backup];
    SRCheck([saved isEqual:original] && ![saved isEqual:SRText(SRRawHosts)],
            @"backup is exact regular target, never substituted raw baseline");
    SRCheck([[NSFileManager.defaultManager attributesOfItemAtPath:f.raw error:NULL][NSFileSize]
                unsignedIntegerValue] == SRText(SRRawHosts).length,
            @"raw file remains its independent fixture baseline");
    struct stat backupStat;
    SRCheck(lstat(backup.fileSystemRepresentation, &backupStat) == 0 && (backupStat.st_mode & 0777) == 0400 &&
                backupStat.st_nlink == 1,
            @"adopted baseline backup is private, immutable-mode, single-link");
    [f checkRaw];

    NSDictionary *active = f.status;
    NSDictionary *repeat = [f applyRequestWithConsent:nil revision:active[@"revision"] extra:nil];
    SRCheck([repeat[@"ok"] boolValue] && ![repeat[@"changed"] boolValue],
            @"repeat apply without adoption flag is a no-op");
    NSDictionary *disabled = [f command:@"disable"];
    struct stat restored;
    SRCheck([disabled[@"ok"] boolValue] && [disabled[@"state"] isEqual:@"inactive"] &&
                lstat(f.target.fileSystemRepresentation, &restored) == 0 && S_ISREG(restored.st_mode) &&
                (restored.st_mode & 07777) == (originalStat.st_mode & 07777) &&
                restored.st_uid == originalStat.st_uid && restored.st_gid == originalStat.st_gid &&
                [[NSData dataWithContentsOfFile:f.target] isEqual:original],
            @"disable restores exact original regular bytes, owner, group, and mode");
    NSDictionary *enabled = [f command:@"enable"];
    SRCheck([enabled[@"ok"] boolValue] && [enabled[@"state"] isEqual:@"active"] && SRTargetBytes(f, combined),
            @"enable rebuilds rules from the immutable original snapshot");
    [f checkRaw];
}

static void SRAdoptionContractAndBadRegulars(BOOL mixedUID) {
    for (NSString *badKind in @[ @"extra-domain", @"redirect", @"missing-default", @"invalid-utf8" ]) {
        @autoreleasepool {
            QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
            NSData *bad = nil;
            if ([badKind isEqual:@"extra-domain"]) {
                bad = SRText([SRDefaultHosts stringByAppendingString:@"0.0.0.0 ads.example\n"]);
            } else if ([badKind isEqual:@"redirect"]) {
                bad = SRText([SRDefaultHosts stringByAppendingString:@"192.0.2.55 redirect.example\n"]);
            } else if ([badKind isEqual:@"missing-default"]) {
                bad = SRText([SRDefaultHosts stringByReplacingOccurrencesOfString:@"::1 localhost\n"
                                                                       withString:@""]);
            } else {
                const unsigned char invalid[] = {0xff, 0xfe, 0x80};
                NSMutableData *data = [SRText(SRDefaultHosts) mutableCopy];
                [data appendBytes:invalid length:sizeof(invalid)];
                bad = data;
            }
            SRRequire(unlink(f.target.fileSystemRepresentation) == 0);
            SRWrite(f.target, bad, 0644, f.expectedOwner, f.expectedGroup);
            NSDictionary *before = SRCapture(f.directory);
            NSDictionary *status = f.status;
            SRCheck(![status[@"ok"] boolValue] && ![status[@"requiresAdoption"] boolValue],
                    [NSString stringWithFormat:@"nondefault regular %@ is not adoption eligible", badKind]);
            NSDictionary *attempt = [f applyRequestWithConsent:@YES revision:status[@"revision"] extra:nil];
            SRCheck(![attempt[@"ok"] boolValue] && ![attempt[@"changed"] boolValue],
                    [NSString stringWithFormat:@"nondefault regular %@ is rejected by apply", badKind]);
            SRCheck([before isEqual:SRCapture(f.directory)], @"rejected regular candidate is unchanged");
            SRCheckNoState(f, @"rejected nondefault regular never creates adoption state");
            [f checkRaw];
        }
    }

    QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
    NSDictionary *status = f.status;
    NSDictionary *before = SRCapture(f.directory);
    NSDictionary *falseConsent = [f applyRequestWithConsent:@NO revision:status[@"revision"] extra:nil];
    SRCheck(![falseConsent[@"ok"] boolValue] && [falseConsent[@"errorCode"] isEqual:@"adoption-required"],
            @"explicit false boolean is valid schema but not takeover consent");
    SRCheck([before isEqual:SRCapture(f.directory)], @"false consent changes no target or state");
    NSDictionary *wrongType = [f applyRequestWithConsent:@1 revision:status[@"revision"] extra:nil];
    SRCheck(![wrongType[@"ok"] boolValue] && [wrongType[@"errorCode"] isEqual:@"invalid-request"],
            @"non-boolean adoption consent is rejected by request schema");
    NSDictionary *extra = [f applyRequestWithConsent:@YES
                                            revision:status[@"revision"]
                                               extra:@{
                                                   @"force" : @YES
                                               }];
    SRCheck(![extra[@"ok"] boolValue] && [extra[@"errorCode"] isEqual:@"invalid-request"],
            @"unknown adoption request flags are not accepted");
    SRCheck([before isEqual:SRCapture(f.directory)], @"invalid consent schemas are side-effect free");
    SRCheckNoState(f, @"invalid consent schemas create no state");

    QHSplitRootFixture *mirror = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
    SRRequire(unlink(mirror.target.fileSystemRepresentation) == 0);
    SRRequire(symlink(mirror.raw.fileSystemRepresentation, mirror.target.fileSystemRepresentation) == 0);
    NSDictionary *mirrorStatus = mirror.status;
    NSDictionary *mirrorBefore = SRCapture(mirror.directory);
    NSDictionary *inapplicableConsent = [mirror applyRequestWithConsent:@YES
                                                               revision:mirrorStatus[@"revision"]
                                                                  extra:nil];
    SRCheck(![inapplicableConsent[@"ok"] boolValue] &&
                [inapplicableConsent[@"errorCode"] isEqual:@"adoption-required"],
            @"adoption consent cannot broaden the existing verified-symlink takeover contract");
    SRCheck([mirrorBefore isEqual:SRCapture(mirror.directory)], @"inapplicable consent preserves mirror");
    [mirror checkRaw];
}

static void SRRequireRefusal(QHSplitRootFixture *f, NSString *label) {
    NSDictionary *before = SRCapture(f.directory);
    NSDictionary *status = f.status;
    SRCheck(![status[@"ok"] boolValue], label);
    SRCheck([before isEqual:SRCapture(f.directory)], @"invalid split-root layout status is read-only");
    SRCheckNoState(f, @"invalid split-root layout cannot create private state");
    [f checkRaw];
}
static void SRPathAndLinkRefusals(BOOL mixedUID) {
    {
        QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
        NSString *wrong = [f.pairedParent stringByAppendingPathComponent:@".jbroot-0123456789ABCDE0/var"];
        f.manager = [[QHFileManager alloc] initWithRoot:f.root
                                            systemHosts:f.raw
                                          expectedOwner:f.expectedOwner
                                         pairedDataRoot:wrong];
        SRRequireRefusal(f, @"paired root leaf must match primary 16-hex brand");
    }
    {
        QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
        NSString *link = [f.pairedRoot stringByAppendingPathComponent:@".jbroot"];
        SRRequire(unlink(link.fileSystemRepresentation) == 0);
        SRRequire(
            symlink(@"/rootfs/foreign-jbroot".fileSystemRepresentation, link.fileSystemRepresentation) == 0);
        SRRequireRefusal(f, @"paired-root backlink to wrong namespace is refused");
    }
    {
        QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
        NSString *outside = [f.directory stringByAppendingPathComponent:@"other-var"];
        SRDirectory(outside, 0755, f.expectedOwner, f.expectedGroup);
        NSString *privateVar = [f.privateDirectory stringByAppendingPathComponent:@"var"];
        SRRequire(unlink(privateVar.fileSystemRepresentation) == 0);
        SRRequire(symlink(outside.fileSystemRepresentation, privateVar.fileSystemRepresentation) == 0);
        SRRequireRefusal(f, @"private/var cannot route to an arbitrary valid directory");
    }
    {
        QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
        NSString *var = [f.pairedRoot stringByAppendingPathComponent:@"var"];
        NSString *foreign = [f.directory stringByAppendingPathComponent:@"foreign-var"];
        SRDirectory(foreign, 0755, mixedUID ? (uid_t)501 : f.expectedOwner,
                    mixedUID ? (gid_t)501 : f.expectedGroup);
        NSString *originalVar = [f.directory stringByAppendingPathComponent:@"original-paired-var"];
        SRRequire(rename(var.fileSystemRepresentation, originalVar.fileSystemRepresentation) == 0);
        SRRequire(symlink(foreign.fileSystemRepresentation, var.fileSystemRepresentation) == 0);
        SRRequireRefusal(f, @"paired var symlink is rejected even when its target is a safe directory");
    }
    {
        QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
        NSString *var = [f.pairedRoot stringByAppendingPathComponent:@"var"];
        NSString *old = [f.directory stringByAppendingPathComponent:@"saved-paired-var"];
        SRRequire(rename(var.fileSystemRepresentation, old.fileSystemRepresentation) == 0);
        SRWrite(var, SRText(@"not a directory"), 0644, f.expectedOwner, f.expectedGroup);
        SRRequireRefusal(f, @"paired var non-directory is rejected");
    }
    {
        QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
        NSString *rootfsRoot = [@"/rootfs" stringByAppendingString:[f.root substringFromIndex:1]];
        NSString *rootfsPair = [@"/rootfs" stringByAppendingString:[f.pairedVar substringFromIndex:1]];
        f.manager = [[QHFileManager alloc] initWithRoot:rootfsRoot
                                            systemHosts:f.raw
                                          expectedOwner:f.expectedOwner
                                         pairedDataRoot:rootfsPair];
        SRRequireRefusal(f, @"terminal /rootfs spelling is not treated as native paired root");
    }
}

static void SRSetWrongOwner(NSString *path) {
    /* Called only under the isolated root-only mixed-UID runner. UID 501 is
     * used solely for entries created inside this suite's private fixture. */
    SRRequire(chown(path.fileSystemRepresentation, 501, 501) == 0);
}
static void SRProtectedOwnerRefusals(void) {
    if (getuid() != 0) {
        SRCheck(NO, @"mixed-UID ownership fixtures require the root-only isolated runner");
        return;
    }
    NSArray<NSString *> *roles = @[ @"etc", @"private", @"paired-root", @"lib", @"state" ];
    for (NSString *role in roles) {
        @autoreleasepool {
            QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:YES];
            if ([role isEqual:@"state"]) {
                SRDirectory(f.state, 0700, 0, 0);
                SRSetWrongOwner(f.state);
            } else {
                NSString *path = [role isEqual:@"etc"]
                                     ? f.etc
                                     : ([role isEqual:@"private"]
                                            ? f.privateDirectory
                                            : ([role isEqual:@"paired-root"] ? f.pairedRoot : f.pairedLib));
                SRSetWrongOwner(path);
            }
            SRRequireRefusal(f, [NSString stringWithFormat:@"%@ remains protected from UID 501", role]);
        }
    }
    for (NSString *role in @[ @"primary-root", @"paired-var", @"etc", @"private", @"paired-root", @"lib" ]) {
        @autoreleasepool {
            QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:YES];
            NSString *path =
                [role isEqual:@"primary-root"]
                    ? f.root
                    : ([role isEqual:@"paired-var"]
                           ? f.pairedVar
                           : ([role isEqual:@"etc"]
                                  ? f.etc
                                  : ([role isEqual:@"private"]
                                         ? f.privateDirectory
                                         : ([role isEqual:@"paired-root"] ? f.pairedRoot : f.pairedLib))));
            SRRequire(chmod(path.fileSystemRepresentation, 0777) == 0);
            SRRequireRefusal(f, [NSString stringWithFormat:@"unsafe 0777 mode rejected for %@", role]);
        }
    }
    {
        QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:YES];
        SRDirectory(f.state, 0777, 0, 0);
        SRRequireRefusal(f, @"group/world-writable private state directory rejected");
    }
}

static void SRCrash(QHSplitRootFixture *f, NSString *point) {
    NSDictionary *status = f.status;
    pid_t child = fork();
    SRRequire(child >= 0);
    if (child == 0) {
        signal(SIGALRM, SIG_DFL);
        alarm(30);
        QHSetTransactionFault(point);
        [f apply:YES revision:status[@"revision"]];
        _exit(87);
    }
    int result = 0;
    pid_t waited;
    do {
        waited = waitpid(child, &result, 0);
    } while (waited < 0 && errno == EINTR);
    SRCheck(waited == child && WIFEXITED(result) && WEXITSTATUS(result) == 86,
            [NSString stringWithFormat:@"fault injection reached %@ in child", point]);
}
static void SRCrashRecovery(BOOL mixedUID) {
    /* Run before any cloud/test runner initializes concurrent networking. The
     * injected exit occurs in a child; the parent alone performs recovery. */
    for (NSString *point in @[ @"after-journal", @"after-backup", @"after-target", @"after-state" ]) {
        @autoreleasepool {
            QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
            SRCrash(f, point);
            NSDictionary *recovered = f.status;
            NSData *original = SRText(SRDefaultHosts);
            NSMutableData *combined = [original mutableCopy];
            [combined appendData:SRBlocks()];
            SRCheck([recovered[@"ok"] boolValue] && [recovered[@"state"] isEqual:@"active"] &&
                        [recovered[@"reloadPending"] boolValue],
                    [NSString stringWithFormat:@"status replays adoption journal after %@", point]);
            SRCheck([[NSData dataWithContentsOfFile:[f.state stringByAppendingPathComponent:@"original.bin"]]
                        isEqual:original],
                    @"crash recovery promotes exact regular adoption backup");
            SRCheck(SRTargetBytes(f, combined), @"crash recovery commits expected regular target");
            [f checkRaw];
            NSDictionary *disabled = [f command:@"disable"];
            SRCheck([disabled[@"ok"] boolValue] &&
                        [[NSData dataWithContentsOfFile:f.target] isEqual:original],
                    @"recovered adoption still restores exact regular original");
        }
    }

    QHSplitRootFixture *foreign = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
    SRCrash(foreign, @"after-journal");
    SRRequire(unlink(foreign.target.fileSystemRepresentation) == 0);
    NSData *foreignBytes = SRText(@"foreign target installed after transaction journal\n");
    SRWrite(foreign.target, foreignBytes, 0644, foreign.expectedOwner, foreign.expectedGroup);
    NSString *journal = [foreign.state stringByAppendingPathComponent:@"journal.json"];
    NSDictionary *refused = foreign.status;
    SRCheck(![refused[@"ok"] boolValue] && [refused[@"errorCode"] isEqual:@"recovery-conflict"],
            @"unknown foreign target blocks recovery");
    SRCheck([[NSData dataWithContentsOfFile:foreign.target] isEqual:foreignBytes] &&
                [[NSData dataWithContentsOfFile:journal] length] > 0,
            @"recovery preserves foreign target and diagnostic journal");
    [foreign checkRaw];
}

/* Private seam implemented by QHFileManager.m only under QH_TESTING. */
extern void QHSetDirectoryMutationHook(NSString *point, void (^mutation)(void));
static void SRNamespacePostcheckMutation(BOOL mixedUID) {
    QHSplitRootFixture *f = [[QHSplitRootFixture alloc] initWithMixedUID:mixedUID];
    NSDictionary *preview = f.status;
    __block BOOL fired = NO;
    NSString *parked = [f.directory stringByAppendingPathComponent:@"temporarily-detached-etc"];
    QHSetDirectoryMutationHook(@"after-check:commit-target", ^{
        fired = YES;
        SRRequire(rename(f.etc.fileSystemRepresentation, parked.fileSystemRepresentation) == 0);
        SRRequire(rename(parked.fileSystemRepresentation, f.etc.fileSystemRepresentation) == 0);
    });
    NSDictionary *result = [f apply:YES revision:preview[@"revision"]];
    QHSetDirectoryMutationHook(nil, nil);
    SRCheck(fired, @"deterministic namespace post-check hook ran");
    // The syscall can occur after the final anchor check. Do not hide that gap
    // with an extra test-only pre-write check or assert an impossible zero-write guarantee.
    SRCheck(![result[@"ok"] boolValue] && [result[@"errorCode"] isEqual:@"directory-raced"],
            @"move-away/move-back is detected at the next guard and never reports success");
    SRCheck([result[@"changed"] boolValue], @"test exposes a target write after the last check");
    SRCheck([[NSData dataWithContentsOfFile:[f.state stringByAppendingPathComponent:@"original.bin"]]
                isEqual:SRText(SRDefaultHosts)],
            @"exact original backup survives the post-check race");
    SRCheck([NSFileManager.defaultManager
                fileExistsAtPath:[f.state stringByAppendingPathComponent:@"journal.json"]],
            @"uncertain commit retains recovery journal");
    [f checkRaw];
}

NSUInteger RunSplitRootTests(BOOL mixedUID) {
    SplitRootFailures = 0;
    SplitRootChecks = 0;
    if (mixedUID && getuid() != 0) {
        SRCheck(NO, @"mixed-UID suite must run only as root on isolated fixtures");
        NSLog(@"SplitRootTests: %lu checks, %lu failures (mixedUID=%@)", (unsigned long)SplitRootChecks,
              (unsigned long)SplitRootFailures, @"YES");
        return SplitRootFailures;
    }
    @autoreleasepool {
        SRValidLayoutAndOwnership(mixedUID);
        SRRegularAdoptionAndRestore(mixedUID);
        SRAdoptionContractAndBadRegulars(mixedUID);
        SRPathAndLinkRefusals(mixedUID);
        if (mixedUID) {
            SRProtectedOwnerRefusals();
        }
        SRCrashRecovery(mixedUID);
        SRNamespacePostcheckMutation(mixedUID);
    }
    NSLog(@"SplitRootTests: %lu checks, %lu failures (mixedUID=%@)", (unsigned long)SplitRootChecks,
          (unsigned long)SplitRootFailures, mixedUID ? @"YES" : @"NO");
    return SplitRootFailures;
}
