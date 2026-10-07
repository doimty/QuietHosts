#import <Foundation/Foundation.h>
#import "../Shared/QHRuleEngine.h"
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const QHStoreErrorDomain;
FOUNDATION_EXPORT NSUInteger const QHMaximumSources;
// Immutable prospective document. No persistence until commitPreview succeeds.
@interface QHStorePreview : NSObject
@property(nonatomic, readonly, copy) NSDictionary *document;
@property(nonatomic, readonly, copy) NSString *baseRevision;
@property(nonatomic, readonly, strong) QHCompiledRules *compiled;
@property(nonatomic, readonly, copy) NSDictionary<NSString *, QHParseResult *> *sourceResults;
@property(nonatomic, readonly) NSUInteger allowlistCount;
@property(nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *parseStatistics;
@end
// Synchronous, thread-safe API. Run all methods on a background queue in UIKit.
// Every read validates the full bounded document. Corrupt storage is never reset.
@interface QHStore : NSObject
- (nullable QHStorePreview *)load:(NSError **)error;
- (nullable QHStorePreview *)previewSources:(NSArray<NSDictionary *> *)sources
                                  allowlist:(NSData *)allowlist
                           expectedRevision:(NSString *)revision
                                      error:(NSError **)error;
- (BOOL)commitPreview:(QHStorePreview *)preview error:(NSError **)error;
// Coordinated security-scoped read; streams at most 16MiB + one byte off-main.
+ (nullable NSData *)readImportURL:(NSURL *)url error:(NSError **)error;
#if defined(QH_TESTING) && QH_TESTING
- (instancetype)initWithDirectory:(NSURL *)directory;
#endif
@end
NS_ASSUME_NONNULL_END
