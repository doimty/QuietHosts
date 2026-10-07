#import "QHRuleEngine.h"
#import "QHParser.h"
#import "QHLocalization.h"
#include <string.h>

const NSUInteger QHMaximumInputBytes = 16u * 1024u * 1024u;
const NSUInteger QHMaximumDocumentBytes = 32u * 1024u * 1024u;
const NSUInteger QHMaximumDomains = 300000u;

@interface QHParseResult ()
- (instancetype)initWithDomains:(NSArray<NSString *> *)domains statistics:(NSDictionary *)statistics;
@end
@implementation QHParseResult
- (instancetype)initWithDomains:(NSArray<NSString *> *)domains statistics:(NSDictionary *)statistics {
    if ((self = [super init])) {
        _domains = [domains copy];
        _statistics = [statistics copy];
    }
    return self;
}
@end
@interface QHCompiledRules ()
- (instancetype)initWithDomains:(NSArray<NSString *> *)domains
                           data:(NSData *)data
                     statistics:(NSDictionary *)statistics;
@end
@implementation QHCompiledRules
- (instancetype)initWithDomains:(NSArray<NSString *> *)domains
                           data:(NSData *)data
                     statistics:(NSDictionary *)statistics {
    if ((self = [super init])) {
        _domains = [domains copy];
        _hostsData = [data copy];
        _statistics = [statistics copy];
    }
    return self;
}
@end
static void Fail(NSError **error, NSInteger code, NSString *message, NSUInteger line) {
    if (error) {
        if (line) {
            message = [NSString stringWithFormat:QHL(@"%@ (line %lu)"), message, (unsigned long)line];
        }
        NSMutableDictionary *info = [@{NSLocalizedDescriptionKey : message} mutableCopy];
        if (line) {
            info[@"line"] = @(line);
        }
        *error = [NSError errorWithDomain:@"QuietHosts.RuleEngine" code:code userInfo:info];
    }
}
typedef struct {
    __unsafe_unretained NSMutableOrderedSet<NSString *> *names;
    NSUInteger duplicates;
    BOOL overflow;
} Collector;
static bool Collect(const char *domain, void *context) {
    Collector *c = context;
    @autoreleasepool {
        NSString *name = [[NSString alloc] initWithUTF8String:domain];
        if ([c->names containsObject:name]) {
            c->duplicates++;
            return true;
        }
        if (c->names.count >= QHMaximumDomains) {
            c->overflow = YES;
            return false;
        }
        [c->names addObject:name];
        return true;
    }
}
static QHParseResult *Parse(NSData *data, BOOL allowlist, NSError **error) {
    if (error) {
        *error = nil;
    }
    if (![data isKindOfClass:NSData.class]) {
        Fail(error, 1, QHL(@"Rule input must be data."), 0);
        return nil;
    }
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    Collector collector = {names, 0, NO};
    QHParserStats stats;
    QHParseStatus status = QHParserParse(data.bytes, data.length, allowlist, Collect, &collector, &stats);
    if (status != QHParseOK) {
        NSString *message;
        if (status == QHParseTooLarge) {
            message = QHL(@"Each rule input must be at most 16 MiB.");
        } else if (status == QHParseInvalidEncoding) {
            message = QHL(@"Rules must be valid UTF-8 without NUL or control characters.");
        } else if (status == QHParseInvalidAllowlist) {
            message = QHL(@"Allowlist contains an invalid line; use one exact domain per line.");
        } else {
            message = QHL(@"Rules exceed the limit of 300000 unique domains.");
        }
        Fail(error, status + 10, message, stats.firstRejectedLine);
        return nil;
    }
    NSDictionary *counts = @{
        @"bytes" : @(data.length),
        @"lines" : @(stats.lines),
        @"accepted" : @(stats.acceptedNames),
        @"unique" : @(names.count),
        @"duplicates" : @(collector.duplicates),
        @"redirects" : @(stats.redirectLines),
        @"local" : @(stats.localNames),
        @"invalid" : @(stats.invalidLines + stats.invalidNames),
        @"unsupported" : @(stats.unsupported),
        @"invalidLines" : @(stats.invalidLines),
        @"invalidNames" : @(stats.invalidNames),
        @"ignoredLines" : @(stats.ignoredLines)
    };
    return [[QHParseResult alloc] initWithDomains:names.array statistics:counts];
}
QHParseResult *QHParseRules(NSData *data, NSError **error) {
    return Parse(data, NO, error);
}
NSSet<NSString *> *QHParseAllowlist(NSData *data, NSError **error) {
    QHParseResult *result = Parse(data, YES, error);
    return result ? [NSSet setWithArray:result.domains] : nil;
}
static BOOL ExactName(NSString *name) {
    if (![name isKindOfClass:NSString.class]) {
        return NO;
    }
    const char *text = name.UTF8String;
    if (!text) {
        return NO;
    }
    size_t n = strlen(text);
    if (n != [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) {
        return NO;
    }
    char canonical[254];
    return QHCanonicalDomain((const unsigned char *)text, n, canonical) && strcmp(text, canonical) == 0 &&
           !QHLocalDomain(canonical);
}
QHCompiledRules *QHCompileDomains(NSArray<QHParseResult *> *sources, NSSet<NSString *> *allow,
                                  NSError **error) {
    if (error) {
        *error = nil;
    }
    if (![sources isKindOfClass:NSArray.class] || sources.count > 32 || ![allow isKindOfClass:NSSet.class]) {
        Fail(error, 30, QHL(@"Use at most 32 rule sources and a valid exact allowlist."), 0);
        return nil;
    }
    for (NSString *name in allow) {
        BOOL valid;
        @autoreleasepool {
            valid = ExactName(name);
        }
        if (!valid) {
            Fail(error, 31, QHL(@"Allowlist must contain canonical exact domains only."), 0);
            return nil;
        }
    }
    NSMutableSet<NSString *> *merged = [NSMutableSet set];
    NSUInteger inputBytes = 0, duplicates = 0;
    for (QHParseResult *source in sources) {
        if (![source isKindOfClass:QHParseResult.class]) {
            Fail(error, 32, QHL(@"A rule source is invalid."), 0);
            return nil;
        }
        NSUInteger bytes = [source.statistics[@"bytes"] unsignedIntegerValue];
        if (bytes > QHMaximumInputBytes || bytes > QHMaximumDocumentBytes - inputBytes) {
            Fail(error, 33, QHL(@"Combined rule inputs must be at most 32 MiB."), 0);
            return nil;
        }
        inputBytes += bytes;
        duplicates += [source.statistics[@"duplicates"] unsignedIntegerValue];
        for (NSString *name in source.domains) {
            BOOL valid;
            @autoreleasepool {
                valid = ExactName(name);
            }
            if (!valid) {
                Fail(error, 32, QHL(@"A rule source is invalid."), 0);
                return nil;
            }
            if ([merged containsObject:name]) {
                duplicates++;
                continue;
            }
            if (merged.count >= QHMaximumDomains) {
                Fail(error, 34, QHL(@"Rules exceed the limit of 300000 unique domains."), 0);
                return nil;
            }
            [merged addObject:name];
        }
    }
    NSUInteger before = merged.count;
    [merged minusSet:allow];
    NSUInteger excluded = before - merged.count;
    NSArray<NSString *> *domains =
        [[merged allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
            return [left compare:right options:NSLiteralSearch];
        }];
    NSUInteger emitted = 0;
    for (NSString *name in domains) {
        NSUInteger size = 14 + 2 * name.length; // 0.0.0.0 SPACE name LF ::1 SPACE name LF
        if (size > QHMaximumDocumentBytes - emitted) {
            Fail(error, 35, QHL(@"Generated hosts records must be at most 32 MiB."), 0);
            return nil;
        }
        emitted += size;
    }
    NSMutableData *output = [NSMutableData dataWithCapacity:emitted];
    for (NSString *name in domains) {
        @autoreleasepool {
            const char *text = name.UTF8String;
            NSUInteger length = name.length;
            [output appendBytes:"0.0.0.0 " length:8];
            [output appendBytes:text length:length];
            [output appendBytes:"\n::1 " length:5];
            [output appendBytes:text length:length];
            [output appendBytes:"\n" length:1];
        }
    }
    return [[QHCompiledRules alloc] initWithDomains:domains
                                               data:output
                                         statistics:@{
                                             @"unique" : @(domains.count),
                                             @"duplicates" : @(duplicates),
                                             @"excluded" : @(excluded),
                                             @"bytes" : @(output.length),
                                             @"sourceCount" : @(sources.count)
                                         }];
}

BOOL QHValidateCompiledHosts(NSData *data, NSUInteger *count, NSError **error) {
    if (error) {
        *error = nil;
    }
    if (count) {
        *count = 0;
    }
    if (![data isKindOfClass:NSData.class] || data.length > QHMaximumDocumentBytes) {
        Fail(error, 40, QHL(@"Generated hosts records must be at most 32 MiB."), 0);
        return NO;
    }
    const unsigned char *p = data.bytes;
    size_t length = data.length, cursor = 0;
    NSUInteger total = 0;
    char previous[254] = {0};
    while (cursor < length) {
        if (length - cursor < 8 || memcmp(p + cursor, "0.0.0.0 ", 8)) {
            goto invalid;
        }
        cursor += 8;
        size_t start = cursor;
        while (cursor < length && p[cursor] != '\n' && cursor - start <= 253) {
            cursor++;
        }
        size_t n = cursor - start;
        char domain[254];
        if (cursor == length || p[cursor] != '\n' || !QHCanonicalDomain(p + start, n, domain) ||
            strlen(domain) != n || memcmp(domain, p + start, n) || QHLocalDomain(domain) ||
            strcmp(previous, domain) >= 0) {
            goto invalid;
        }
        cursor++;
        if (length - cursor < n + 5 || memcmp(p + cursor, "::1 ", 4) || memcmp(p + cursor + 4, domain, n) ||
            p[cursor + 4 + n] != '\n') {
            goto invalid;
        }
        cursor += n + 5;
        if (++total > QHMaximumDomains) {
            goto invalid;
        }
        memcpy(previous, domain, n + 1);
    }
    if (count) {
        *count = total;
    }
    return YES;
invalid:
    Fail(error, 41, QHL(@"Hosts records are not sorted unique canonical IPv4 and IPv6 pairs."), 0);
    return NO;
}
