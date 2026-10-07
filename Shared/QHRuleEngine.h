#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT const NSUInteger QHMaximumInputBytes;
FOUNDATION_EXPORT const NSUInteger QHMaximumDocumentBytes;
FOUNDATION_EXPORT const NSUInteger QHMaximumDomains;
@interface QHParseResult : NSObject
@property(nonatomic, readonly, copy) NSArray<NSString *> *domains;
@property(nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *statistics;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
@interface QHCompiledRules : NSObject
@property(nonatomic, readonly, copy) NSArray<NSString *> *domains;
@property(nonatomic, readonly, copy) NSData *hostsData;
@property(nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *statistics;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
FOUNDATION_EXPORT QHParseResult *_Nullable QHParseRules(NSData *data, NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSSet<NSString *> *_Nullable QHParseAllowlist(NSData *data,
                                                                NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT QHCompiledRules *_Nullable QHCompileDomains(NSArray<QHParseResult *> *sources,
                                                              NSSet<NSString *> *allow,
                                                              NSError *_Nullable *_Nullable error);
/* Independent 32MiB validator: exact sorted unique canonical IPv4/IPv6 pairs,
 * no headers, local names, redirects, BOM, or missing final newline. Empty OK.
 * count is set to zero on failure; no domain collection allocated. */
FOUNDATION_EXPORT BOOL QHValidateCompiledHosts(NSData *data, NSUInteger *_Nullable count,
                                               NSError *_Nullable *_Nullable error);
NS_ASSUME_NONNULL_END
