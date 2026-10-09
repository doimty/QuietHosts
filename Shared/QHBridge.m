#import "QHBridge.h"
#import "QHProcess.h"
#import "QHLocalization.h"
#import "QHPlatform.h"
#include <errno.h>
#include <stdlib.h>

@implementation QHBridge
+ (void)request:(NSString *)command
        payload:(NSDictionary *)payload
     completion:(void (^)(NSDictionary *))completion {
    NSString *operation = [command copy];
    NSDictionary *request = [payload copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSSet *commands = [NSSet setWithArray:@[ @"status", @"apply", @"enable", @"disable", @"reload" ]];
            NSDictionary *result = nil;
            NSData *input = [NSJSONSerialization isValidJSONObject:request]
                                ? [NSJSONSerialization dataWithJSONObject:request options:0 error:NULL]
                                : nil;
            if (![commands containsObject:operation] || !input || input.length > 48u * 1024u * 1024u) {
                result = @{@"ok" : @NO, @"state" : @"error", @"errorCode" : @"invalid-request"};
            } else {
                char *output = malloc(65536);
                if (!output) {
                    result = @{@"ok" : @NO, @"state" : @"error", @"errorCode" : @"memory"};
                } else {
                    size_t length = 0;
                    int status = -1;
                    int error = QHRunProcess(QH_PLATFORM_PATH("/usr/libexec/quiethosts-helper"), operation.UTF8String,
                                             input.bytes, input.length, output, 65536, &length, &status, 90);
                    if (!error) {
                        id response = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:output
                                                                                             length:length]
                                                                      options:0
                                                                        error:NULL];
                        if ([response isKindOfClass:NSDictionary.class] &&
                            [response[@"ok"] isKindOfClass:NSNumber.class] &&
                            CFGetTypeID((__bridge CFTypeRef)response[@"ok"]) == CFBooleanGetTypeID() &&
                            [response[@"state"] isKindOfClass:NSString.class] &&
                            ((status == 0 && [response[@"ok"] boolValue]) ||
                             (status != 0 && ![response[@"ok"] boolValue]))) {
                            if (![response[@"ok"] boolValue] ||
                                ([response[@"revision"] isKindOfClass:NSString.class] &&
                                 [response[@"domainCount"] isKindOfClass:NSNumber.class])) {
                                result = response;
                            }
                        }
                    }
                    if (!result) {
                        result = @{
                            @"ok" : @NO,
                            @"state" : @"error",
                            @"errorCode" : error == ETIMEDOUT ? @"helper-timeout" : @"helper-unavailable"
                        };
                    }
                    free(output);
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(result);
                }
            });
        }
    });
}
@end
