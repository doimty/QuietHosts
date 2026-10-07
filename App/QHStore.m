#import "QHStore.h"
#import "QHDownload.h"
#import "../Shared/QHLocalization.h"
#import <TargetConditionals.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

NSString *const QHStoreErrorDomain = @"QHStoreErrorDomain";
NSUInteger const QHMaximumSources = 32;
static NSUInteger const QHStoreDiskLimit = 33 * 1024 * 1024;
static NSError *StoreError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:QHStoreErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}
static BOOL Fail(NSError **error, NSInteger code, NSString *message) {
    if (error) {
        *error = StoreError(code, message);
    }
    return NO;
}
static BOOL SafeString(id value, NSUInteger limit, BOOL empty) {
    return [value isKindOfClass:NSString.class] && [value length] <= limit && (empty || [value length]) &&
           [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}
static BOOL Keys(NSDictionary *value, NSArray *allowed) {
    for (id key in value) {
        if (![allowed containsObject:key]) {
            return NO;
        }
    }
    return YES;
}
static NSData *ReadFD(int fd, NSUInteger limit, NSError **error) {
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size < 0 || (uint64_t)st.st_size > limit) {
        Fail(error, 2, QHL(@"The file is unreadable or exceeds its size limit."));
        return nil;
    }
    NSMutableData *data = [NSMutableData data];
    unsigned char buffer[65536];
    while (YES) {
        NSUInteger remaining = limit - data.length;
        size_t requested = MIN(sizeof(buffer), remaining + 1);
        ssize_t n = read(fd, buffer, requested);
        if (n < 0 && errno == EINTR) {
            continue;
        }
        if (n < 0) {
            Fail(error, 2, QHL(@"The file could not be read. No rules were changed."));
            return nil;
        }
        if (!n) {
            break;
        }
        if ((NSUInteger)n > remaining) {
            Fail(error, 2, QHL(@"The file exceeds its size limit."));
            return nil;
        }
        [data appendBytes:buffer length:(NSUInteger)n];
    }
    return [data copy];
}

@interface QHStorePreview ()
@property(nonatomic, readwrite, copy) NSDictionary *document;
@property(nonatomic, readwrite, copy) NSString *baseRevision;
@property(nonatomic, readwrite, strong) QHCompiledRules *compiled;
@property(nonatomic, readwrite, copy) NSDictionary<NSString *, QHParseResult *> *sourceResults;
@property(nonatomic, readwrite) NSUInteger allowlistCount;
@property(nonatomic, readwrite, copy) NSDictionary<NSString *, NSNumber *> *parseStatistics;
@end
@implementation QHStorePreview
@end

@implementation QHStore {
    NSURL *_directory;
    NSRecursiveLock *_lock;
}
- (instancetype)init {
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                       inDomains:NSUserDomainMask]
                      .firstObject;
    return [self initPrivateDirectory:[base URLByAppendingPathComponent:@"QuietHosts" isDirectory:YES]];
}
- (instancetype)initPrivateDirectory:(NSURL *)directory {
    if ((self = [super init])) {
        _directory = [directory copy];
        _lock = [NSRecursiveLock new];
    }
    return self;
}
#if defined(QH_TESTING) && QH_TESTING
- (instancetype)initWithDirectory:(NSURL *)directory {
    return [self initPrivateDirectory:directory];
}
#endif
- (NSURL *)documentURL {
    return [_directory URLByAppendingPathComponent:@"sources.plist"];
}
- (NSDictionary *)emptyDocument {
    return @{@"schema" : @1, @"revision" : @"empty", @"sources" : @[], @"allowlist" : [NSData data]};
}
- (BOOL)validateDirectory:(NSError **)error absent:(BOOL *)absent {
    *absent = NO;
    if (!_directory.isFileURL) {
        return Fail(error, 1, QHL(@"Local storage is unavailable."));
    }
    struct stat st;
    if (lstat(_directory.fileSystemRepresentation, &st)) {
        if (errno == ENOENT) {
            *absent = YES;
            return YES;
        }
        return Fail(error, 1, QHL(@"Local storage is unavailable."));
    }
    if (!S_ISDIR(st.st_mode) || st.st_uid != getuid() || (st.st_mode & 0077)) {
        return Fail(error, 1, QHL(@"Local storage permissions are unsafe. Existing data was preserved."));
    }
    return YES;
}
- (NSDictionary *)readDocument:(NSError **)error {
    BOOL absent = NO;
    if (![self validateDirectory:error absent:&absent]) {
        return nil;
    }
    if (absent) {
        return [self emptyDocument];
    }
    int fd = open(self.documentURL.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        if (errno == ENOENT) {
            return [self emptyDocument];
        }
        Fail(error, 1, QHL(@"Local storage could not be opened. Existing data was preserved."));
        return nil;
    }
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() || st.st_nlink != 1 ||
        (st.st_mode & 0077)) {
        close(fd);
        Fail(error, 1, QHL(@"Local storage permissions are unsafe. Existing data was preserved."));
        return nil;
    }
    NSData *data = ReadFD(fd, QHStoreDiskLimit, error);
    close(fd);
    if (!data) {
        return nil;
    }
    NSPropertyListFormat format;
    id document = [NSPropertyListSerialization propertyListWithData:data
                                                            options:NSPropertyListImmutable
                                                             format:&format
                                                              error:NULL];
    if (![document isKindOfClass:NSDictionary.class] || format != NSPropertyListBinaryFormat_v1_0) {
        Fail(error, 3, QHL(@"Local storage is damaged. It has not been replaced or reset."));
        return nil;
    }
    return document;
}
- (QHStorePreview *)validateDocument:(NSDictionary *)document
                        baseRevision:(NSString *)base
                               error:(NSError **)error {
    if (![document isKindOfClass:NSDictionary.class] ||
        !Keys(document, @[ @"schema", @"revision", @"sources", @"allowlist" ]) ||
        ![document[@"schema"] isKindOfClass:NSNumber.class] || ![document[@"schema"] isEqual:@1] ||
        !SafeString(document[@"revision"], 64, NO) || ![document[@"sources"] isKindOfClass:NSArray.class] ||
        ![document[@"allowlist"] isKindOfClass:NSData.class]) {
        Fail(error, 3, QHL(@"Local storage is damaged. It has not been replaced or reset."));
        return nil;
    }
    NSArray *sources = document[@"sources"];
    NSData *allowData = document[@"allowlist"];
    if (sources.count > QHMaximumSources || allowData.length > QHMaximumInputBytes) {
        Fail(error, 4, QHL(@"Limit exceeded: 32 sources, 16 MiB per input, 32 MiB total raw data."));
        return nil;
    }
    NSUInteger total = allowData.length;
    NSMutableSet *identifiers = [NSMutableSet set];
    // Budget and metadata validation precedes all parsing or defensive copies.
    for (id object in sources) {
        if (![object isKindOfClass:NSDictionary.class]) {
            Fail(error, 3, QHL(@"The source metadata is invalid."));
            return nil;
        }
        NSDictionary *source = object;
        if (!Keys(source, @[ @"id", @"name", @"enabled", @"kind", @"url", @"data" ]) ||
            !SafeString(source[@"id"], 64, NO) || ![[NSUUID alloc] initWithUUIDString:source[@"id"]] ||
            [identifiers containsObject:source[@"id"]] || !SafeString(source[@"name"], 120, NO) ||
            ![source[@"enabled"] isKindOfClass:NSNumber.class] ||
            ![@[ @0, @1 ] containsObject:source[@"enabled"]] ||
            ![@[ @"url", @"file", @"paste" ] containsObject:source[@"kind"]] ||
            ![source[@"data"] isKindOfClass:NSData.class]) {
            Fail(error, 3, QHL(@"The source metadata is invalid."));
            return nil;
        }
        [identifiers addObject:source[@"id"]];
        if ([source[@"kind"] isEqual:@"url"]) {
            if (!SafeString(source[@"url"], 4096, NO) || ![QHDownload validatedURLFromString:source[@"url"]
                                                                                       error:NULL]) {
                Fail(error, 3, QHL(@"The stored source URL is invalid. It was not displayed or requested."));
                return nil;
            }
        } else if (source[@"url"]) {
            Fail(error, 3, QHL(@"The source metadata is invalid."));
            return nil;
        }
        NSUInteger length = [source[@"data"] length];
        if (length > QHMaximumInputBytes || length > QHMaximumDocumentBytes - total) {
            Fail(error, 4, QHL(@"Limit exceeded: 32 sources, 16 MiB per input, 32 MiB total raw data."));
            return nil;
        }
        total += length;
    }
    NSSet *allow = QHParseAllowlist(allowData, error);
    if (!allow) {
        return nil;
    }
    NSMutableArray *enabled = [NSMutableArray array];
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];
    for (NSDictionary *source in sources) {
        QHParseResult *result = QHParseRules(source[@"data"], error);
        if (!result) {
            return nil;
        }
        results[source[@"id"]] = result;
        if ([source[@"enabled"] boolValue]) {
            [enabled addObject:result];
        }
        for (NSString *key in result.statistics) {
            stats[key] =
                @([stats[key] unsignedLongLongValue] + [result.statistics[key] unsignedLongLongValue]);
        }
    }
    QHCompiledRules *compiled = QHCompileDomains(enabled, allow, error);
    if (!compiled) {
        return nil;
    }
    // Deep immutable copy prevents mutable caller data changing an approved preview.
    NSData *encoded = [NSPropertyListSerialization dataWithPropertyList:document
                                                                 format:NSPropertyListBinaryFormat_v1_0
                                                                options:0
                                                                  error:NULL];
    if (!encoded || encoded.length > QHStoreDiskLimit) {
        Fail(error, 4, QHL(@"The local document exceeds its storage limit."));
        return nil;
    }
    QHStorePreview *preview = [QHStorePreview new];
    preview.document = [NSPropertyListSerialization propertyListWithData:encoded
                                                                 options:NSPropertyListImmutable
                                                                  format:NULL
                                                                   error:NULL];
    preview.baseRevision = base ?: preview.document[@"revision"];
    preview.compiled = compiled;
    preview.sourceResults = results;
    preview.allowlistCount = allow.count;
    preview.parseStatistics = stats;
    return preview;
}
- (QHStorePreview *)load:(NSError **)error {
    [_lock lock];
    @try {
        NSDictionary *document = [self readDocument:error];
        return document ? [self validateDocument:document baseRevision:nil error:error] : nil;
    } @finally {
        [_lock unlock];
    }
}
- (QHStorePreview *)previewSources:(NSArray<NSDictionary *> *)sources
                         allowlist:(NSData *)allowlist
                  expectedRevision:(NSString *)revision
                             error:(NSError **)error {
    [_lock lock];
    @try {
        QHStorePreview *current = [self load:error];
        if (!current) {
            return nil;
        }
        if (![current.document[@"revision"] isEqual:revision]) {
            Fail(error, 5, QHL(@"The local draft changed. Cancel and create a new preview."));
            return nil;
        }
        NSDictionary *document = @{
            @"schema" : @1,
            @"revision" : NSUUID.UUID.UUIDString,
            @"sources" : sources,
            @"allowlist" : allowlist
        };
        return [self validateDocument:document baseRevision:revision error:error];
    } @finally {
        [_lock unlock];
    }
}
- (BOOL)ensureDirectory:(NSError **)error {
    BOOL absent = NO;
    if (![self validateDirectory:error absent:&absent]) {
        return NO;
    }
    if (absent) {
        NSDictionary *attributes = @{NSFilePosixPermissions : @0700};
        if (![NSFileManager.defaultManager createDirectoryAtURL:_directory
                                    withIntermediateDirectories:YES
                                                     attributes:attributes
                                                          error:NULL]) {
            return Fail(error, 1, QHL(@"Local storage could not be created."));
        }
        if (![self validateDirectory:error absent:&absent] || absent) {
            return NO;
        }
    }
    return YES;
}
- (BOOL)commitPreview:(QHStorePreview *)preview error:(NSError **)error {
    [_lock lock];
    int directoryFD = -1;
    @try {
        if (![preview isKindOfClass:QHStorePreview.class] || !preview.document || !preview.baseRevision) {
            return Fail(error, 3, QHL(@"The preview is invalid. No rules were saved."));
        }
        // Reject existing corruption BEFORE creating any storage artifacts.
        QHStorePreview *current = [self load:error];
        if (!current) {
            return NO;
        }
        if (![self ensureDirectory:error]) {
            return NO;
        }
        directoryFD =
            open(_directory.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
        if (directoryFD < 0 || flock(directoryFD, LOCK_EX | LOCK_NB)) {
            return Fail(error, 1, QHL(@"Local storage is busy or unavailable."));
        }
        current = [self load:error];
        if (!current) {
            return NO;
        }
        if (![current.document[@"revision"] isEqual:preview.baseRevision]) {
            return Fail(error, 5, QHL(@"The local draft changed. Cancel and create a new preview."));
        }
        QHStorePreview *checked = [self validateDocument:preview.document
                                            baseRevision:preview.baseRevision
                                                   error:error];
        if (!checked || [checked.document[@"revision"] isEqual:checked.baseRevision]) {
            return Fail(error, 3, QHL(@"The preview is invalid. No rules were saved."));
        }
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:checked.document
                                                                  format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0
                                                                   error:NULL];
        NSString *temporaryName = [@".pending-" stringByAppendingString:NSUUID.UUID.UUIDString];
        NSURL *temporaryURL = [_directory URLByAppendingPathComponent:temporaryName];
        int fd = openat(directoryFD, temporaryName.UTF8String,
                        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (fd < 0) {
            return Fail(error, 1, QHL(@"The local draft could not be saved. Existing data was preserved."));
        }
        BOOL okay = YES;
#if TARGET_OS_IPHONE
        okay = [NSFileManager.defaultManager
            setAttributes:@{NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication}
             ofItemAtPath:temporaryURL.path
                    error:NULL];
#else
        (void)temporaryURL;
#endif
        const uint8_t *bytes = data.bytes;
        NSUInteger offset = 0;
        while (okay && offset < data.length) {
            ssize_t n = write(fd, bytes + offset, data.length - offset);
            if (n < 0 && errno == EINTR) {
                continue;
            }
            if (n <= 0) {
                okay = NO;
                break;
            }
            offset += (NSUInteger)n;
        }
        if (okay && fsync(fd)) {
            okay = NO;
        }
        if (close(fd)) {
            okay = NO;
        }
        if (okay && renameat(directoryFD, temporaryName.UTF8String, directoryFD, "sources.plist")) {
            okay = NO;
        }
        if (!okay) {
            unlinkat(directoryFD, temporaryName.UTF8String, 0);
            return Fail(error, 1, QHL(@"The local draft could not be saved. Existing data was preserved."));
        }
        // Atomic rename is the commit point. Do not report failure after committing.
        (void)fsync(directoryFD);
        return YES;
    } @finally {
        if (directoryFD >= 0) {
            (void)flock(directoryFD, LOCK_UN);
            close(directoryFD);
        }
        [_lock unlock];
    }
}
+ (NSData *)readImportURL:(NSURL *)url error:(NSError **)error {
    if (!url.isFileURL) {
        Fail(error, 2, QHL(@"Choose a local file to import."));
        return nil;
    }
    BOOL scoped = [url startAccessingSecurityScopedResource];
    __block NSData *data = nil;
    __block NSError *readError = nil;
    NSError *coordinationError = nil;
    @try {
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator
            coordinateReadingItemAtURL:url
                               options:0
                                 error:&coordinationError
                            byAccessor:^(NSURL *newURL) {
                                int fd = open(newURL.fileSystemRepresentation,
                                              O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
                                if (fd < 0) {
                                    readError = StoreError(2, QHL(@"The selected file could not be opened."));
                                    return;
                                }
                                data = ReadFD(fd, QHMaximumInputBytes, &readError);
                                close(fd);
                            }];
    } @finally {
        if (scoped) {
            [url stopAccessingSecurityScopedResource];
        }
    }
    if (!data && error) {
        *error =
            readError
                ?: StoreError(
                       2, QHL(@"The selected file could not be read. Try downloading it in Files first."));
    }
    return data;
}
@end
