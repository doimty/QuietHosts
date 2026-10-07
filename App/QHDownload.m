/* Adapted from NetShield2. Copyright (c) 2026 EolnMsuk.
 * SPDX-License-Identifier: MIT. See LICENSE and third-party notices. */
#import "QHDownload.h"
#import "../Shared/QHRuleEngine.h"
#import "../Shared/QHLocalization.h"
#import <dispatch/dispatch.h>
#include "../Shared/QHStrictAddress.h"

NSString *const QHDownloadErrorDomain = @"QHDownloadErrorDomain";

static NSError *DownloadError(QHDownloadErrorCode code, NSString *message) {
    // Never attach the URL, response, or an underlying error: queries may be secret.
    return [NSError errorWithDomain:QHDownloadErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}
static NSError *CancelledError(void) {
    return DownloadError(QHDownloadCancelled, QHL(@"The Hosts download was cancelled."));
}
static NSError *URLError(void) {
    return DownloadError(QHDownloadInvalidURL,
                         QHL(@"Enter a valid HTTPS URL without a username, password, or fragment."));
}
static BOOL IsHex(unichar c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}
static BOOL ValidHost(NSString *host, BOOL ipv6) {
    unsigned char address[16];
    if (ipv6) {
        return QHStrictInetPton(AF_INET6, host.UTF8String, address) == 1;
    }
    if ([host hasSuffix:@"."]) {
        host = [host substringToIndex:host.length - 1];
    }
    if (host.length == 0 || host.length > 253) {
        return NO;
    }
    BOOL numeric = YES;
    for (NSUInteger i = 0; i < host.length; i++) {
        unichar c = [host characterAtIndex:i];
        if (!(c == '.' || (c >= '0' && c <= '9'))) {
            numeric = NO;
        }
    }
    if (numeric && [host containsString:@"."]) {
        return QHStrictInetPton(AF_INET, host.UTF8String, address) == 1;
    }
    for (NSString *label in [host componentsSeparatedByString:@"."]) {
        if (label.length == 0 || label.length > 63 || [label hasPrefix:@"-"] || [label hasSuffix:@"-"]) {
            return NO;
        }
        for (NSUInteger i = 0; i < label.length; i++) {
            unichar c = [label characterAtIndex:i];
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-')) {
                return NO;
            }
        }
    }
    return YES;
}
static NSURL *ValidatedURL(NSString *text) {
    NSString *trimmed =
        [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length < 9 || [[trimmed substringToIndex:8]
                                  caseInsensitiveCompare:@"https://"] != NSOrderedSame) {
        return nil;
    }
    NSMutableCharacterSet *forbidden = [NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];
    [forbidden formUnionWithCharacterSet:NSCharacterSet.controlCharacterSet];
    [forbidden addCharactersInString:@"\\#"];
    if ([trimmed rangeOfCharacterFromSet:forbidden].location != NSNotFound) {
        return nil;
    }
    // Newer Foundation may repair malformed percent escapes; do not silently repair input.
    for (NSUInteger i = 0; i < trimmed.length; i++) {
        if ([trimmed characterAtIndex:i] != '%') {
            continue;
        }
        if (i + 2 >= trimmed.length || !IsHex([trimmed characterAtIndex:i + 1]) ||
            !IsHex([trimmed characterAtIndex:i + 2])) {
            return nil;
        }
        i += 2;
    }
    NSString *suffix = [trimmed substringFromIndex:8];
    NSRange end = [suffix rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?"]];
    NSString *authority = end.location == NSNotFound ? suffix : [suffix substringToIndex:end.location];
    if ([authority rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"@%"]]
            .location != NSNotFound) {
        return nil;
    }
    NSString *host = nil, *port = nil;
    BOOL ipv6 = [authority hasPrefix:@"["];
    if (ipv6) {
        NSRange close = [authority rangeOfString:@"]"];
        if (close.location == NSNotFound) {
            return nil;
        }
        host = [authority substringWithRange:NSMakeRange(1, close.location - 1)];
        NSString *tail = [authority substringFromIndex:close.location + 1];
        if (tail.length) {
            if (![tail hasPrefix:@":"]) {
                return nil;
            }
            port = [tail substringFromIndex:1];
        }
    } else {
        NSArray<NSString *> *parts = [authority componentsSeparatedByString:@":"];
        if (parts.count > 2) {
            return nil;
        }
        host = parts.firstObject;
        if (parts.count == 2) {
            port = parts.lastObject;
        }
    }
    // Deliberately accept DNS ASCII/punycode, IPv4, and bracketed IPv6; reject
    // ambiguous escaped hosts, abbreviated dotted IPv4, and IPv6 zone IDs.
    if (!ValidHost(host, ipv6)) {
        return nil;
    }
    if (port != nil) {
        if (!port.length) {
            return nil;
        }
        NSUInteger number = 0;
        for (NSUInteger i = 0; i < port.length; i++) {
            unichar c = [port characterAtIndex:i];
            if (c < '0' || c > '9') {
                return nil;
            }
            number = number * 10 + (c - '0');
            if (number > 65535) {
                return nil;
            }
        }
        if (!number) {
            return nil;
        }
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
    if (![components.scheme.lowercaseString isEqualToString:@"https"] || !components.host.length ||
        components.user != nil || components.password != nil || components.fragment != nil) {
        return nil;
    }
    return components.URL;
}

// The downloader and NSURLSession both retain this delegate; it retains NEITHER.
// All state changes occur on the main queue, including release-triggered cancel.
@interface QHDownloadDelegate : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, copy) void (^completion)(NSData *, NSError *);
@property(nonatomic, strong) NSMutableData *buffer;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL responseAccepted;
@property(nonatomic) NSUInteger redirects;
- (void)finishData:(NSData *)data error:(NSError *)error session:(NSURLSession *)session;
@end

@implementation QHDownloadDelegate
- (void)finishData:(NSData *)data error:(NSError *)error session:(NSURLSession *)session {
    NSAssert(NSThread.isMainThread, @"Download callbacks must use the main queue");
    if (self.finished) {
        return;
    }
    self.finished = YES;
    void (^completion)(NSData *, NSError *) = self.completion;
    self.completion = nil;
    self.buffer = nil;
    [session invalidateAndCancel];
    // Never capture the downloader or delegate in the user's queued completion.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) {
            completion(data, error);
        }
    });
}
- (void)URLSession:(NSURLSession *)session
              dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSError *error = nil;
    if (self.finished) {
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    if (self.responseAccepted || ![response isKindOfClass:NSHTTPURLResponse.class]) {
        error = DownloadError(QHDownloadInvalidResponse, QHL(@"The server returned an invalid response."));
    } else if (((NSHTTPURLResponse *)response).statusCode != 200) {
        error = DownloadError(QHDownloadHTTPStatus,
                              QHL(@"The server did not return HTTP 200. Use a direct raw Hosts file URL."));
    } else if ([response.MIMEType.lowercaseString isEqualToString:@"text/html"] ||
               [response.MIMEType.lowercaseString isEqualToString:@"application/xhtml+xml"]) {
        error = DownloadError(
            QHDownloadHTML,
            QHL(@"The URL returned an HTML page. Use a direct raw Hosts file URL, not a web page."));
    } else if (response.expectedContentLength > (int64_t)QHMaximumInputBytes) {
        error = DownloadError(QHDownloadTooLarge, QHL(@"The Hosts download exceeds the 16 MiB limit."));
    }
    if (error) {
        completionHandler(NSURLSessionResponseCancel);
        [self finishData:nil error:error session:session];
        return;
    }
    self.responseAccepted = YES;
    self.buffer = [NSMutableData data];
    completionHandler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if (self.finished) {
        return;
    }
    if (!self.responseAccepted) {
        [self finishData:nil
                   error:DownloadError(QHDownloadInvalidResponse,
                                       QHL(@"The server returned an invalid response."))
                 session:session];
        return;
    }
    // URLSession data callbacks contain decoded bytes. Check BEFORE append, and
    // subtract rather than add to avoid an integer overflow on attacker input.
    if (data.length > (NSUInteger)QHMaximumInputBytes - self.buffer.length) {
        [self
            finishData:nil
                 error:DownloadError(QHDownloadTooLarge, QHL(@"The Hosts download exceeds the 16 MiB limit."))
               session:session];
        return;
    }
    [self.buffer appendData:data];
}
- (void)URLSession:(NSURLSession *)session
                    task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
    if (self.finished) {
        return;
    }
    if (error) {
        [self finishData:nil
                   error:DownloadError(QHDownloadNetwork,
                                       QHL(@"The Hosts download failed. Check the URL and your connection."))
                 session:session];
    } else if (!self.responseAccepted) {
        [self finishData:nil
                   error:DownloadError(QHDownloadInvalidResponse,
                                       QHL(@"The server returned an invalid response."))
                 session:session];
    } else if (!self.buffer.length) {
        [self finishData:nil
                   error:DownloadError(QHDownloadEmpty, QHL(@"The downloaded Hosts file is empty."))
                 session:session];
    } else {
        [self finishData:[self.buffer copy] error:nil session:session];
    }
}
- (void)URLSession:(NSURLSession *)session
                          task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                    newRequest:(NSURLRequest *)request
             completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if (self.finished) {
        completionHandler(nil);
        return;
    }
    NSError *error = nil;
    NSURL *url = ValidatedURL(request.URL.absoluteString);
    if (!url) {
        error = URLError();
    } else if (self.redirects >= 5) {
        error = DownloadError(QHDownloadTooManyRedirects,
                              QHL(@"The Hosts download redirected too many times (maximum 5)."));
    }
    if (error) {
        // Reject before URLSession can issue the next network request.
        completionHandler(nil);
        [self finishData:nil error:error session:session];
        return;
    }
    self.redirects++;
    // A fresh GET avoids carrying Authorization/Cookie headers across origins.
    NSMutableURLRequest *next = [NSMutableURLRequest requestWithURL:url
                                                        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                    timeoutInterval:30];
    next.HTTPShouldHandleCookies = NO;
    completionHandler(next);
}
// No authentication-challenge override: normal platform TLS/trust validation.
@end

@implementation QHDownload {
    BOOL _started;
    QHDownloadDelegate *_delegate;
    NSURLSession *_session;
#if defined(QH_TESTING) && QH_TESTING
    NSArray<Class> *_testingProtocolClasses;
    __weak NSURLSessionDataTask *_testingTask;
#endif
}
+ (NSURL *)validatedURLFromString:(NSString *)text error:(NSError **)error {
    NSURL *url = ValidatedURL(text);
    if (error) {
        *error = url ? nil : URLError();
    }
    return url;
}
- (void)startURLString:(NSString *)text completion:(void (^)(NSData *, NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Download API is main-thread only");
    if (_started) {
        NSError *error =
            DownloadError(QHDownloadAlreadyStarted, QHL(@"This downloader can only be used once."));
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(nil, error);
            }
        });
        return;
    }
    _started = YES;
    _delegate = [QHDownloadDelegate new];
    _delegate.completion = completion;
    NSError *error = nil;
    NSURL *url = [QHDownload validatedURLFromString:text error:&error];
    if (!url) {
        [_delegate finishData:nil error:error session:nil];
        return;
    }
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.HTTPShouldSetCookies = NO;
    configuration.HTTPCookieStorage = nil;
    configuration.URLCredentialStorage = nil;
    configuration.URLCache = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = 30;
    configuration.timeoutIntervalForResource = 60;
    if (@available(iOS 11.0, macOS 10.13, *)) {
        configuration.waitsForConnectivity = NO;
    }
#if defined(QH_TESTING) && QH_TESTING
    if (_testingProtocolClasses) {
        configuration.protocolClasses = _testingProtocolClasses;
    }
#endif
    _session = [NSURLSession sessionWithConfiguration:configuration
                                             delegate:_delegate
                                        delegateQueue:NSOperationQueue.mainQueue];
    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url
                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                            timeoutInterval:30];
    request.HTTPShouldHandleCookies = NO;
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request];
#if defined(QH_TESTING) && QH_TESTING
    _testingTask = task;
#endif
    [task resume];
}
- (void)cancel {
    NSAssert(NSThread.isMainThread, @"Download API is main-thread only");
    [_delegate finishData:nil error:CancelledError() session:_session];
}
- (void)dealloc {
    // A dropped request still completes. Capture state, never self. Serializing
    // even off-main destruction avoids racing a delegate callback already queued.
    QHDownloadDelegate *delegate = _delegate;
    NSURLSession *session = _session;
    if (delegate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate finishData:nil error:CancelledError() session:session];
        });
    }
}
#if defined(QH_TESTING) && QH_TESTING
+ (instancetype)downloadForTestingWithProtocolClasses:(NSArray<Class> *)classes {
    NSAssert(NSThread.isMainThread, @"Download API is main-thread only");
    QHDownload *download = [self new];
    download->_testingProtocolClasses = [classes copy];
    return download;
}
- (void)redirectForTestingToURL:(NSURL *)url completion:(void (^)(NSURLRequest *))completion {
    NSAssert(NSThread.isMainThread && _started, @"Start a test request on main first");
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"must-not-forward" forHTTPHeaderField:@"Authorization"];
    [request setValue:@"must-not-forward" forHTTPHeaderField:@"Cookie"];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url
                                                              statusCode:302
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{@"Location" : url.absoluteString}];
    [_delegate URLSession:_session
                              task:_testingTask
        willPerformHTTPRedirection:response
                        newRequest:request
                 completionHandler:completion];
}
#endif
@end
