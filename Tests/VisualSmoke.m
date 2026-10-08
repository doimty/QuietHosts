#import <UIKit/UIKit.h>
#import "../App/QHAppController.h"
#import "../App/QHStore.h"
#import "../App/QHVisualComponents.h"
#import "../Shared/QHBridge.h"
#include <math.h>
#include <stdlib.h>
static NSUInteger Requests = 0, Writes = 0, Checks = 0, Failures = 0;
@implementation QHBridge
+ (void)request:(NSString *)command payload:(NSDictionary *)payload completion:(void (^)(NSDictionary *))completion {
    (void)payload;
    Requests++;
    if (![command isEqual:@"status"]) Writes++;
    completion(@{@"ok":@YES, @"state":@"active", @"revision":@"537A11EE-1ED7-4719-9489-114078092E26",
        @"domainCount":@42, @"hasBaseline":@YES});
}
@end
@interface QHAppController (SmokeAccess)
- (void)render;
- (void)openSource:(NSString *)identifier;
- (void)showPreview:(QHStorePreview *)preview title:(NSString *)title detail:(NSString *)detail button:(NSString *)button confirm:(void (^)(void))confirm;
@end
static void Check(BOOL value, NSString *name) {
    Checks++;
    if (!value) { Failures++; NSLog(@"FAIL %@",name); }
}
static void Geometry(UIView *view) {
    CGRect f=view.frame;
    Check(isfinite(f.size.width) && isfinite(f.size.height) && f.size.width>=0 && f.size.height>=0, @"finite frame");
    if ([view.accessibilityIdentifier isEqual:@"QHVBadge"] && [view isKindOfClass:UIStackView.class]) {
        UILabel *label=(UILabel *)((UIStackView *)view).arrangedSubviews.firstObject;
        Check(fabs(CGRectGetWidth(view.bounds)-CGRectGetWidth(label.bounds)-20)<1,@"capsule has only text plus insets");
        Check(CGRectGetWidth(view.bounds)<=label.intrinsicContentSize.width+21,@"capsule does not steal source text width");
    }
    if ([view isKindOfClass:UISwitch.class]) return; // Native switch shadow/internal decoration may extend.
    for (UIView *child in view.subviews) {
        if (!child.hidden && [child isKindOfClass:UILabel.class]) {
            Check(CGRectGetMinX(child.frame)>=-1 && CGRectGetMaxX(child.frame)<=CGRectGetWidth(view.bounds)+1,
                  @"label horizontal containment");
        }
        Geometry(child);
    }
}
static UISwitch *FindSwitch(UIView *view, NSString *label) {
    if ([view isKindOfClass:UISwitch.class] && [view.accessibilityLabel isEqual:label]) return (UISwitch *)view;
    for (UIView *child in view.subviews) {
        UISwitch *found = FindSwitch(child, label);
        if (found) return found;
    }
    return nil;
}
static NSUInteger CountClass(UIView *view, Class type) {
    NSUInteger count=[view isKindOfClass:type] ? 1 : 0;
    for (UIView *child in view.subviews) count+=CountClass(child,type);
    return count;
}
@interface SmokeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) QHAppController *controller;
@property(nonatomic,strong) QHStorePreview *preview;
@end
@implementation SmokeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;(void)options;
    [UIView setAnimationsEnabled:NO];
    NSError *error=nil;
    NSURL *directory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    QHStore *store=[[QHStore alloc] initWithDirectory:directory];
    QHStorePreview *empty=[store load:&error];
    NSData *data=[@"0.0.0.0 ads.example test.example\n0.0.0.0 ads.example\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *source=@{@"id":NSUUID.UUID.UUIDString,@"kind":@"paste",@"name":@"A very long source name / 超长规则来源标题用于核验原生换行",
        @"enabled":@YES,@"data":data};
    self.preview=[store previewSources:@[source] allowlist:NSData.data expectedRevision:empty.document[@"revision"] error:&error];
    Check(self.preview!=nil,error.localizedDescription ?: @"preview generated");
    Check(self.preview.compiled.domains.count==2,@"actual compiled count");
    self.controller=[QHAppController new];
    [self.controller setValue:store forKey:@"store"];
    [self.controller setValue:self.preview forKey:@"draft"];
    [self.controller setValue:@{@"ok":@YES,@"state":@"active",@"revision":@"537A11EE-1ED7-4719-9489-114078092E26",@"domainCount":@42,@"hasBaseline":@YES} forKey:@"status"];
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=self.controller.rootController;
    [self.window makeKeyAndVisible];
    [self.controller render];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [self runFixtures]; });
    return YES;
}
- (void)runFixtures {
    NSArray *categories=@[UIContentSizeCategoryLarge,UIContentSizeCategoryExtraExtraExtraLarge,UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
    for (NSNumber *style in @[@(UIUserInterfaceStyleLight),@(UIUserInterfaceStyleDark)])
    for (NSNumber *width in @[@320,@375,@428]) for (NSString *category in categories) {
        UIWindow *fixtureWindow=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        fixtureWindow.overrideUserInterfaceStyle=(UIUserInterfaceStyle)style.integerValue;
        UIViewController *parent=[UIViewController new], *child=[UIViewController new];
        fixtureWindow.rootViewController=parent;
        [fixtureWindow makeKeyAndVisible];
        [parent addChildViewController:child];
        [parent.view addSubview:child.view];
        [child didMoveToParentViewController:parent];
        if (@available(iOS 17.0, *)) {
            child.traitOverrides.preferredContentSizeCategory = category;
        } else {
            Check(NO, @"Smoke requires a CI simulator with iOS17+ trait injection");
        }
        child.view.frame=CGRectMake(0,0,width.doubleValue,4000);
        UIStackView *stack=QHVCard();
        stack.translatesAutoresizingMaskIntoConstraints=NO;
        [child.view addSubview:stack];
        [stack.leadingAnchor constraintEqualToAnchor:child.view.leadingAnchor constant:16].active=YES;
        [stack.trailingAnchor constraintEqualToAnchor:child.view.trailingAnchor constant:-16].active=YES;
        [stack.topAnchor constraintEqualToAnchor:child.view.topAnchor constant:16].active=YES;
        [stack addArrangedSubview:QHVBrandHeader(@"静域 QuietHosts",@"已启用",YES,@"Local Hosts rules")];
        [stack addArrangedSubview:QHVInfo(@"Hosts rules",@"Long explanation / 状态说明必须完整呈现而不是省略",@"shield",[UISwitch new])];
        [stack addArrangedSubview:QHVStats(@"唯一域名 Unique domains",@"300,000",@"合并去重 Merge duplicates",@"123,456,789")];
        UIControl *row=QHVRow(@"Very long source name / 超长来源名称",@"Detailed source summary that wraps",@"doc",@"300,000",NO,YES, ^{});
        [stack addArrangedSubview:row];
        [stack addArrangedSubview:QHVFormRow(@"合并后唯一域名 / merged domains",@"300,000")];
        [child.view setNeedsLayout];
        for (NSUInteger pass=0;pass<3;pass++) {
            [fixtureWindow layoutIfNeeded];
            [child.view layoutIfNeeded];
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        }
        UIStackView *stats=(UIStackView *)stack.arrangedSubviews[2];
        NSLog(@"QH_TRAIT width=%@ requested=%@ child=%@ stats=%@ axis=%ld frame=%@ window=%d",width,category,
            child.view.traitCollection.preferredContentSizeCategory,stats.traitCollection.preferredContentSizeCategory,
            (long)stats.axis,NSStringFromCGRect(stats.frame),stats.window!=nil);
        Check(stats.window==fixtureWindow,@"fixture attached to real window");
        Check([stats.traitCollection.preferredContentSizeCategory isEqual:category],@"requested category reached actual stats");
        Geometry(stack);
        Check(row.isAccessibilityElement && (row.accessibilityTraits & UIAccessibilityTraitButton),@"row accessibility");
        Check(CGRectGetHeight(row.bounds)>=44,@"44pt row target");
        if (UIContentSizeCategoryIsAccessibilityCategory(category)) {
            Check(stats.axis==UILayoutConstraintAxisVertical,@"accessibility stats single column");
        }
        if ([category isEqual:UIContentSizeCategoryLarge] && width.doubleValue>=375) {
            Check(stats.axis==UILayoutConstraintAxisHorizontal,@"normal stats two columns");
        }
        Check(stats.traitCollection.userInterfaceStyle==(UIUserInterfaceStyle)style.integerValue,@"requested appearance reached actual stats");
        if (@available(iOS 17.0, *)) {
            // Reuse the existing views. No manual component updateFlow call,
            // no fabricated category notification and no recreation of labels.
            CGFloat normalFont=0;
            for (NSString *next in @[UIContentSizeCategoryLarge,UIContentSizeCategoryAccessibilityExtraExtraExtraLarge,UIContentSizeCategoryLarge]) {
                child.traitOverrides.preferredContentSizeCategory=next;
                for (NSUInteger pass=0;pass<3;pass++) {
                    [fixtureWindow layoutIfNeeded];
                    [child.view layoutIfNeeded];
                    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
                }
                Check([stats.traitCollection.preferredContentSizeCategory isEqual:next],@"live category reaches existing stats");
                BOOL single=UIContentSizeCategoryIsAccessibilityCategory(next) || width.doubleValue<364;
                Check(stats.axis==(single ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal),@"live stats axis follows category and width");
                UIStackView *panel=(UIStackView *)stats.arrangedSubviews[0];
                UILabel *number=(UILabel *)panel.arrangedSubviews[0];
                if ([next isEqual:UIContentSizeCategoryLarge]) {
                    if (normalFont>0) Check(fabs(number.font.pointSize-normalFont)<.1,@"normal font restored");
                    normalFont=number.font.pointSize;
                } else Check(number.font.pointSize>normalFont,@"existing statistic font actually scales");
                Geometry(stack);
            }
        }
        fixtureWindow.hidden=YES;
        fixtureWindow.rootViewController=nil;
        [self.window makeKeyAndVisible];
    }
    // Exercise actual controller states, not only a copied state model.
    NSDictionary *savedStatus=[self.controller valueForKey:@"status"];
    for (NSDictionary *fixture in @[
        @{@"state":@"active",@"ok":@YES,@"busy":@NO,@"enabled":@YES,@"on":@YES},
        @{@"state":@"inactive",@"ok":@YES,@"busy":@NO,@"enabled":@YES,@"on":@NO},
        @{@"state":@"unmanaged",@"ok":@YES,@"busy":@NO,@"enabled":@NO,@"on":@NO},
        @{@"state":@"conflict",@"ok":@YES,@"busy":@NO,@"enabled":@NO,@"on":@NO},
        @{@"state":@"active",@"ok":@NO,@"busy":@NO,@"enabled":@NO,@"on":@NO},
        @{@"state":@"active",@"ok":@YES,@"busy":@YES,@"enabled":@NO,@"on":@YES}]) {
        [self.controller setValue:@{@"state":fixture[@"state"],@"ok":fixture[@"ok"],@"revision":@"mock-revision"} forKey:@"status"];
        [self.controller setValue:fixture[@"busy"] forKey:@"busy"];
        [self.controller render];
        UIViewController *homeNav=self.controller.rootController.viewControllers.firstObject;
        UISwitch *toggle=FindSwitch(homeNav.view,NSLocalizedString(@"Hosts rules",nil));
        Check(toggle!=nil && toggle.enabled==[fixture[@"enabled"] boolValue] && toggle.on==[fixture[@"on"] boolValue],@"real managed-switch state");
    }
    [self.controller setValue:@NO forKey:@"busy"];
    [self.controller setValue:savedStatus forKey:@"status"];
    [self.controller render];
    // Snapshot the actual controller pages; Bridge is mock-only and never runs helper.
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    for (NSUInteger index=0;index<3;index++) {
        self.controller.rootController.selectedIndex=index;
        [self.controller.rootController.view layoutIfNeeded];
        Check(CountClass(self.controller.rootController.selectedViewController.view,UILabel.class)>3,@"real controller rendered");
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds];
        UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            (void)context;[self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
        }];
        [UIImagePNGRepresentation(image) writeToFile:[documents stringByAppendingPathComponent:[NSString stringWithFormat:@"page-%lu.png",(unsigned long)index]] atomically:YES];
    }
    self.controller.rootController.selectedIndex=1;
    [self.controller openSource:self.preview.document[@"sources"][0][@"id"]];
    [self.controller.rootController.view layoutIfNeeded];
    UINavigationController *sources=(UINavigationController *)self.controller.rootController.selectedViewController;
    Check(sources.viewControllers.count==2,@"real source detail navigation");
    UIGraphicsImageRenderer *detailRenderer=[[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds];
    UIImage *detailImage=[detailRenderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;[self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
    }];
    [UIImagePNGRepresentation(detailImage) writeToFile:[documents stringByAppendingPathComponent:@"source-detail.png"] atomically:YES];
    [self.controller showPreview:self.preview title:@"Preview" detail:@"MOCK TEST: no Hosts writes. Explicit consent is retained." button:@"Confirm" confirm:^{ Writes++; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        Check(self.controller.rootController.presentedViewController!=nil,@"real preview presented");
        UIGraphicsImageRenderer *previewRenderer=[[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds];
        UIImage *previewImage=[previewRenderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            (void)context;[self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
        }];
        [UIImagePNGRepresentation(previewImage) writeToFile:[documents stringByAppendingPathComponent:@"preview.png"] atomically:YES];
        Check(Writes==0,@"no file/DNS commands and no implicit confirmation");
        NSDictionary *report=@{@"checks":@(Checks),@"failures":@(Failures),@"mock_status_requests":@(Requests),@"writes":@(Writes),@"scope":@"UIKit simulator layout/component/controller smoke; not device or real helper acceptance"};
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]
            writeToFile:[documents stringByAppendingPathComponent:@"result.json"] atomically:YES];
        NSLog(@"QH_UI_SMOKE %@",report);
        exit(Failures ? 1 : 0);
    });
}
@end
int main(int argc,char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(SmokeDelegate.class)); }
}
