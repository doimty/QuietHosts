#import <Foundation/Foundation.h>
#include <sys/types.h>
NS_ASSUME_NONNULL_BEGIN
/* Production supplies jbroot(@"/"), @"/etc/hosts", and uid 0. No process
 * side effects live here. Each call reopens, locks, and verifies filesystem state. */
@interface QHFileManager : NSObject
- (instancetype)initWithRoot:(NSString *)mappedJbroot
                 systemHosts:(NSString *)rawSystemPath
               expectedOwner:(uid_t)uid;
- (NSDictionary *)handleCommand:(NSString *)command request:(NSDictionary *)request;
@end
#ifdef QH_TESTING
/* Test child only: _exit(86) at a named durable transaction boundary. */
FOUNDATION_EXPORT void QHSetTransactionFault(NSString *_Nullable point);
#endif
NS_ASSUME_NONNULL_END
