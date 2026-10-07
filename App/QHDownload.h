/* Adapted from NetShield2. Copyright (c) 2026 EolnMsuk.
 * SPDX-License-Identifier: MIT. See LICENSE and third-party notices. */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const QHDownloadErrorDomain;
typedef NS_ENUM(NSInteger, QHDownloadErrorCode) {
    QHDownloadInvalidURL = 1,
    QHDownloadAlreadyStarted,
    QHDownloadInvalidResponse,
    QHDownloadHTTPStatus,
    QHDownloadHTML,
    QHDownloadTooLarge,
    QHDownloadEmpty,
    QHDownloadNetwork,
    QHDownloadCancelled,
    QHDownloadTooManyRedirects,
};

// URL validation is thread-safe; start/cancel are main-thread-only. Create a fresh instance for every
// request; no policy writes. Every start completion is called exactly once, asynchronously on the main queue.
// Success returns immutable, nonempty data; failure returns only a sanitized error.
// cancel is idempotent; before start it is a no-op. Releasing an active instance
// cancels it, without a session/delegate retain cycle or losing its completion.
@interface QHDownload : NSObject
- (void)startURLString:(NSString *)text
            completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;
- (void)cancel;
+ (NSURL *_Nullable)validatedURLFromString:(NSString *)text error:(NSError *_Nullable *_Nullable)error;
@end

#if defined(QH_TESTING) && QH_TESTING
// No production configuration override. Tests still use the production ephemeral
// configuration, adding only an in-process NSURLProtocol (never real networking).
@interface QHDownload (Testing)
+ (instancetype)downloadForTestingWithProtocolClasses:(NSArray<Class> *)classes;
// Exercises the actual redirect delegate callback: NSURLProtocol redirect support
// differs between Foundation versions. Call only after starting a stalled request.
- (void)redirectForTestingToURL:(NSURL *)url completion:(void (^)(NSURLRequest *_Nullable))completion;
@end
#endif

NS_ASSUME_NONNULL_END
