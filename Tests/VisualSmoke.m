#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../App/QHAppController.h"
#import "../App/QHDialogController.h"
#import "../App/QHDownload.h"
#import "../App/QHStore.h"
#import "../App/QHVisualComponents.h"
#import "../Shared/QHBridge.h"
#include <math.h>
#include <stdlib.h>

// CI-only, isolated simulator fixture. Neither the real helper nor the network
// is invoked. These counters become evidence only when this executable runs.
static NSUInteger Requests = 0, Writes = 0, Downloads = 0, Checks = 0, Failures = 0;
static NSUInteger ComponentFixtures = 0, ControllerCases = 0, NativeSwitchChecks = 0;
static NSUInteger ControllerLiveTransitions = 0, ConsentCancellations = 0, Screenshots = 0;
static NSDictionary *BridgeStatusOverride = nil;
extern void QHRunDialogSmoke(QHAppController *,void (^)(NSUInteger,NSUInteger));
static NSDictionary *DefaultStatus(void) {
    return @{ @"ok":@YES, @"state":@"active", @"revision":@"537A11EE-1ED7-4719-9489-114078092E26",
              @"domainCount":@42, @"hasBaseline":@YES };
}
@implementation QHBridge
+ (void)request:(NSString *)command payload:(NSDictionary *)payload completion:(void (^)(NSDictionary *))completion {
    (void)payload;
    Requests++;
    if (![command isEqual:@"status"]) Writes++;
    completion(BridgeStatusOverride ?: DefaultStatus());
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
// Any unexpected download attempt is counted and fails the final zero gate;
// replace only the test process's start IMP so a regression cannot contact a
// real source server before being detected. URL validation remains production.
static void BlockDownloadStart(id owner, SEL selector, NSString *url, void (^completion)(NSData *,NSError *)) {
    (void)owner;(void)selector;(void)url;
    Downloads++;
    dispatch_async(dispatch_get_main_queue(),^{
        if (completion) completion(nil,[NSError errorWithDomain:@"QHVisualSmokeNoNetwork" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"UI smoke forbids network downloads"}]);
    });
}
static void InstallDownloadGuard(void) {
    Method method=class_getInstanceMethod(QHDownload.class,@selector(startURLString:completion:));
    Check(method!=NULL,@"production downloader start is guarded in the isolated test process");
    if (method) class_replaceMethod(QHDownload.class,@selector(startURLString:completion:),
                                   (IMP)BlockDownloadStart,method_getTypeEncoding(method));
}
static void Geometry(UIView *view) {
    CGRect f=view.frame;
    Check(isfinite(f.size.width) && isfinite(f.size.height) && f.size.width>=0 && f.size.height>=0, @"finite frame");
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
static UIView *FindID(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *child in view.subviews) { UIView *found=FindID(child,identifier);if(found)return found; }
    return nil;
}
static UIControl *FindControl(UIView *view, NSString *label) {
    if ([view isKindOfClass:UIControl.class] && [view.accessibilityLabel isEqual:label]) return (UIControl *)view;
    for (UIView *child in view.subviews) { UIControl *found=FindControl(child,label);if(found)return found; }
    return nil;
}
static UILabel *FindLabel(UIView *view, NSString *text) {
    if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqual:text]) return (UILabel *)view;
    for (UIView *child in view.subviews) { UILabel *found=FindLabel(child,text);if(found)return found; }
    return nil;
}
static NSUInteger CountClass(UIView *view, Class type) {
    NSUInteger count=[view isKindOfClass:type] ? 1 : 0;
    for (UIView *child in view.subviews) count+=CountClass(child,type);
    return count;
}
static NSUInteger CountID(UIView *view, NSString *identifier) {
    NSUInteger count=[view.accessibilityIdentifier isEqual:identifier] ? 1 : 0;
    for (UIView *child in view.subviews) count+=CountID(child,identifier);
    return count;
}
static BOOL ContainsView(UIView *ancestor, UIView *view) {
    if (!ancestor || !view) return NO;
    for (UIView *candidate=view;candidate;candidate=candidate.superview) if (candidate==ancestor) return YES;
    return NO;
}
static BOOL SwitchAccessibilityVisible(UISwitch *toggle, UIView *card) {
    if (!ContainsView(card,toggle)) return NO;
    for (UIView *view=toggle;view;view=view.superview) {
        if (view.hidden || view.accessibilityElementsHidden) return NO;
        if (view==card) break;
    }
    return YES;
}
static BOOL NativeSwitchSizeMatches(UISwitch *toggle) {
    if (![toggle isKindOfClass:UISwitch.class]) return NO;
    CGSize native=[toggle sizeThatFits:CGSizeZero];
    return native.width>0 && native.height>0 &&
        fabs(CGRectGetWidth(toggle.bounds)-native.width)<=0.5 &&
        fabs(CGRectGetHeight(toggle.bounds)-native.height)<=0.5 &&
        fabs(CGRectGetWidth(toggle.frame)-native.width)<=0.5 &&
        fabs(CGRectGetHeight(toggle.frame)-native.height)<=0.5 &&
        CGAffineTransformEqualToTransform(toggle.transform,CGAffineTransformIdentity);
}
static void CheckNativeSwitch(UISwitch *toggle, UIView *card) {
    NativeSwitchChecks++;
    Check(toggle.window!=nil && NativeSwitchSizeMatches(toggle),@"hero UISwitch keeps its actual native sizeThatFits dimensions without stretch");
    Check(SwitchAccessibilityVisible(toggle,card),@"hero native switch remains an independent accessible control");
}
static BOOL ManagedCountMatches(UIView *card, NSString *expected) {
    UIView *count=FindID(card,@"qh.managed.count");
    if (!expected) return count==nil && CountID(card,@"qh.managed.count")==0;
    return count!=nil && CountID(card,@"qh.managed.count")==1 && [count.accessibilityValue isEqual:expected];
}
static NSString *Number(NSUInteger value) {
    return [NSNumberFormatter localizedStringFromNumber:@(value) numberStyle:NSNumberFormatterDecimalStyle];
}
static void LayoutWindow(UIWindow *window) {
    for (NSUInteger pass=0;pass<3;pass++) {
        [window layoutIfNeeded];
        [window.rootViewController.view layoutIfNeeded];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    }
}
static void Screenshot(UIWindow *window, NSString *documents, NSString *name) {
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;[window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    NSData *png=UIImagePNGRepresentation(image);
    BOOL written=png.length>0 && [png writeToFile:[documents stringByAppendingPathComponent:name] atomically:YES];
    Check(written,[@"real controller screenshot saved: " stringByAppendingString:name]);
    if (written) Screenshots++;
}
@interface SmokeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) QHAppController *controller;
@property(nonatomic,strong) QHStorePreview *preview;
@property(nonatomic,strong) QHStorePreview *emptyPreview;
- (void)runFixtures;
- (void)runControllerMatrix;
- (void)runDraftProofFixtures;
- (void)runConsentProbes:(NSUInteger)stage completion:(void (^)(void))completion;
- (void)snapshotControllerPages;
@end
@implementation SmokeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;(void)options;
    [UIView setAnimationsEnabled:NO];
    InstallDownloadGuard();
    NSError *error=nil;
    NSURL *directory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    QHStore *store=[[QHStore alloc] initWithDirectory:directory];
    QHStorePreview *empty=[store load:&error];
    self.emptyPreview=empty;
    NSData *data=[@"0.0.0.0 ads.example test.example\n0.0.0.0 ads.example\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *source=@{@"id":NSUUID.UUID.UUIDString,@"kind":@"paste",@"name":@"A very long source name / 超长规则来源标题用于核验原生换行",
        @"enabled":@YES,@"data":data};
    self.preview=[store previewSources:@[source] allowlist:NSData.data expectedRevision:empty.document[@"revision"] error:&error];
    Check(self.preview!=nil,error.localizedDescription ?: @"preview generated");
    Check(self.preview.compiled.domains.count==2,@"actual compiled count");
    Check(self.emptyPreview!=nil && self.emptyPreview.compiled.domains.count==0,@"actual empty prospective draft");
    self.controller=[QHAppController new];
    [self.controller setValue:store forKey:@"store"];
    [self.controller setValue:self.preview forKey:@"draft"];
    [self.controller setValue:DefaultStatus() forKey:@"status"];
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=self.controller.rootController;
    [self.window makeKeyAndVisible];
    [self.controller render];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [self runFixtures]; });
    return YES;
}
- (void)runFixtures {
    // Preserve all 18 original fixtures, including the 320pt regression width.
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
        UIControl *command=QHVCommandRow(@"Very long source name / 超长来源名称",@"Detailed source summary that wraps",@"doc",@"300,000",NO,YES, ^{});
        [stack addArrangedSubview:command];
        UISwitch *knownSwitch=[UISwitch new];knownSwitch.on=YES;knownSwitch.enabled=YES;
        UISwitch *unknownSwitch=[UISwitch new];unknownSwitch.on=NO;unknownSwitch.enabled=NO;
        UIStackView *withCount=QHVStatusCard(@"Verified managed state / 核验后的真实文件状态",@"Enabled",@"Long explanation / 不代表所有网络请求均受保护",
            @"Managed domains",@"300,000",knownSwitch,YES,NO);
        UIStackView *withoutCount=QHVStatusCard(@"No reported count / 未报告域名数量",@"Needs attention",@"No synthetic zero / 不伪造零数量",
            @"Managed domains",nil,unknownSwitch,NO,YES);
        [stack addArrangedSubview:withCount];
        [stack addArrangedSubview:withoutCount];
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
        Check(command.isAccessibilityElement && (command.accessibilityTraits & UIAccessibilityTraitButton),@"command accessibility");
        Check(CGRectGetHeight(row.bounds)>=44,@"44pt row target");
        Check(CGRectGetHeight(command.bounds)>=44,@"44pt command target");
        Check(CountClass(row,UIImageView.class)==CountClass(command,UIImageView.class)+1,@"only navigation rows display a disclosure chevron");
        CheckNativeSwitch(knownSwitch,withCount);
        CheckNativeSwitch(unknownSwitch,withoutCount);
        Check(ManagedCountMatches(withCount,@"300,000"),@"reported count is shown once inside its hero");
        Check(ManagedCountMatches(withoutCount,nil),@"missing count omits the row rather than manufacturing zero");
        Check(knownSwitch.on && knownSwitch.enabled && !unknownSwitch.on && !unknownSwitch.enabled,@"status component never changes controller-owned on/enabled values");
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
                CheckNativeSwitch(knownSwitch,withCount);
                CheckNativeSwitch(unknownSwitch,withoutCount);
                Check(ManagedCountMatches(withoutCount,nil),@"live reflow never invents a missing count");
                Geometry(stack);
            }
        }
        ComponentFixtures++;
        fixtureWindow.hidden=YES;
        fixtureWindow.rootViewController=nil;
        [self.window makeKeyAndVisible];
    }
    Check(ComponentFixtures==18,@"all 18 historical light/dark width/category fixtures executed");
    // Independent detector counterexamples, never injected into production UI.
    UISwitch *stretched=[UISwitch new];
    CGSize native=[stretched sizeThatFits:CGSizeZero];
    stretched.bounds=CGRectMake(0,0,native.width+24,native.height);
    Check(!NativeSwitchSizeMatches(stretched),@"native-size detector rejects a horizontally stretched UISwitch");
    UIStackView *syntheticZero=QHVStatusCard(@"Unknown",@"Needs attention",nil,@"Managed domains",@"0",[UISwitch new],NO,YES);
    Check(!ManagedCountMatches(syntheticZero,nil),@"count detector rejects a synthetic zero when no count was reported");
    Check(ManagedCountMatches(syntheticZero,@"0"),@"a genuine reported zero is distinct from missing count");
    [self runControllerMatrix];
    [self runDraftProofFixtures];
    [self runConsentProbes:0 completion:^{ [self snapshotControllerPages]; }];
}
- (void)runControllerMatrix {
    // Real controller live DT321/375/428 matrix; the original DT320 component
    // fixtures above remain intact. Width is the actual window, not a model.
    NSDictionary *savedStatus=[self.controller valueForKey:@"status"];
    CGRect savedFrame=self.window.frame;
    UIUserInterfaceStyle savedStyle=self.window.overrideUserInterfaceStyle;
    self.controller.rootController.selectedIndex=0;
    NSArray *states=@[
        @{@"state":@"active",@"ok":@YES,@"busy":@NO,@"enabled":@YES,@"on":@YES},
        @{@"state":@"inactive",@"ok":@YES,@"busy":@NO,@"enabled":@YES,@"on":@NO},
        @{@"state":@"unmanaged",@"ok":@YES,@"busy":@NO,@"enabled":@NO,@"on":@NO},
        @{@"state":@"conflict",@"ok":@YES,@"busy":@NO,@"enabled":@NO,@"on":@NO},
        @{@"state":@"active",@"ok":@NO,@"busy":@NO,@"enabled":@NO,@"on":@NO},
        @{@"state":@"active",@"ok":@YES,@"busy":@YES,@"enabled":@NO,@"on":@YES}];
    for (NSNumber *style in @[@(UIUserInterfaceStyleLight),@(UIUserInterfaceStyleDark)])
    for (NSNumber *width in @[@321,@375,@428]) {
        self.window.overrideUserInterfaceStyle=(UIUserInterfaceStyle)style.integerValue;
        self.window.frame=CGRectMake(savedFrame.origin.x,savedFrame.origin.y,width.doubleValue,savedFrame.size.height);
        if (@available(iOS 17.0, *)) self.controller.rootController.traitOverrides.preferredContentSizeCategory=UIContentSizeCategoryLarge;
        LayoutWindow(self.window);
        Check(fabs(CGRectGetWidth(self.window.bounds)-width.doubleValue)<.5,@"real controller window uses requested matrix width");
        for (NSDictionary *fixture in states) for (id countValue in @[@42,NSNull.null,@"42"]) {
            NSMutableDictionary *status=[@{@"state":fixture[@"state"],@"ok":fixture[@"ok"],@"revision":@"mock-revision"} mutableCopy];
            if (countValue!=NSNull.null) status[@"domainCount"]=countValue;
            [self.controller setValue:status forKey:@"status"];
            [self.controller setValue:fixture[@"busy"] forKey:@"busy"];
            [self.controller render];
            LayoutWindow(self.window);
            UINavigationController *homeNav=(UINavigationController *)self.controller.rootController.viewControllers.firstObject;
            UIView *home=homeNav.topViewController.view;
            UIView *hero=FindID(home,@"qh.managed.card");
            UISwitch *toggle=FindSwitch(home,NSLocalizedString(@"Hosts rules",nil));
            Check(toggle!=nil && toggle.enabled==[fixture[@"enabled"] boolValue] && toggle.on==[fixture[@"on"] boolValue],@"real managed-switch state");
            Check(CountID(home,@"qh.managed.card")==1 && CountClass(hero,UISwitch.class)==1,@"real Home has one hero and one original native switch");
            CheckNativeSwitch(toggle,hero);
            BOOL managed=[fixture[@"ok"] boolValue] && [@[@"active",@"inactive"] containsObject:fixture[@"state"]];
            NSString *expected=managed && [countValue isKindOfClass:NSNumber.class] ? Number([countValue unsignedIntegerValue]) : nil;
            Check(ManagedCountMatches(hero,expected),@"real controller uses only a verified numeric managed count; absent/string/conflict do not become zero");
            Check(hero.traitCollection.userInterfaceStyle==(UIUserInterfaceStyle)style.integerValue,@"real controller hero inherits light/dark appearance");
            UIView *draft=FindID(home,@"qh.draft.card"), *apply=FindID(home,@"qh.draft.apply");
            Check(ContainsView(draft,apply) && !ContainsView(hero,apply),@"real Preview and apply CTA belongs inside the draft card, never the managed hero");
            Geometry((UIStackView *)[homeNav.topViewController valueForKey:@"stack"]);
            ControllerCases++;
        }
        [self.controller setValue:@NO forKey:@"busy"];
        [self.controller setValue:savedStatus forKey:@"status"];
        [self.controller render];
        LayoutWindow(self.window);
        UINavigationController *homeNav=(UINavigationController *)self.controller.rootController.viewControllers.firstObject;
        UIStackView *stats=(UIStackView *)FindID(homeNav.topViewController.view,@"qh.draft.stats");
        UIStackView *panel=(UIStackView *)stats.arrangedSubviews.firstObject;
        UILabel *number=(UILabel *)panel.arrangedSubviews.firstObject;
        CGFloat normalFont=0;
        if (@available(iOS 17.0, *)) {
            for (NSString *next in @[UIContentSizeCategoryLarge,UIContentSizeCategoryAccessibilityExtraExtraExtraLarge,UIContentSizeCategoryLarge]) {
                self.controller.rootController.traitOverrides.preferredContentSizeCategory=next;
                LayoutWindow(self.window);
                Check(stats.window==self.window && [stats.traitCollection.preferredContentSizeCategory isEqual:next],@"live category reaches existing real controller statistics");
                BOOL single=UIContentSizeCategoryIsAccessibilityCategory(next) || width.doubleValue<364;
                Check(stats.axis==(single ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal),@"real controller live stats reflow follows actual category and width");
                if ([next isEqual:UIContentSizeCategoryLarge]) {
                    if (normalFont>0) Check(fabs(number.font.pointSize-normalFont)<.1,@"real controller normal statistic font restored");
                    normalFont=number.font.pointSize;
                } else Check(number.font.pointSize>normalFont,@"existing real controller statistic font actually scales");
                UIView *hero=FindID(homeNav.topViewController.view,@"qh.managed.card");
                CheckNativeSwitch(FindSwitch(homeNav.topViewController.view,NSLocalizedString(@"Hosts rules",nil)),hero);
                Geometry((UIStackView *)[homeNav.topViewController valueForKey:@"stack"]);
                ControllerLiveTransitions++;
            }
        } else Check(NO,@"real controller live matrix requires iOS17+ trait injection");
    }
    Check(ControllerCases==108,@"all original controller states execute with numeric, missing and invalid counts in both appearances and three widths");
    Check(ControllerLiveTransitions==18,@"real controller live DT321/375/428 transitions executed without recreating labels");
    [self.controller setValue:@NO forKey:@"busy"];
    [self.controller setValue:savedStatus forKey:@"status"];
    self.window.frame=savedFrame;
    self.window.overrideUserInterfaceStyle=savedStyle;
    if (@available(iOS 17.0, *)) self.controller.rootController.traitOverrides.preferredContentSizeCategory=UIContentSizeCategoryLarge;
    [self.controller render];
    LayoutWindow(self.window);
}
- (void)runDraftProofFixtures {
    NSDictionary *savedStatus=[self.controller valueForKey:@"status"];
    id savedLocal=[self.controller valueForKey:@"appliedLocalRevision"];
    id savedHelper=[self.controller valueForKey:@"appliedHelperRevision"];
    NSString *revision=self.preview.document[@"revision"];
    for (NSDictionary *proof in @[
        @{@"local":NSNull.null,@"helper":NSNull.null,@"same":@NO},
        @{@"local":revision,@"helper":@"other-helper",@"same":@NO},
        @{@"local":@"other-local",@"helper":@"mock-revision",@"same":@NO},
        @{@"local":revision,@"helper":@"mock-revision",@"same":@YES}]) {
        [self.controller setValue:@{@"state":@"active",@"ok":@YES,@"revision":@"mock-revision",@"domainCount":@(self.preview.compiled.domains.count)} forKey:@"status"];
        [self.controller setValue:proof[@"local"]==NSNull.null ? nil : proof[@"local"] forKey:@"appliedLocalRevision"];
        [self.controller setValue:proof[@"helper"]==NSNull.null ? nil : proof[@"helper"] forKey:@"appliedHelperRevision"];
        [self.controller render];
        LayoutWindow(self.window);
        UINavigationController *home=(UINavigationController *)self.controller.rootController.viewControllers.firstObject;
        BOOL same=FindLabel(home.topViewController.view,NSLocalizedString(@"This draft was confirmed applied in this session.",nil))!=nil;
        Check(same==[proof[@"same"] boolValue],@"equal domain counts never prove applied: both recorded revisions must match");
    }
    [self.controller setValue:savedLocal forKey:@"appliedLocalRevision"];
    [self.controller setValue:savedHelper forKey:@"appliedHelperRevision"];
    [self.controller setValue:savedStatus forKey:@"status"];
    // Excluded URL snapshots still expose refresh. No rendering calls start a
    // download; the app's real hasOnlineSources path is exercised via its rows.
    QHStore *store=[self.controller valueForKey:@"store"];
    for (NSDictionary *kind in @[
        @{@"kind":@"paste",@"enabled":@YES,@"online":@NO},
        @{@"kind":@"file",@"enabled":@YES,@"online":@NO},
        @{@"kind":@"url",@"enabled":@YES,@"online":@YES},
        @{@"kind":@"url",@"enabled":@NO,@"online":@YES}]) {
        NSMutableDictionary *source=[self.preview.document[@"sources"][0] mutableCopy];
        source[@"kind"]=kind[@"kind"];source[@"enabled"]=kind[@"enabled"];
        if ([kind[@"kind"] isEqual:@"url"]) source[@"url"]=@"https://example.invalid/fixture-hosts";
        NSError *error=nil;
        QHStorePreview *candidate=[store previewSources:@[source] allowlist:NSData.data expectedRevision:self.emptyPreview.document[@"revision"] error:&error];
        Check(candidate!=nil,error.localizedDescription ?: @"isolated source-kind fixture");
        [self.controller setValue:candidate forKey:@"draft"];
        [self.controller render];
        LayoutWindow(self.window);
        UINavigationController *home=(UINavigationController *)self.controller.rootController.viewControllers.firstObject;
        UIControl *refresh=FindControl(home.topViewController.view,NSLocalizedString(@"Update online sources",nil));
        // Accessible rows include their subtitle in the label; find the title
        // label as well, rather than assuming an old label-only row snapshot.
        BOOL shown=refresh!=nil || FindLabel(home.topViewController.view,NSLocalizedString(@"Update online sources",nil))!=nil;
        Check(shown==[kind[@"online"] boolValue],@"real Home refresh includes all URLs, including excluded snapshots");
        Check(Downloads==0 && Writes==0,@"source-kind rendering causes no download or Hosts/DNS command");
    }
    [self.controller setValue:self.preview forKey:@"draft"];
    [self.controller render];
}
- (void)runConsentProbes:(NSUInteger)stage completion:(void (^)(void))completion {
    if (stage>=5) {
        BridgeStatusOverride=nil;
        [self.controller setValue:self.preview forKey:@"draft"];
        [self.controller setValue:DefaultStatus() forKey:@"status"];
        [self.controller setValue:@NO forKey:@"busy"];
        [self.controller render];
        Check(ConsentCancellations==5,@"all real import/switch/empty-apply consent probes cancelled explicitly");
        if (completion) completion();
        return;
    }
    BOOL empty=stage==0 || stage>=3;
    BOOL active=stage==1 || stage==3;
    NSString *state=stage==0 ? @"unmanaged" : active ? @"active" : @"inactive";
    BridgeStatusOverride=@{@"ok":@YES,@"state":state,@"revision":@"mock-consent-revision",@"domainCount":@42,@"hasBaseline":@YES};
    [self.controller setValue:empty ? self.emptyPreview : self.preview forKey:@"draft"];
    [self.controller setValue:BridgeStatusOverride forKey:@"status"];
    [self.controller setValue:@NO forKey:@"busy"];
    self.controller.rootController.selectedIndex=0;
    [self.controller render];
    LayoutWindow(self.window);
    UINavigationController *home=(UINavigationController *)self.controller.rootController.viewControllers.firstObject;
    UIView *hero=FindID(home.topViewController.view,@"qh.managed.card");
    UISwitch *toggle=FindSwitch(home.topViewController.view,NSLocalizedString(@"Hosts rules",nil));
    CheckNativeSwitch(toggle,hero);
    if (stage==1 || stage==2) {
        [toggle setOn:!active animated:NO];
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        Check(toggle.on==active,@"real switch click restores active state before confirmation");
    } else {
        UIControl *apply=(UIControl *)FindID(home.topViewController.view,@"qh.draft.apply");
        NSString *title=NSLocalizedString(stage==0 ? @"Add your first source" : @"Preview and apply",nil);
        Check(apply!=nil && apply.enabled && [apply.accessibilityLabel isEqual:title],@"empty draft CTA offers first import only when unmanaged, otherwise preview/apply");
        [apply sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        UIViewController *presented=self.controller.rootController.presentedViewController;
        Check(presented!=nil && [[self.controller valueForKey:@"busy"] boolValue],@"real user action enters an explicit consent flow while busy is owned");
        if (stage==0) {
            Check([presented isKindOfClass:QHDialogController.class] && [((UINavigationController *)presented).topViewController.title isEqual:NSLocalizedString(@"Add source",nil)],@"Add first source routes to chooseImport, not apply or an implicit URL download");
            UIView *choices=FindID(presented.view,@"qh.dialog.choices");
            Check(CountID(presented.view,@"qh.dialog.choices")==1 && CountClass(choices,UIControl.class)>=3,@"real import choices share one grouped card");
        } else if (stage<3) {
            Check([presented isKindOfClass:QHDialogController.class] && ((QHDialogController *)presented).usesCenteredConfirmation,@"real enable/disable uses its original short confirmation");
        } else {
            Check([presented isKindOfClass:UINavigationController.class] && ![presented isKindOfClass:QHDialogController.class] && self.emptyPreview.compiled.domains.count==0,@"active or paused saved rules can explicitly preview applying an empty draft");
        }
        Check(Downloads==0 && Writes==0,@"opening consent never downloads or writes/reloads Hosts");
        UIControl *cancel=FindControl(presented.view,NSLocalizedString(@"Cancel",nil));
        Check(cancel!=nil,@"real consent has an explicit cancel control");
        if (cancel) [cancel sendActionsForControlEvents:UIControlEventTouchUpInside];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            Check(self.controller.rootController.presentedViewController==nil && ![[self.controller valueForKey:@"busy"] boolValue],@"cancel dismisses the real consent flow and releases busy");
            Check(Downloads==0 && Writes==0,@"cancelled import/switch/empty apply sends no download or Hosts/DNS write");
            UINavigationController *currentHome=(UINavigationController *)self.controller.rootController.viewControllers.firstObject;
            UIView *currentHero=FindID(currentHome.topViewController.view,@"qh.managed.card");
            UISwitch *currentSwitch=FindSwitch(currentHome.topViewController.view,NSLocalizedString(@"Hosts rules",nil));
            Check(currentSwitch.on==active,@"cancel preserves verified active/paused/unmanaged switch state");
            CheckNativeSwitch(currentSwitch,currentHero);
            if (self.controller.rootController.presentedViewController==nil && ![[self.controller valueForKey:@"busy"] boolValue]) ConsentCancellations++;
            [self runConsentProbes:stage+1 completion:completion];
        });
    });
}
- (void)snapshotControllerPages {
    // Snapshot actual controller pages in both appearances. Preserve every old
    // page-{i}.png/source-detail.png/preview.png filename as the light capture.
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    for (NSNumber *style in @[@(UIUserInterfaceStyleLight),@(UIUserInterfaceStyleDark)]) {
        BOOL dark=style.integerValue==UIUserInterfaceStyleDark;
        self.window.overrideUserInterfaceStyle=(UIUserInterfaceStyle)style.integerValue;
        [self.controller render];
        for (NSUInteger index=0;index<3;index++) {
            self.controller.rootController.selectedIndex=index;
            LayoutWindow(self.window);
            Check(CountClass(self.controller.rootController.selectedViewController.view,UILabel.class)>3,@"real controller rendered");
            Check(self.controller.rootController.selectedViewController.view.traitCollection.userInterfaceStyle==(UIUserInterfaceStyle)style.integerValue,@"actual page screenshot inherits requested appearance");
            Screenshot(self.window,documents,[NSString stringWithFormat:dark ? @"page-%lu-dark.png" : @"page-%lu.png",(unsigned long)index]);
        }
        self.controller.rootController.selectedIndex=1;
        UINavigationController *sources=(UINavigationController *)self.controller.rootController.selectedViewController;
        [sources popToRootViewControllerAnimated:NO];
        [self.controller openSource:self.preview.document[@"sources"][0][@"id"]];
        LayoutWindow(self.window);
        Check(sources.viewControllers.count==2,@"real source detail navigation");
        Geometry((UIStackView *)[sources.topViewController valueForKey:@"stack"]);
        Screenshot(self.window,documents,dark ? @"source-detail-dark.png" : @"source-detail.png");
        [sources popToRootViewControllerAnimated:NO];
    }
    self.window.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;
    [self.controller showPreview:self.preview title:@"Preview" detail:@"MOCK TEST: no Hosts writes. Explicit consent is retained." button:@"Confirm" confirm:^{ Writes++; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        Check(self.controller.rootController.presentedViewController!=nil,@"real preview presented");
        for (NSNumber *style in @[@(UIUserInterfaceStyleDark),@(UIUserInterfaceStyleLight)]) {
            self.window.overrideUserInterfaceStyle=(UIUserInterfaceStyle)style.integerValue;
            LayoutWindow(self.window);
            Screenshot(self.window,documents,style.integerValue==UIUserInterfaceStyleDark ? @"preview-dark.png" : @"preview.png");
        }
        Check(Writes==0,@"no file/DNS commands and no implicit confirmation");
        Check(Downloads==0,@"no implicit source download across rendering, navigation, appearance, consent or cancel");
        [self.controller.rootController dismissViewControllerAnimated:NO completion:^{
            QHRunDialogSmoke(self.controller,^(NSUInteger dialogChecks,NSUInteger dialogFailures) {
                Checks+=dialogChecks;Failures+=dialogFailures;
                Check(Writes==0,@"dialog flows never send write/reload or implicit consent");
                Check(Downloads==0,@"dialog cancel and invalid-input flows never start a download");
                NSDictionary *report=@{@"checks":@(Checks),@"failures":@(Failures),@"dialog_checks":@(dialogChecks),
                    @"mock_status_requests":@(Requests),@"writes":@(Writes),@"downloads":@(Downloads),
                    @"component_fixtures":@(ComponentFixtures),@"controller_cases":@(ControllerCases),
                    @"native_switch_checks":@(NativeSwitchChecks),@"controller_live_transitions":@(ControllerLiveTransitions),
                    @"consent_cancellations":@(ConsentCancellations),@"screenshots":@(Screenshots),
                    @"scope":@"UIKit simulator real controller layout/dialog lifecycle smoke; mock Bridge and blocked network; not device or real helper acceptance"};
                [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]
                    writeToFile:[documents stringByAppendingPathComponent:@"result.json"] atomically:YES];
                NSLog(@"QH_UI_SMOKE %@",report);
                exit(Failures ? 1 : 0);
            });
        }];
    });
}
@end
int main(int argc,char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(SmokeDelegate.class)); }
}
