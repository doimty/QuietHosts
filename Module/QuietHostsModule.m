#import <ControlCenterUIKit/CCUIToggleModule.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../Shared/QHBridge.h"

@interface QuietHostsModule : CCUIToggleModule
@property(nonatomic) BOOL qhSelected;
@property(nonatomic) BOOL qhBusy;
@property(nonatomic, copy) NSString *qhRevision;
- (void)queryState;
@end
static void Changed(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                    CFDictionaryRef info) {
    (void)center;
    (void)name;
    (void)object;
    (void)info;
    __weak QuietHostsModule *module = (__bridge QuietHostsModule *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [module queryState];
    });
}
@implementation QuietHostsModule
- (instancetype)init {
    if ((self = [super init])) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self,
                                        Changed, CFSTR("com.doimty.quiethosts.changed"), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        [self queryState];
    }
    return self;
}
- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self,
                                       CFSTR("com.doimty.quiethosts.changed"), NULL);
}
- (UIImage *)iconGlyph {
    return [UIImage systemImageNamed:@"shield.lefthalf.filled"];
}
- (UIImage *)selectedIconGlyph {
    return [self iconGlyph];
}
- (UIColor *)selectedColor {
    return [UIColor colorWithRed:0.15 green:0.46 blue:0.41 alpha:1];
}
- (BOOL)isSelected {
    return self.qhSelected;
}
- (void)queryState {
    if (self.qhBusy) {
        return;
    }
    self.qhBusy = YES;
    __weak typeof(self) weakSelf = self;
    [QHBridge request:@"status"
              payload:@{}
           completion:^(NSDictionary *result) {
               QuietHostsModule *owner = weakSelf;
               if (!owner) {
                   return;
               }
               owner.qhBusy = NO;
               owner.qhRevision = [result[@"ok"] boolValue] ? result[@"revision"] : nil;
               owner.qhSelected = [result[@"ok"] boolValue] && [result[@"state"] isEqual:@"active"];
               [owner refreshState];
           }];
}
- (void)setSelected:(BOOL)selected {
    if (self.qhBusy || !self.qhRevision.length) {
        [self queryState];
        return;
    }
    self.qhBusy = YES;
    NSString *revision = [self.qhRevision copy];
    __weak typeof(self) weakSelf = self;
    [QHBridge request:selected ? @"enable" : @"disable"
              payload:@{@"expectedRevision" : revision}
           completion:^(NSDictionary *result) {
               QuietHostsModule *owner = weakSelf;
               if (!owner) {
                   return;
               }
               owner.qhBusy = NO;
               // Never display an optimistic enabled state on helper failure.
               if ([result[@"ok"] boolValue]) {
                   owner.qhSelected = [result[@"state"] isEqual:@"active"];
                   owner.qhRevision = result[@"revision"];
               }
               [owner refreshState];
               [owner queryState];
           }];
}
@end
