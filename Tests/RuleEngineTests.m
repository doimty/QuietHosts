#import <Foundation/Foundation.h>
#import "../Shared/QHRuleEngine.h"
#include <string.h>
#include <stdio.h>

static NSUInteger failures;
static void Check(BOOL condition, NSString *label) {
    if (!condition) {
        failures++;
        NSLog(@"RuleEngineTests FAIL: %@", label);
    }
}
static NSData *UTF8(NSString *text) {
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}
static QHParseResult *Rules(NSString *text) {
    return QHParseRules(UTF8(text), NULL);
}
static NSMutableData *Numbered(NSUInteger count) {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i < count; i++) {
        char line[64];
        int n = snprintf(line, sizeof(line), "n%06lu.example\n", (unsigned long)i);
        [data appendBytes:line length:(NSUInteger)n];
    }
    return data;
}
static void Basic(void) {
    NSError *error = nil;
    QHParseResult *a = Rules(@"EXAMPLE.COM.\n0.0.0.0 example.com www.example.com\n::1 z.example\n");
    Check([a.domains isEqualToArray:@[ @"example.com", @"www.example.com", @"z.example" ]],
          @"ordered dedup, no www expansion");
    Check([a.statistics[@"accepted"] integerValue] == 4 && [a.statistics[@"duplicates"] integerValue] == 1,
          @"source counts");
    NSSet *allow = QHParseAllowlist(UTF8(@"# exact\n Example.Com.\nexample.com\n"), &error);
    Check(allow.count == 1 && error == nil, @"canonical allowlist duplicate");
    QHParseResult *b = Rules(@"z.example\na.example\n");
    QHCompiledRules *compiled = QHCompileDomains(@[ a, b ], allow, &error);
    NSString *expected = @"0.0.0.0 a.example\n::1 a.example\n0.0.0.0 www.example.com\n::1 "
                         @"www.example.com\n0.0.0.0 z.example\n::1 z.example\n";
    Check([compiled.hostsData isEqualToData:UTF8(expected)], @"deterministic paired hosts exact allow only");
    Check([compiled.statistics[@"unique"] integerValue] == 3 &&
              [compiled.statistics[@"duplicates"] integerValue] == 2 &&
              [compiled.statistics[@"excluded"] integerValue] == 1 &&
              [compiled.statistics[@"sourceCount"] integerValue] == 2 &&
              [compiled.statistics[@"bytes"] unsignedIntegerValue] == compiled.hostsData.length,
          @"compiled counts");
    Check([QHCompileDomains(@[ b, a ], allow, NULL).hostsData isEqualToData:compiled.hostsData],
          @"source order independent generation");
    NSUInteger count = 999;
    Check(QHValidateCompiledHosts(compiled.hostsData, &count, &error) && count == 3,
          @"independent validation");
    Check(QHValidateCompiledHosts([NSData data], &count, &error) && count == 0, @"empty validation");
    Check(QHCompileDomains(@[], [NSSet set], NULL).hostsData.length == 0, @"empty compilation");
    for (NSString *line in @[
             @"0.0.0.0 a.example", @"https://a.example", @"*.a.example", @"DOMAIN,a.example", @"localhost",
             @"1.2.3.4"
         ]) {
        NSString *text = [@"# comment\nvalid.example\n" stringByAppendingString:line];
        error = nil;
        Check(QHParseAllowlist(UTF8(text), &error) == nil && [error.userInfo[@"line"] integerValue] == 3,
              @"atomic invalid allowlist and line");
    }
    Check(QHCompileDomains(@[ a ], [NSSet setWithObject:@"EXAMPLE.COM"], &error) == nil,
          @"reject noncanonical programmatic allowlist");
    Check(QHCompileDomains(@[ a ], [NSSet setWithObject:@"*.example.com"], &error) == nil,
          @"reject programmatic wildcard");
    const unsigned char bad[] = "a.example\n#\xc0\xaf";
    Check(QHParseRules([NSData dataWithBytes:bad length:sizeof(bad) - 1], &error) == nil &&
              [error.userInfo[@"line"] integerValue] == 2,
          @"bad UTF8 whole input and line");
    const unsigned char nul[] = "a.example\n\0b.example";
    Check(QHParseRules([NSData dataWithBytes:nul length:sizeof(nul) - 1], &error) == nil, @"NUL whole input");
    QHParseResult *stats = Rules(@"# comment\n0.0.0.0 localhost bad_name a.example\n8.8.8.8 "
                                 @"redirect.example\nDOMAIN,x.example\nbad\n");
    Check([stats.statistics[@"local"] integerValue] == 1 &&
              [stats.statistics[@"redirects"] integerValue] == 1 &&
              [stats.statistics[@"invalidNames"] integerValue] == 2 &&
              [stats.statistics[@"invalidLines"] integerValue] == 0 &&
              [stats.statistics[@"unsupported"] integerValue] == 1 &&
              [stats.statistics[@"unique"] integerValue] == 1,
          @"distinct rejection counts");
}
static void InvalidDocuments(void) {
    NSArray *bad = @[
        @"0.0.0.0 a.example\n", @"::1 a.example\n0.0.0.0 a.example\n", @"0.0.0.0 A.example\n::1 A.example\n",
        @"0.0.0.0 a.example.\n::1 a.example.\n", @"0.0.0.0 a.example\n::1 b.example\n",
        @"0.0.0.0 a.example\r\n::1 a.example\r\n", @"0.0.0.0 a.example\n::1 a.example",
        @"0.0.0.0 localhost.localdomain\n::1 localhost.localdomain\n",
        @"127.0.0.1 a.example\n::1 a.example\n", @"# comment\n",
        @"0.0.0.0 a.example\n::1 a.example\n0.0.0.0 a.example\n::1 a.example\n",
        @"0.0.0.0 z.example\n::1 z.example\n0.0.0.0 a.example\n::1 a.example\n",
        @"0.0.0.0 a.example b.example\n::1 a.example b.example\n"
    ];
    for (NSString *text in bad) {
        NSUInteger count = 99;
        NSError *error = nil;
        Check(!QHValidateCompiledHosts(UTF8(text), &count, &error) && count == 0 && error != nil,
              @"reject noncanonical document");
    }
}
static void InputLimits(void) {
    NSMutableData *data = [NSMutableData dataWithLength:QHMaximumInputBytes];
    memset(data.mutableBytes, ' ', data.length);
    ((char *)data.mutableBytes)[0] = '#';
    QHParseResult *result = QHParseRules(data, NULL);
    Check(result != nil && result.domains.count == 0, @"exact 16MiB input");
    Check(QHCompileDomains(@[ result, result ], [NSSet set], NULL) != nil, @"exact 32MiB combined input");
    Check(QHCompileDomains(@[ result, result, Rules(@"#") ], [NSSet set], NULL) == nil,
          @"combined input one byte over");
    [data appendBytes:" " length:1];
    Check(QHParseRules(data, NULL) == nil, @"input one byte over");
    NSMutableArray *sources = [NSMutableArray array];
    for (NSUInteger i = 0; i < 33; i++) {
        [sources addObject:Rules(@"")];
    }
    Check(QHCompileDomains(sources, [NSSet set], NULL) == nil, @"33 sources refused");
    [sources removeLastObject];
    Check(QHCompileDomains(sources, [NSSet set], NULL) != nil, @"32 sources accepted");
}
static void DomainLimits(void) {
    NSMutableData *data = Numbered(QHMaximumDomains);
    QHParseResult *result = QHParseRules(data, NULL);
    Check(result.domains.count == QHMaximumDomains, @"exact 300000 domains, no 4096 cap");
    QHCompiledRules *compiled = QHCompileDomains(@[ result ], [NSSet set], NULL);
    NSUInteger count = 0;
    Check(compiled.domains.count == QHMaximumDomains &&
              QHValidateCompiledHosts(compiled.hostsData, &count, NULL) && count == QHMaximumDomains,
          @"300000 generation and independent validation");
    NSMutableData *tooMany = [compiled.hostsData mutableCopy];
    [tooMany appendData:UTF8(@"0.0.0.0 zzzz.example\n::1 zzzz.example\n")];
    Check(!QHValidateCompiledHosts(tooMany, &count, NULL) && count == 0,
          @"validator rejects 300001 canonical pairs");
    QHParseResult *extra = Rules(@"extra.example\n");
    Check(QHCompileDomains(@[ result, extra ], [NSSet setWithObject:@"extra.example"], NULL) == nil,
          @"merged cap enforced before exclusions");
    [data appendData:UTF8(@"n000000.example\n")];
    Check(QHParseRules(data, NULL).domains.count == QHMaximumDomains, @"duplicate at cap allowed");
    [data appendData:UTF8(@"extra.example\n")];
    Check(QHParseRules(data, NULL) == nil, @"300001 unique rejects whole source");
}
static void OutputLimits(void) {
    // 253-byte valid names: 65000*254 input <16MiB, 65000*520 output >32MiB.
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i < 65000; i++) {
        char line[255];
        memset(line, 'a', 253);
        char prefix[8];
        snprintf(prefix, sizeof(prefix), "%06lu", (unsigned long)i);
        memcpy(line, prefix, 6);
        line[63] = '.';
        line[127] = '.';
        line[191] = '.';
        line[253] = '\n';
        [data appendBytes:line length:254];
    }
    QHParseResult *result = QHParseRules(data, NULL);
    Check(result.domains.count == 65000, @"long-name input under source cap");
    Check(QHCompileDomains(@[ result ], [NSSet set], NULL) == nil,
          @"output limit checked before allocating output");
    // Exact output boundary using 64527*520 + 264 + 128 = 33554432.
    NSMutableSet *allow =
        [NSMutableSet setWithArray:[result.domains subarrayWithRange:NSMakeRange(64527, 473)]];
    NSString *n125 = [[@"b" stringByPaddingToLength:62 withString:@"b" startingAtIndex:0]
        stringByAppendingFormat:@".%@", [@"b" stringByPaddingToLength:62 withString:@"b" startingAtIndex:0]];
    NSString *n57 = [@"c." stringByPaddingToLength:57 withString:@"c" startingAtIndex:0];
    QHParseResult *extra = Rules([NSString stringWithFormat:@"%@\n%@\n", n125, n57]);
    QHCompiledRules *exact = QHCompileDomains(@[ result, extra ], allow, NULL);
    Check(exact.hostsData.length == QHMaximumDocumentBytes, @"exact 32MiB emitted block");
    NSUInteger count = 0;
    Check(QHValidateCompiledHosts(exact.hostsData, &count, NULL) && count == 64529,
          @"validator accepts 32MiB unlike import parser");
    QHParseResult *oneMore = Rules(@"d.example\n");
    Check(QHCompileDomains(@[ result, extra, oneMore ], allow, NULL) == nil,
          @"output over 32MiB rejects whole compilation");
    NSMutableData *over = [exact.hostsData mutableCopy];
    [over appendBytes:"\n" length:1];
    Check(!QHValidateCompiledHosts(over, NULL, NULL), @"validator one byte over cap");
}
NSUInteger RunRuleEngineTests(void) {
    failures = 0;
    @autoreleasepool {
        Basic();
        InvalidDocuments();
    }
    @autoreleasepool {
        InputLimits();
    }
    @autoreleasepool {
        DomainLimits();
    }
    @autoreleasepool {
        OutputLimits();
    }
    NSLog(@"RuleEngineTests: %lu failures", (unsigned long)failures);
    return failures;
}
