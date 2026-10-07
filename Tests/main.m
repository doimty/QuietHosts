#import <Foundation/Foundation.h>
#include <stdlib.h>
extern NSUInteger RunFileManagerTests(void);
extern NSUInteger RunRuleEngineTests(void);
extern NSUInteger RunAppStoreTests(void);
extern NSUInteger RunDownloadTests(void);
int main(void) {
    @autoreleasepool {
        // Crash tests fork before any URLSession or concurrent app-store tests.
        if (RunFileManagerTests()) {
            return EXIT_FAILURE;
        }
        if (RunRuleEngineTests()) {
            return EXIT_FAILURE;
        }
        if (RunAppStoreTests()) {
            return EXIT_FAILURE;
        }
        NSUInteger checks = RunDownloadTests();
        NSLog(@"Download checks: %lu; all native suites passed", (unsigned long)checks);
    }
    return EXIT_SUCCESS;
}
