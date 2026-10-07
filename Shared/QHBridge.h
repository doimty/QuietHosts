#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// All completion blocks run on main. Payload/result are JSON values. Helper path
// is fixed by the native RootHide mapping; no caller-supplied executable or paths.
@interface QHBridge : NSObject
+ (void)request:(NSString *)command
        payload:(NSDictionary *)payload
     completion:(void (^)(NSDictionary *result))completion;
@end
NS_ASSUME_NONNULL_END
