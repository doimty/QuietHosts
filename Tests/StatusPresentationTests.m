#import <Foundation/Foundation.h>
#import "../Shared/QHStatusPresentation.h"
static NSUInteger failures, checks;
static void Check(BOOL condition) {
    checks++;
    if (!condition) {
        failures++;
        NSLog(@"StatusPresentation failure at check %lu", (unsigned long)checks);
    }
}
NSUInteger RunStatusPresentationTests(void) {
    failures = 0;
    checks = 0;
    Check([QHStatusExplanation(nil) isEqual:@"Checking file state"]);
    NSDictionary *adoption = @{@"ok" : @YES, @"state" : @"unmanaged", @"requiresAdoption" : @YES};
    Check(QHStatusRequiresAdoption(adoption));
    Check([QHStatusExplanation(adoption) containsString:@"has not been adopted"]);
    Check(![QHStatusExplanation(adoption) containsString:@"verified file state"]);
    for (id bad in @[ @1, @"true", NSNull.null, @NO, @[] ]) {
        Check(!QHStatusRequiresAdoption(@{@"ok" : @YES, @"state" : @"unmanaged", @"requiresAdoption" : bad}));
    }
    Check(!QHStatusRequiresAdoption(@{@"ok" : @NO, @"state" : @"unmanaged", @"requiresAdoption" : @YES}));
    Check(!QHStatusRequiresAdoption(@{@"ok" : @YES, @"state" : @"active", @"requiresAdoption" : @YES}));
    Check(!QHStatusRequiresAdoption(nil));
    Check(!QHStatusRequiresAdoption(@[ @"unmanaged" ]));
    Check([QHStatusExplanation(
        @{@"ok" : @NO,
          @"errorCode" : @"adoption-required"}) containsString:@"No takeover was authorized"]);
    for (NSString *code in @[
             @"unsafe-directory", @"unsafe-root-directory", @"unsafe-var-layout", @"unmanaged-target",
             @"secondary-conflict", @"mirror-conflict", @"backup-corrupt", @"orphan-preparation",
             @"revision-conflict", @"baseline-conflict", @"target-conflict", @"helper-timeout",
             @"unknown-valid-code"
         ]) {
        NSDictionary *status = @{@"ok" : @NO, @"state" : @"conflict", @"errorCode" : code};
        NSString *message = QHStatusExplanation(status);
        Check([message containsString:[@"Diagnostic code: " stringByAppendingString:code]]);
        Check([QHStatusErrorCode(status) isEqual:code]);
        Check(![message containsString:@"CCAdsBeGone"]);
    }
    NSString *regular = QHStatusExplanation(@{@"ok" : @NO, @"errorCode" : @"unmanaged-target"});
    Check([regular containsString:@"regular Hosts file"]);
    Check([regular containsString:@"will not take it over automatically"]);
    NSString *layout = QHStatusExplanation(@{@"ok" : @NO, @"errorCode" : @"unsafe-directory"});
    Check([layout containsString:@"compatibility issue"]);
    Check([layout containsString:@"Do not change ownership"]);
    for (id bad in @[
             [NSNull null], @42, @[], @{}, @"", @"path/private/token", @"unsafe-directory\nsecret", @"🔥",
             [@"x" stringByPaddingToLength:81 withString:@"x" startingAtIndex:0]
         ]) {
        NSDictionary *status =
            @{@"ok" : @NO,
              @"errorCode" : bad,
              @"message" : @"Sensitive user-supplied secret"};
        Check([QHStatusErrorCode(status) isEqual:@"unknown-error"]);
        NSString *message = QHStatusExplanation(status);
        Check([message containsString:@"Diagnostic code: unknown-error"]);
        Check(![message containsString:@"Sensitive"]);
    }
    for (id malformed in @[ @[], @42, @"raw status", [NSNull null] ]) {
        Check([QHStatusErrorCode(malformed) isEqual:@"unknown-error"]);
    }
    for (id bad in @[ @1, @"true", [NSNull null], @[] ]) {
        Check([QHStatusExplanation(@{@"ok" : bad}) containsString:@"Diagnostic code:"]);
    }
    NSString *ok = QHStatusExplanation(@{@"ok" : @YES, @"state" : @"active"});
    Check(![ok containsString:@"Diagnostic code"]);
    Check([ok containsString:@"not a DNS or traffic protection test"]);
    NSString *paused = QHStatusExplanation(@{@"ok" : @YES, @"state" : @"inactive"});
    Check([paused containsString:@"restored its verified original Hosts state"]);
    Check([paused containsString:@"does not test DNS behavior"]);
    NSString *unmanaged = QHStatusExplanation(@{@"ok" : @YES, @"state" : @"unmanaged"});
    Check([unmanaged containsString:@"No QuietHosts rules have been applied"]);
    Check([unmanaged containsString:@"original system Hosts file has not been written"]);
    NSLog(@"StatusPresentationTests: %lu checks, %lu failures", (unsigned long)checks,
          (unsigned long)failures);
    return failures;
}
