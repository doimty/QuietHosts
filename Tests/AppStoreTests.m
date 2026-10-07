#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "../App/QHStore.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#if !defined(QH_TESTING) || !QH_TESTING
#error AppStoreTests requires QH_TESTING=1 and isolated temporary fixtures.
#endif
static NSUInteger failures;
static void Check(BOOL okay, NSString *label) {
    if (!okay) {
        failures++;
        NSLog(@"AppStoreTests FAIL: %@", label);
    }
}
static NSData *Text(NSString *text) {
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}
static NSDictionary *Source(NSData *data) {
    return @{
        @"id" : NSUUID.UUID.UUIDString,
        @"name" : @"Fixture",
        @"enabled" : @YES,
        @"kind" : @"paste",
        @"data" : data
    };
}
static NSURL *Child(NSURL *root, NSString *name) {
    return [root URLByAppendingPathComponent:name];
}
static void WriteDocument(NSURL *directory, NSDictionary *document) {
    [NSFileManager.defaultManager createDirectoryAtURL:directory
                           withIntermediateDirectories:YES
                                            attributes:@{
                                                NSFilePosixPermissions : @0700
                                            }
                                                 error:NULL];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:document
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:NULL];
    [data writeToURL:Child(directory, @"sources.plist") atomically:YES];
    chmod(Child(directory, @"sources.plist").fileSystemRepresentation, 0600);
}
static void Transactions(NSURL *root) {
    NSURL *directory = Child(root, @"transactions");
    QHStore *store = [[QHStore alloc] initWithDirectory:directory];
    NSError *error = nil;
    QHStorePreview *empty = [store load:&error];
    Check(empty != nil && error == nil && empty.compiled.domains.count == 0 &&
              [empty.document[@"sources"] count] == 0,
          @"fresh app is empty");
    Check(![NSFileManager.defaultManager fileExistsAtPath:directory.path], @"load does not create files");
    NSMutableData *mutable = [Text(@"a.example\nb.example\na.example\n") mutableCopy];
    QHStorePreview *first = [store previewSources:@[ Source(mutable) ]
                                        allowlist:Text(@"b.example\n")
                                 expectedRevision:empty.baseRevision
                                            error:&error];
    Check(first.compiled.domains.count == 1 && first.allowlistCount == 1,
          @"exact allowlist and merge preview");
    Check(![NSFileManager.defaultManager fileExistsAtPath:directory.path], @"preview never writes files");
    [mutable setData:Text(@"changed.example\n")];
    Check([first.document[@"sources"][0][@"data"] isEqual:Text(@"a.example\nb.example\na.example\n")],
          @"candidate snapshot deep immutable");
    QHStorePreview *stale = [store previewSources:@[ Source(Text(@"other.example\n")) ]
                                        allowlist:[NSData data]
                                 expectedRevision:empty.baseRevision
                                            error:NULL];
    Check([store commitPreview:first error:&error], @"explicit save commits atomically");
    struct stat st;
    Check(lstat(Child(directory, @"sources.plist").fileSystemRepresentation, &st) == 0 &&
              (st.st_mode & 0777) == 0600 && st.st_nlink == 1,
          @"private 0600 regular document");
    NSData *before = [NSData dataWithContentsOfURL:Child(directory, @"sources.plist")];
    Check(![store commitPreview:stale error:NULL], @"stale preview cannot overwrite newer revision");
    Check([before isEqual:[NSData dataWithContentsOfURL:Child(directory, @"sources.plist")]],
          @"conflict retains original bytes");
    QHStorePreview *loaded = [store load:NULL];
    Check([loaded.compiled.hostsData isEqual:first.compiled.hostsData],
          @"reopen reconstructs exact snapshot");
    Check(![store previewSources:loaded.document[@"sources"]
                       allowlist:Text(@"valid.example\n*.invalid.example\n")
                expectedRevision:loaded.baseRevision
                           error:NULL],
          @"invalid allowlist rejects all changes");
    NSMutableDictionary *off = [loaded.document[@"sources"][0] mutableCopy];
    off[@"enabled"] = @NO;
    QHStorePreview *disabled = [store previewSources:@[ off ]
                                           allowlist:[NSData data]
                                    expectedRevision:loaded.baseRevision
                                               error:NULL];
    Check(disabled.compiled.domains.count == 0 && disabled.sourceResults.count == 1,
          @"disabled snapshot retained and excluded from merge");
    NSMutableDictionary *bad = [off mutableCopy];
    bad[@"name"] = @"bad\nname";
    Check(![store previewSources:@[ bad ]
                       allowlist:[NSData data]
                expectedRevision:loaded.baseRevision
                           error:NULL],
          @"control characters in metadata rejected");
    bad = [off mutableCopy];
    bad[@"kind"] = @"url";
    bad[@"url"] = @"https://user:secret@example.test/raw?token=private";
    error = nil;
    Check(![store previewSources:@[ bad ]
                       allowlist:[NSData data]
                expectedRevision:loaded.baseRevision
                           error:&error],
          @"credentials in source URL rejected");
    Check(![error.localizedDescription containsString:@"secret"] &&
              ![error.localizedDescription containsString:@"private"],
          @"source URL redacted from errors");
    bad[@"url"] = @"https://example.test/raw?token=private";
    Check([store previewSources:@[ bad ]
                      allowlist:[NSData data]
               expectedRevision:loaded.baseRevision
                          error:NULL] != nil,
          @"query URL preserved for manual refresh without network");
    Check(![store previewSources:@[ off, off ]
                       allowlist:[NSData data]
                expectedRevision:loaded.baseRevision
                           error:NULL],
          @"duplicate source IDs rejected");
    NSArray *batch = @[
        Source(Text(@"one.example\n")), Source(Text(@"two.example\n")),
        Source([NSData dataWithBytes:"\xff" length:1])
    ];
    Check(![store previewSources:batch
                       allowlist:[NSData data]
                expectedRevision:loaded.baseRevision
                           error:NULL],
          @"last-source parse failure rejects whole batch");
    Check([before isEqual:[NSData dataWithContentsOfURL:Child(directory, @"sources.plist")]],
          @"invalid batch does not partially persist");
    Check(![store commitPreview:loaded error:NULL], @"loaded document is not a new approval transaction");
    QHStorePreview *next = [store previewSources:@[]
                                       allowlist:[NSData data]
                                expectedRevision:loaded.baseRevision
                                           error:NULL];
    __block NSUInteger successes = 0;
    dispatch_apply(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
        (void)i;
        if ([store commitPreview:next error:NULL]) {
            @synchronized(store) {
                successes++;
            }
        }
    });
    Check(successes == 1, @"concurrent commits serialize and only one revision wins");
}
static void Corruption(NSURL *root) {
    NSURL *directory = Child(root, @"corrupt");
    NSDictionary *bad =
        @{@"schema" : @999,
          @"revision" : @"bad",
          @"sources" : @[],
          @"allowlist" : [NSData data]};
    WriteDocument(directory, bad);
    QHStore *store = [[QHStore alloc] initWithDirectory:directory];
    NSData *before = [NSData dataWithContentsOfURL:Child(directory, @"sources.plist")];
    Check(![store load:NULL], @"unknown schema rejected");
    Check(![store previewSources:@[] allowlist:[NSData data] expectedRevision:@"empty" error:NULL],
          @"corruption never becomes empty writable draft");
    Check([before isEqual:[NSData dataWithContentsOfURL:Child(directory, @"sources.plist")]],
          @"corrupt bytes preserved");
    [Text(@"not a property list") writeToURL:Child(directory, @"sources.plist") atomically:NO];
    Check(![store load:NULL], @"truncated plist rejected");
    NSURL *target = Child(root, @"foreign");
    [Text(@"foreign") writeToURL:target atomically:NO];
    unlink(Child(directory, @"sources.plist").fileSystemRepresentation);
    symlink(target.fileSystemRepresentation, Child(directory, @"sources.plist").fileSystemRepresentation);
    Check(![store load:NULL], @"symlink local document refused");
    Check([[NSData dataWithContentsOfURL:target] isEqual:Text(@"foreign")], @"symlink target untouched");
    unlink(Child(directory, @"sources.plist").fileSystemRepresentation);
    int fd = open(Child(directory, @"sources.plist").fileSystemRepresentation, O_CREAT | O_WRONLY, 0600);
    if (fd >= 0) {
        ftruncate(fd, 33LL * 1024 * 1024 + 1);
        close(fd);
    }
    Check(![store load:NULL], @"disk read budget checked before plist allocation");
    chmod(directory.fileSystemRepresentation, 0777);
    Check(![store load:NULL], @"unsafe directory permissions refused");
    chmod(directory.fileSystemRepresentation, 0700);
}
static void LimitsAndFiles(NSURL *root) {
    QHStore *store = [[QHStore alloc] initWithDirectory:Child(root, @"limits")];
    QHStorePreview *empty = [store load:NULL];
    NSMutableArray *sources = [NSMutableArray array];
    for (NSUInteger i = 0; i < 33; i++) {
        [sources addObject:Source([NSData data])];
    }
    Check(![store previewSources:sources
                       allowlist:[NSData data]
                expectedRevision:empty.baseRevision
                           error:NULL],
          @"33 sources rejected");
    [sources removeLastObject];
    Check([store previewSources:sources
                      allowlist:[NSData data]
               expectedRevision:empty.baseRevision
                          error:NULL] != nil,
          @"exactly 32 sources accepted");
    @autoreleasepool {
        NSMutableData *comment = [NSMutableData dataWithLength:QHMaximumInputBytes];
        memset(comment.mutableBytes, ' ', comment.length);
        ((char *)comment.mutableBytes)[0] = '#';
        QHStorePreview *full = [store previewSources:@[ Source(comment), Source(comment) ]
                                           allowlist:[NSData data]
                                    expectedRevision:empty.baseRevision
                                               error:NULL];
        Check(full != nil && full.compiled.domains.count == 0, @"exact 32MiB source raw budget accepted");
        Check(![store previewSources:@[ Source(comment), Source(comment) ]
                           allowlist:Text(@"#")
                    expectedRevision:empty.baseRevision
                               error:NULL],
              @"allowlist shares raw document budget");
        [comment appendBytes:" " length:1];
        Check(![store previewSources:@[ Source(comment) ]
                           allowlist:[NSData data]
                    expectedRevision:empty.baseRevision
                               error:NULL],
              @"16MiB plus one source rejected");
    }
    NSURL *file = Child(root, @"import.txt");
    [Text(@"test.example\n") writeToURL:file atomically:NO];
    Check([[QHStore readImportURL:file error:NULL] isEqual:Text(@"test.example\n")],
          @"coordinated local read");
    int fd = open(file.fileSystemRepresentation, O_WRONLY | O_TRUNC);
    if (fd >= 0) {
        ftruncate(fd, (off_t)QHMaximumInputBytes + 1);
        close(fd);
    }
    Check(![QHStore readImportURL:file error:NULL], @"oversize coordinated file rejected");
    Check(![QHStore readImportURL:[NSURL URLWithString:@"https://example.test/"] error:NULL],
          @"import reader never downloads URLs");
}
// Return failures, not check count; native cloud runner must assert zero.
NSUInteger RunAppStoreTests(void) {
    failures = 0;
    NSURL *root = [NSURL
        fileURLWithPath:[NSTemporaryDirectory()
                            stringByAppendingPathComponent:[@"QHStoreTests-"
                                                               stringByAppendingString:NSUUID.UUID
                                                                                           .UUIDString]]
            isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:root
                           withIntermediateDirectories:YES
                                            attributes:@{
                                                NSFilePosixPermissions : @0700
                                            }
                                                 error:NULL];
    @try {
        Transactions(root);
        Corruption(root);
        LimitsAndFiles(root);
    } @finally {
        [NSFileManager.defaultManager removeItemAtURL:root error:NULL];
    }
    return failures;
}
