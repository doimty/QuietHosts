/* Adapted from NetShield2. Copyright (c) 2026 EolnMsuk.
 * SPDX-License-Identifier: MIT. See LICENSE and third-party notices. */
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "../QHDownload.h"
#import "../../Shared/QHRuleEngine.h"
#include <stdlib.h>

#if !defined(QH_TESTING) || !QH_TESTING
#error HostsDownloadTests requires QH_TESTING=1 for isolated protocol injection.
#endif

static NSUInteger checks;
#define CHECK(...)                                                                                           \
    do {                                                                                                     \
        checks++;                                                                                            \
        if (!(__VA_ARGS__)) {                                                                                \
            NSLog(@"FAIL %s:%d: %s", __FILE__, __LINE__, #__VA_ARGS__);                                      \
            abort();                                                                                         \
        }                                                                                                    \
    } while (0)

@interface QHDownloadFixtureScript : NSObject
@property(nonatomic) NSInteger status;
@property(nonatomic, copy) NSString *mime;
@property(nonatomic, copy) NSString *length;
@property(nonatomic, copy) NSArray<NSData *> *chunks;
@property(nonatomic, strong) NSError *error;
@property(nonatomic) BOOL stall;
@property(nonatomic) BOOL nonHTTP;
@property(nonatomic) NSUInteger loads;
@property(nonatomic) NSUInteger stops;
@property(nonatomic, copy) NSURLRequest *request;
@end
@implementation QHDownloadFixtureScript
- (instancetype)init {
    if ((self = [super init])) {
        _status = 200;
        _mime = @"text/plain";
        _chunks = @[];
    }
    return self;
}
@end

static QHDownloadFixtureScript *currentScript;
@interface QHDownloadFixtureProtocol : NSURLProtocol
@property(nonatomic, strong) QHDownloadFixtureScript *script;
@end
@implementation QHDownloadFixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return YES;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}
- (void)startLoading {
    @synchronized(QHDownloadFixtureProtocol.class) {
        self.script = currentScript;
    }
    QHDownloadFixtureScript *script = self.script;
    // A missing script is a test bug, never a reason to fall through to networking.
    if (!script) {
        abort();
    }
    @synchronized(script) {
        script.loads++;
        script.request = self.request;
    }
    if (script.stall) {
        return;
    }
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (script.mime) {
        headers[@"Content-Type"] = script.mime;
    }
    if (script.length) {
        headers[@"Content-Length"] = script.length;
    }
    NSURLResponse *response;
    if (script.nonHTTP) {
        response = [[NSURLResponse alloc] initWithURL:self.request.URL
                                             MIMEType:script.mime
                                expectedContentLength:-1
                                     textEncodingName:nil];
    } else {
        response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                               statusCode:script.status
                                              HTTPVersion:@"HTTP/1.1"
                                             headerFields:headers];
    }
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    for (NSData *chunk in script.chunks) {
        [self.client URLProtocol:self didLoadData:chunk];
    }
    if (script.error) {
        [self.client URLProtocol:self didFailWithError:script.error];
    } else {
        [self.client URLProtocolDidFinishLoading:self];
    }
}
- (void)stopLoading {
    QHDownloadFixtureScript *script = self.script;
    @synchronized(script) {
        script.stops++;
    }
}
@end

@interface QHDownloadFixtureResult : NSObject
@property(nonatomic) NSUInteger calls;
@property(nonatomic) BOOL returned;
@property(nonatomic, copy) NSData *data;
@property(nonatomic, strong) NSError *error;
@end
@implementation QHDownloadFixtureResult
@end

// Never block the main queue with a semaphore/group while waiting for callbacks.
static void PumpUntil(BOOL (^predicate)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!predicate() && deadline.timeIntervalSinceNow > 0) {
        @autoreleasepool {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                   beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    }
    CHECK(predicate());
}
static void Drain(void) {
    // Multiple barriers flush completion and invalidation turns without sleeping.
    for (NSUInteger i = 0; i < 4; i++) {
        __block BOOL reached = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            reached = YES;
        });
        PumpUntil(^BOOL {
            return reached;
        });
    }
}
static void AssertError(NSError *error, QHDownloadErrorCode code) {
    CHECK([error.domain isEqualToString:QHDownloadErrorDomain]);
    CHECK(error.code == code);
    CHECK(error.localizedDescription.length > 0);
    CHECK(error.userInfo.count == 1 && error.userInfo[NSLocalizedDescriptionKey] != nil);
    CHECK([error.localizedDescription rangeOfString:@"query-secret"].location == NSNotFound);
}
static QHDownload *Start(QHDownloadFixtureScript *script, NSString *url, QHDownloadFixtureResult *result) {
    @synchronized(QHDownloadFixtureProtocol.class) {
        currentScript = script;
    }
    QHDownload *download =
        [QHDownload downloadForTestingWithProtocolClasses:@[ QHDownloadFixtureProtocol.class ]];
    [download startURLString:url
                  completion:^(NSData *data, NSError *error) {
                      CHECK(NSThread.isMainThread);
                      CHECK(result.returned);
                      result.calls++;
                      CHECK(result.calls == 1);
                      CHECK((data != nil) != (error != nil));
                      result.data = data;
                      result.error = error;
                  }];
    CHECK(result.calls == 0);
    result.returned = YES;
    return download;
}
static QHDownloadFixtureResult *Run(QHDownloadFixtureScript *script, QHDownloadErrorCode expectedError) {
    QHDownloadFixtureResult *result = [QHDownloadFixtureResult new];
    QHDownload *download = Start(script, @"https://hosts.test/raw?token=query-secret", result);
    PumpUntil(^BOOL {
        return result.calls == 1;
    });
    if (expectedError) {
        AssertError(result.error, expectedError);
        CHECK(result.data == nil);
    } else {
        CHECK(result.error == nil && result.data.length > 0);
    }
    [download cancel];
    [download cancel];
    Drain();
    CHECK(result.calls == 1);
    return result;
}
static void TestURLValidation(void) {
    NSArray<NSString *> *valid = @[
        @"https://example.test/hosts", @" HTTPS://EXAMPLE.TEST/raw?token=query-secret \n",
        @"https://example.test:1/", @"https://example.test:65535/", @"https://example.test:00443/",
        @"https://example.test./", @"https://127.0.0.1/", @"https://[::1]:443/", @"https://[2001:db8::1]/",
        @"https://xn--fsqu00a.xn--0zwm56d/", @"https://localhost/raw%20hosts?q=%23ok"
    ];
    for (NSString *text in valid) {
        NSError *error = [NSError errorWithDomain:@"sentinel" code:1 userInfo:nil];
        CHECK([QHDownload validatedURLFromString:text error:&error] != nil);
        CHECK(error == nil);
    }
    NSArray<NSString *> *invalid = @[
        @"",
        @" \n\t",
        @"http://example.test/",
        @"file:///tmp/hosts",
        @"data:text/plain,hosts",
        @"https:/example.test",
        @"//example.test/",
        @"https://",
        @"https:///hosts",
        @"https://?a=b",
        @"https://user@example.test/",
        @"https://user:pass@example.test/",
        @"https://@example.test/",
        @"https://:pass@example.test/",
        @"https://example.test/#fragment",
        @"https://example.test/#",
        @"https://example.test:0/",
        @"https://example.test:65536/",
        @"https://example.test:-1/",
        @"https://example.test:+443/",
        @"https://example.test:/",
        @"https://example.test:abc/",
        @"https://example.test:999999999999999999999/",
        @"https://example.test:443:80/",
        @"https://bad host.test/",
        @"https://example.test/a b",
        @"https://example.test/\nraw",
        @"https://example.test\\@other.test/",
        @"https://example.test/%",
        @"https://example.test/%xz",
        @"https://%65xample.test/",
        @"https://-bad.test/",
        @"https://bad-.test/",
        @"https://bad_.test/",
        @"https://bad..test/",
        @"https://.test/",
        @"https://999.0.0.1/",
        @"https://127.1/",
        @"https://[bad]/",
        @"https://[::1/",
        @"https://::1/",
        @"https://[::1]suffix/",
        @"https://[fe80::1%25en0]/"
    ];
    for (NSString *text in invalid) {
        NSError *error = nil;
        CHECK([QHDownload validatedURLFromString:text error:&error] == nil);
        AssertError(error, QHDownloadInvalidURL);
        CHECK([QHDownload validatedURLFromString:text error:NULL] == nil);
    }
    NSString *label = [@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    CHECK([QHDownload validatedURLFromString:[NSString stringWithFormat:@"https://%@.test/", label]
                                       error:NULL] == nil);
    NSURL *trimmed = [QHDownload validatedURLFromString:@" \nhttps://example.test/raw?q=%23 \t" error:NULL];
    CHECK([trimmed.absoluteString isEqualToString:@"https://example.test/raw?q=%23"]);
}

static void TestResponsesAndLimits(void) {
    NSData *first = [@"# hosts\n0.0.0.0 " dataUsingEncoding:NSUTF8StringEncoding];
    NSData *last = [@"ads.test\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *expected = [first mutableCopy];
    [expected appendData:last];
    QHDownloadFixtureScript *script = [QHDownloadFixtureScript new];
    script.chunks = @[ first, last ];
    script.length = [NSString stringWithFormat:@"%lu", (unsigned long)expected.length];
    QHDownloadFixtureResult *result = Run(script, 0);
    CHECK([result.data isEqualToData:expected]);
    CHECK(![result.data isKindOfClass:NSMutableData.class]);
    for (NSNumber *status in @[ @204, @206, @301, @400, @403, @404, @500 ]) {
        script = [QHDownloadFixtureScript new];
        script.status = status.integerValue;
        script.chunks = @[ first ];
        Run(script, QHDownloadHTTPStatus);
    }
    for (NSString *mime in @[ @"text/html", @"Text/HTML; charset=UTF-8", @"application/xhtml+xml" ]) {
        script = [QHDownloadFixtureScript new];
        script.mime = mime;
        script.chunks = @[ first ];
        Run(script, QHDownloadHTML);
    }
    for (id mime in @[ @"application/octet-stream", NSNull.null ]) {
        script = [QHDownloadFixtureScript new];
        script.mime = mime == NSNull.null ? nil : mime;
        script.chunks = @[ first ];
        CHECK([Run(script, 0).data isEqualToData:first]);
    }
    script = [QHDownloadFixtureScript new];
    script.nonHTTP = YES;
    script.chunks = @[ first ];
    Run(script, QHDownloadInvalidResponse);
    script = [QHDownloadFixtureScript new];
    Run(script, QHDownloadEmpty);
    script = [QHDownloadFixtureScript new];
    script.length = @"0";
    Run(script, QHDownloadEmpty);
    script = [QHDownloadFixtureScript new];
    script.chunks = @[ first ];
    script.length = [NSString stringWithFormat:@"%lu", (unsigned long)QHMaximumInputBytes + 1];
    Run(script, QHDownloadTooLarge);

    NSData *half = [NSData dataWithBytesNoCopy:calloc(1, QHMaximumInputBytes / 2)
                                        length:QHMaximumInputBytes / 2
                                  freeWhenDone:YES];
    NSData *one = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    // Unknown-length streaming exactly at the inclusive decoded-byte limit.
    script = [QHDownloadFixtureScript new];
    script.chunks = @[ half, half ];
    CHECK(Run(script, 0).data.length == QHMaximumInputBytes);
    script = [QHDownloadFixtureScript new];
    script.chunks = @[ half, half ];
    script.length = [NSString stringWithFormat:@"%lu", (unsigned long)QHMaximumInputBytes];
    CHECK(Run(script, 0).data.length == QHMaximumInputBytes);
    // Unknown and misleading small Content-Length cannot bypass accumulated cap.
    for (id length in @[ NSNull.null, @"1" ]) {
        script = [QHDownloadFixtureScript new];
        script.chunks = @[ half, half, one ];
        script.length = length == NSNull.null ? nil : length;
        Run(script, QHDownloadTooLarge);
    }
    script = [QHDownloadFixtureScript new];
    script.chunks = @[ [NSMutableData dataWithLength:QHMaximumInputBytes + 1] ];
    Run(script, QHDownloadTooLarge);
    script = [QHDownloadFixtureScript new];
    script.chunks = @[ first ];
    script.error =
        [NSError errorWithDomain:NSURLErrorDomain
                            code:NSURLErrorServerCertificateUntrusted
                        userInfo:@{
                            NSLocalizedDescriptionKey : @"query-secret",
                            NSURLErrorFailingURLStringErrorKey : @"https://hosts.test/?token=query-secret"
                        }];
    Run(script, QHDownloadNetwork);
}

static NSUInteger LoadCount(QHDownloadFixtureScript *script) {
    @synchronized(script) {
        return script.loads;
    }
}
static NSUInteger StopCount(QHDownloadFixtureScript *script) {
    @synchronized(script) {
        return script.stops;
    }
}
static QHDownload *StartStalled(QHDownloadFixtureScript **outScript, QHDownloadFixtureResult *result) {
    QHDownloadFixtureScript *script = [QHDownloadFixtureScript new];
    script.stall = YES;
    QHDownload *download = Start(script, @"https://hosts.test/raw?token=query-secret", result);
    PumpUntil(^BOOL {
        return LoadCount(script) == 1;
    });
    *outScript = script;
    return download;
}
static void TestConfigurationAndCancel(void) {
    QHDownloadFixtureScript *script = nil;
    QHDownloadFixtureResult *result = [QHDownloadFixtureResult new];
    QHDownload *download = StartStalled(&script, result);
    // Read-only private-state inspection; no production configuration override.
    NSURLSession *session = [download valueForKey:@"session"];
    NSURLSessionConfiguration *config = session.configuration;
    CHECK(session.delegateQueue == NSOperationQueue.mainQueue);
    CHECK(!config.HTTPShouldSetCookies);
    CHECK(config.HTTPCookieStorage == nil && config.URLCredentialStorage == nil && config.URLCache == nil);
    CHECK(config.requestCachePolicy == NSURLRequestReloadIgnoringLocalCacheData);
    CHECK(config.timeoutIntervalForRequest == 30 && config.timeoutIntervalForResource == 60);
    if (@available(iOS 11.0, macOS 10.13, *)) {
        CHECK(!config.waitsForConnectivity);
    }
    @synchronized(script) {
        CHECK(!script.request.HTTPShouldHandleCookies);
        CHECK(script.request.timeoutInterval == 30);
    }
    [download cancel];
    [download cancel];
    CHECK(result.calls == 0);
    PumpUntil(^BOOL {
        return result.calls == 1 && StopCount(script) > 0;
    });
    AssertError(result.error, QHDownloadCancelled);
    Drain();
    CHECK(result.calls == 1);

    QHDownload *idle =
        [QHDownload downloadForTestingWithProtocolClasses:@[ QHDownloadFixtureProtocol.class ]];
    [idle cancel];
    [idle cancel];
    QHDownloadFixtureScript *success = [QHDownloadFixtureScript new];
    success.chunks = @[ [NSData dataWithBytes:"x" length:1] ];
    @synchronized(QHDownloadFixtureProtocol.class) {
        currentScript = success;
    }
    __block NSUInteger calls = 0;
    [idle startURLString:@"https://hosts.test/"
              completion:^(NSData *data, NSError *error) {
                  CHECK(NSThread.isMainThread && data.length == 1 && error == nil);
                  calls++;
              }];
    CHECK(calls == 0);
    PumpUntil(^BOOL {
        return calls == 1;
    });
    [idle cancel];
    Drain();
    CHECK(calls == 1);
}

static void TestRedirects(void) {
    QHDownloadFixtureScript *script = nil;
    QHDownloadFixtureResult *result = [QHDownloadFixtureResult new];
    QHDownload *download = StartStalled(&script, result);
    for (NSUInteger hop = 1; hop <= 6; hop++) {
        __block NSUInteger decisions = 0;
        NSURL *url =
            [NSURL URLWithString:[NSString stringWithFormat:@"https://next%lu.test/raw", (unsigned long)hop]];
        [download
            redirectForTestingToURL:url
                         completion:^(NSURLRequest *request) {
                             CHECK(NSThread.isMainThread);
                             decisions++;
                             if (hop <= 5) {
                                 CHECK([request.URL isEqual:url]);
                                 CHECK([request.HTTPMethod isEqualToString:@"GET"]);
                                 CHECK(!request.HTTPShouldHandleCookies && request.timeoutInterval == 30);
                                 CHECK([request valueForHTTPHeaderField:@"Authorization"] == nil);
                                 CHECK([request valueForHTTPHeaderField:@"Cookie"] == nil);
                             } else {
                                 CHECK(request == nil);
                             }
                         }];
        CHECK(decisions == 1);
        CHECK(result.calls == 0);
    }
    PumpUntil(^BOOL {
        return result.calls == 1 && StopCount(script) > 0;
    });
    AssertError(result.error, QHDownloadTooManyRedirects);
    CHECK(LoadCount(script) == 1); // No redirect test can escape to a network connection.
    __block NSUInteger lateDecisions = 0;
    [download redirectForTestingToURL:[NSURL URLWithString:@"https://late.test/"]
                           completion:^(NSURLRequest *request) {
                               CHECK(request == nil);
                               lateDecisions++;
                           }];
    CHECK(lateDecisions == 1);
    [download cancel];
    Drain();
    CHECK(result.calls == 1);
    for (NSString *target in @[
             @"http://hosts.test/raw", @"file:///tmp/hosts", @"https://user:pass@hosts.test/",
             @"https://hosts.test/#fragment", @"https://hosts.test:65536/"
         ]) {
        result = [QHDownloadFixtureResult new];
        download = StartStalled(&script, result);
        __block NSUInteger decisions = 0;
        [download redirectForTestingToURL:[NSURL URLWithString:target]
                               completion:^(NSURLRequest *request) {
                                   CHECK(request == nil);
                                   decisions++;
                               }];
        CHECK(decisions == 1 && result.calls == 0);
        PumpUntil(^BOOL {
            return result.calls == 1 && StopCount(script) > 0;
        });
        AssertError(result.error, QHDownloadInvalidURL);
        CHECK(LoadCount(script) == 1);
        [download cancel];
        Drain();
        CHECK(result.calls == 1);
    }
}

static void TestEarlyFailuresAndReuse(void) {
    QHDownloadFixtureScript *script = [QHDownloadFixtureScript new];
    QHDownloadFixtureResult *result = [QHDownloadFixtureResult new];
    QHDownload *download = Start(script, @"http://hosts.test/?token=query-secret", result);
    [download cancel];
    PumpUntil(^BOOL {
        return result.calls == 1;
    });
    AssertError(result.error, QHDownloadInvalidURL);
    CHECK(LoadCount(script) == 0);
    Drain();
    CHECK(result.calls == 1);

    result = [QHDownloadFixtureResult new];
    download = StartStalled(&script, result);
    __block NSUInteger secondCalls = 0;
    [download startURLString:@"https://hosts.test/another"
                  completion:^(NSData *data, NSError *error) {
                      CHECK(NSThread.isMainThread && data == nil);
                      AssertError(error, QHDownloadAlreadyStarted);
                      secondCalls++;
                  }];
    CHECK(secondCalls == 0 && result.calls == 0);
    PumpUntil(^BOOL {
        return secondCalls == 1;
    });
    CHECK(result.calls == 0 && LoadCount(script) == 1);
    [download cancel];
    PumpUntil(^BOOL {
        return result.calls == 1 && StopCount(script) > 0;
    });
    AssertError(result.error, QHDownloadCancelled);
    Drain();
    CHECK(result.calls == 1 && secondCalls == 1);
}

static void TestLifetimeAndImmediateCancel(void) {
    // The service does not need to be retained by its caller to deliver cancellation.
    // Inspect weak references in an inner pool so KVC temporaries cannot keep them alive.
    QHDownloadFixtureScript *script = nil;
    QHDownloadFixtureResult *result = [QHDownloadFixtureResult new];
    __weak QHDownload *weakDownload;
    __weak NSURLSession *weakSession;
    __weak id weakDelegate;
    @autoreleasepool {
        QHDownload *download = StartStalled(&script, result);
        weakDownload = download;
        weakSession = [download valueForKey:@"session"];
        weakDelegate = [download valueForKey:@"delegate"];
        download = nil;
    }
    CHECK(weakDownload == nil);
    PumpUntil(^BOOL {
        return result.calls == 1 && StopCount(script) > 0;
    });
    AssertError(result.error, QHDownloadCancelled);
    PumpUntil(^BOOL {
        return weakSession == nil && weakDelegate == nil;
    });
    CHECK(result.calls == 1);

    // Cancellation before the first delegate event must also complete only once.
    script = [QHDownloadFixtureScript new];
    script.stall = YES;
    result = [QHDownloadFixtureResult new];
    @autoreleasepool {
        QHDownload *download = Start(script, @"https://hosts.test/raw", result);
        weakSession = [download valueForKey:@"session"];
        weakDelegate = [download valueForKey:@"delegate"];
        [download cancel];
        [download cancel];
        CHECK(result.calls == 0);
        download = nil;
    }
    PumpUntil(^BOOL {
        return result.calls == 1;
    });
    AssertError(result.error, QHDownloadCancelled);
    PumpUntil(^BOOL {
        return weakSession == nil && weakDelegate == nil;
    });
    Drain();
    CHECK(result.calls == 1);

    // Both success and failure invalidate their session and release the delegate.
    for (NSNumber *fail in @[ @NO, @YES ]) {
        result = [QHDownloadFixtureResult new];
        script = [QHDownloadFixtureScript new];
        script.chunks = @[ [NSData dataWithBytes:"x" length:1] ];
        script.status = fail.boolValue ? 404 : 200;
        @autoreleasepool {
            QHDownload *download = Start(script, @"https://hosts.test/raw", result);
            weakSession = [download valueForKey:@"session"];
            weakDelegate = [download valueForKey:@"delegate"];
            PumpUntil(^BOOL {
                return result.calls == 1;
            });
            if (fail.boolValue) {
                AssertError(result.error, QHDownloadHTTPStatus);
            } else {
                CHECK(result.data.length == 1 && result.error == nil);
            }
            [download cancel];
            download = nil;
        }
        PumpUntil(^BOOL {
            return weakSession == nil && weakDelegate == nil;
        });
        Drain();
        CHECK(result.calls == 1);
    }
}

NSUInteger RunDownloadTests(void) {
    CHECK(NSThread.isMainThread);
    TestURLValidation();
    TestResponsesAndLimits();
    TestConfigurationAndCancel();
    TestRedirects();
    TestEarlyFailuresAndReuse();
    TestLifetimeAndImmediateCancel();
    @synchronized(QHDownloadFixtureProtocol.class) {
        currentScript = nil;
    }
    return checks;
}
