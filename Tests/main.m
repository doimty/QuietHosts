#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>
extern NSUInteger RunSplitRootTests(BOOL mixedUID);
extern NSUInteger RunFileManagerTests(void);
extern NSUInteger RunRuleEngineTests(void);
extern NSUInteger RunAppStoreTests(void);
extern NSUInteger RunStatusPresentationTests(void);
extern NSUInteger RunDownloadTests(void);
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--mixed-uid") == 0) {
            return RunSplitRootTests(YES) ? EXIT_FAILURE : EXIT_SUCCESS;
        }
        if (argc != 1) {
            return EXIT_FAILURE;
        }
        // Crash tests fork before any URLSession or concurrent app-store tests.
        if (RunFileManagerTests()) {
            return EXIT_FAILURE;
        }
        if (RunSplitRootTests(NO)) {
            return EXIT_FAILURE;
        }
        if (RunStatusPresentationTests()) {
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
