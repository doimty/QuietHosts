#import <Foundation/Foundation.h>
#import "QHRootlessRouting.h"

#ifdef QH_TESTING
/* Compile-time fixture namespace; never present in a packaged helper. */
void QHRootlessTestingSetNamespace(NSString *base);
#endif

/* These are trusted runtime inputs, not fields of a helper request. */
NSString *QHRootlessResolvePaths(NSString *dynamicRoot, NSString **root,
                               NSString **systemHosts);
const char *QHRootlessRoutingOpenRuntime(NSString *root, NSString *systemHosts,
                                       uid_t owner, QHRootlessRouting *out);
