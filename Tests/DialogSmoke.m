#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#import "../App/QHDialogController.h"
#import "../App/QHAppController.h"
@interface QHAppController (DialogProbeAccess)
- (void)chooseImport:(BOOL)allowlist;
- (void)showDiagnostics:(BOOL)advanced;
@end
static UIControl *DialogControl(UIView *view,NSString *title) {
    if ([view isKindOfClass:UIControl.class] && [view.accessibilityLabel isEqual:title]) return (UIControl *)view;
    for (UIView *child in view.subviews) { UIControl *found=DialogControl(child,title);if(found)return found; }
    return nil;
}
static UIScrollView *DialogScroll(UIView *view) {
    if ([view isKindOfClass:UIScrollView.class]) return (UIScrollView *)view;
    for (UIView *child in view.subviews) { UIScrollView *found=DialogScroll(child);if(found)return found; }
    return nil;
}
// Real input contract shared by the smoke dialog and the real controller flow:
// the rounded holder keeps 12pt on both sides of the UITextField, at least 44pt
// of the field stays visible, and the field answers window hit testing.
static const CGFloat QHDialogFieldInset=12.0;
static const CGFloat QHDialogFieldMinimumHeight=44.0;
// Sampling tolerances. The removed 1.08 entrance transform deviates by ~0.08,
// forty times the scale tolerance, so a spring cannot pass by rounding.
static const CGFloat QHDialogScaleTolerance=0.002;
static const CGFloat QHDialogSizeTolerance=1.0;
static BOOL QHDialogHitIsFieldOrDescendant(UIView *hit,UIView *field) {
    for (UIView *view=hit;view;view=view.superview) if (view==field) return YES;
    return NO;
}
static BOOL QHDialogViewContains(UIView *ancestor,UIView *view) {
    for (UIView *candidate=view;candidate;candidate=candidate.superview) if (candidate==ancestor) return YES;
    return NO;
}
// Uniform scale of a transform; 0.0 means identity.
static CGFloat QHDialogScaleDeviation(CATransform3D transform) {
    CGFloat horizontal=sqrt(transform.m11*transform.m11+transform.m12*transform.m12);
    CGFloat vertical=sqrt(transform.m21*transform.m21+transform.m22*transform.m22);
    return MAX(fabs(horizontal-1.0),fabs(vertical-1.0));
}
static CGFloat QHDialogAffineScaleDeviation(CGAffineTransform transform) {
    CGFloat horizontal=sqrt(transform.a*transform.a+transform.b*transform.b);
    CGFloat vertical=sqrt(transform.c*transform.c+transform.d*transform.d);
    return MAX(fabs(horizontal-1.0),fabs(vertical-1.0));
}
// Result of inspecting one real UITextField inside its holder. Returned as data
// instead of asserted inline so the same detector can be pointed at a
// disposable fixture that reproduces the old missing-autoresizing-mask shape.
@interface QHDialogFieldArea : NSObject
@property(nonatomic) BOOL inWindow;
@property(nonatomic) BOOL framed;
@property(nonatomic) BOOL insetMatches;
@property(nonatomic) BOOL tallEnough;
@property(nonatomic) NSUInteger hitChecks;
@property(nonatomic) NSUInteger hitFailures;
@property(nonatomic,copy) NSString *detail;
- (BOOL)ok;
@end
@implementation QHDialogFieldArea
- (BOOL)ok {
    return self.framed && self.insetMatches && self.tallEnough && self.hitChecks>0 && self.hitFailures==0;
}
@end
static QHDialogFieldArea *QHDialogInspectField(UITextField *field,BOOL hitTestPoints) {
    QHDialogFieldArea *area=[QHDialogFieldArea new];
    if (![field isKindOfClass:UITextField.class]) { area.detail=@"field missing";return area; }
    UIView *holder=field.superview;
    CGRect fieldFrame=field.frame;
    CGRect holderBounds=holder.bounds;
    CGRect visible=CGRectIntersection(fieldFrame,holderBounds);
    area.inWindow=field.window!=nil && [field.window isKindOfClass:UIWindow.class];
    area.framed=holderBounds.size.width>0.0 && fieldFrame.size.width>0.0 && fieldFrame.size.height>0.0;
    area.insetMatches=area.framed &&
        fabs(CGRectGetMinX(fieldFrame)-QHDialogFieldInset)<=0.5 &&
        fabs(CGRectGetWidth(holderBounds)-CGRectGetMaxX(fieldFrame)-QHDialogFieldInset)<=0.5 &&
        CGRectGetMinY(fieldFrame)>=-0.5 &&
        CGRectGetMaxY(fieldFrame)<=CGRectGetHeight(holderBounds)+0.5;
    area.tallEnough=area.framed && fieldFrame.size.height>=QHDialogFieldMinimumHeight-0.5 &&
        !CGRectIsNull(visible) && CGRectGetHeight(visible)>=QHDialogFieldMinimumHeight-0.5;
    area.detail=[NSString stringWithFormat:@"holder=%@ field=%@ visible=%@",NSStringFromCGRect(holderBounds),
        NSStringFromCGRect(fieldFrame),CGRectIsNull(visible) ? @"empty" : NSStringFromCGRect(visible)];
    if (hitTestPoints && area.framed && area.inWindow && !CGRectIsNull(visible) &&
        visible.size.width>16.0 && visible.size.height>16.0) {
        UIWindow *window=field.window;
        CGPoint local[]={
            CGPointMake(CGRectGetMidX(visible),CGRectGetMidY(visible)),
            CGPointMake(CGRectGetMidX(visible),CGRectGetMinY(visible)+4.0),
            CGPointMake(CGRectGetMidX(visible),CGRectGetMaxY(visible)-4.0),
            CGPointMake(CGRectGetMinX(visible)+6.0,CGRectGetMidY(visible)),
            CGPointMake(CGRectGetMaxX(visible)-6.0,CGRectGetMidY(visible)),
            CGPointMake(CGRectGetMinX(visible)+CGRectGetWidth(visible)*0.3,CGRectGetMidY(visible)),
            CGPointMake(CGRectGetMinX(visible)+CGRectGetWidth(visible)*0.7,CGRectGetMidY(visible))
        };
        for (size_t index=0;index<sizeof(local)/sizeof(local[0]);index++) {
            // Points are holder coordinates; the window decides what they hit.
            UIView *hit=[window hitTest:[window convertPoint:local[index] fromView:holder] withEvent:nil];
            area.hitChecks++;
            if (!QHDialogHitIsFieldOrDescendant(hit,field)) area.hitFailures++;
        }
    }
    return area;
}
// Accumulated per-sample facts for one entrance or exit window. Only
// invariants are compared, never an absolute frame rate or a fixed duration.
@interface QHDialogMotionRecord : NSObject
@property(nonatomic) NSUInteger modelSamples;
@property(nonatomic) NSUInteger presentationSamples;
@property(nonatomic) NSUInteger sizeSamples;
@property(nonatomic) NSUInteger styleViolations;
@property(nonatomic) CGFloat maxModelScaleDeviation;
@property(nonatomic) CGFloat maxPresentationScaleDeviation;
@property(nonatomic) CGFloat maxBackgroundScaleDeviation;
@property(nonatomic) CGFloat maxBackgroundPresentationScaleDeviation;
@property(nonatomic) CGFloat maxPresentationBoundsDelta;
@property(nonatomic) CGFloat maxBackgroundBoundsDelta;
@property(nonatomic) CGFloat minWidth;
@property(nonatomic) CGFloat maxWidth;
@property(nonatomic) CGFloat minHeight;
@property(nonatomic) CGFloat maxHeight;
@property(nonatomic) NSTimeInterval firstSampleDelay;
@property(nonatomic) BOOL presentationCompleted;
@property(nonatomic) BOOL appearanceSampled;
@property(nonatomic) NSUInteger completedPresentationSamples;
- (void)sampleCard:(UIView *)card background:(UIView *)background dialog:(QHDialogController *)dialog elapsed:(NSTimeInterval)elapsed;
@end
@implementation QHDialogMotionRecord
- (void)sampleCard:(UIView *)card background:(UIView *)background dialog:(QHDialogController *)dialog elapsed:(NSTimeInterval)elapsed {
    if ([card isKindOfClass:UIView.class]) {
        if (self.modelSamples==0) self.firstSampleDelay=elapsed;
        self.modelSamples++;
        CGFloat deviation=QHDialogAffineScaleDeviation(card.transform);
        if (deviation>self.maxModelScaleDeviation) self.maxModelScaleDeviation=deviation;
        CGRect bounds=card.bounds;
        if (bounds.size.width>0.0 && bounds.size.height>0.0) {
            if (self.sizeSamples==0) {
                self.minWidth=self.maxWidth=bounds.size.width;
                self.minHeight=self.maxHeight=bounds.size.height;
            } else {
                self.minWidth=MIN(self.minWidth,bounds.size.width);self.maxWidth=MAX(self.maxWidth,bounds.size.width);
                self.minHeight=MIN(self.minHeight,bounds.size.height);self.maxHeight=MAX(self.maxHeight,bounds.size.height);
            }
            self.sizeSamples++;
            CALayer *presentation=card.layer.presentationLayer;
            if (presentation) {
                self.presentationSamples++;
                if (self.presentationCompleted) self.completedPresentationSamples++;
                CGFloat presented=QHDialogScaleDeviation(presentation.transform);
                if (presented>self.maxPresentationScaleDeviation) self.maxPresentationScaleDeviation=presented;
                CGFloat delta=fabs(presentation.bounds.size.width-bounds.size.width)+fabs(presentation.bounds.size.height-bounds.size.height);
                if (delta>self.maxPresentationBoundsDelta) self.maxPresentationBoundsDelta=delta;
            }
        }
    }
    if ([background isKindOfClass:UIView.class]) {
        CGFloat deviation=QHDialogAffineScaleDeviation(background.transform);
        if (deviation>self.maxBackgroundScaleDeviation) self.maxBackgroundScaleDeviation=deviation;
        CALayer *presentation=background.layer.presentationLayer;
        if (presentation) {
            CGFloat presented=QHDialogScaleDeviation(presentation.transform);
            if (presented>self.maxBackgroundPresentationScaleDeviation) self.maxBackgroundPresentationScaleDeviation=presented;
            CGFloat delta=fabs(presentation.bounds.size.width-background.bounds.size.width)+fabs(presentation.bounds.size.height-background.bounds.size.height);
            if (delta>self.maxBackgroundBoundsDelta) self.maxBackgroundBoundsDelta=delta;
        }
    }
    if (!dialog) return;
    // Keep the resolved shape stable across entrance and dismissal. This is
    // independent of whether UIKit stored the initial properties correctly.
    if (dialog.modalPresentationStyle!=UIModalPresentationOverFullScreen ||
        dialog.modalTransitionStyle!=UIModalTransitionStyleCrossDissolve) self.styleViolations++;
}
@end
// Records the last value that actually reached the UIKit setter. The replaced
// implementation kept the real property at FormSheet and answered the getters
// dynamically, so this spy sees the production assignment instead of the value
// a getter fabricates. The factory allocates through dynamic self, so calling
// it on this subclass really builds a spy.
@interface QHDialogSetterSpy : QHDialogController
@property(nonatomic) UIModalPresentationStyle lastStoredPresentationStyle;
@property(nonatomic) UIModalTransitionStyle lastStoredTransitionStyle;
@property(nonatomic) NSUInteger presentationAssignments;
@property(nonatomic) NSUInteger transitionAssignments;
@property(nonatomic,copy) void (^configuredAppearanceSample)(QHDialogController *);
@end
@implementation QHDialogSetterSpy
- (void)setModalPresentationStyle:(UIModalPresentationStyle)style {
    self.lastStoredPresentationStyle=style;self.presentationAssignments++;
    [super setModalPresentationStyle:style];
}
- (void)setModalTransitionStyle:(UIModalTransitionStyle)style {
    self.lastStoredTransitionStyle=style;self.transitionAssignments++;
    [super setModalTransitionStyle:style];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Production builds the card in super. Observe its initial transform here,
    // even when presentViewController returns before this lifecycle callback.
    void (^sample)(QHDialogController *)=self.configuredAppearanceSample;
    self.configuredAppearanceSample=nil;
    if (sample) sample(self);
}
@end

@interface QHDialogProbe : NSObject
@property(nonatomic,strong) UIViewController *presenter;
@property(nonatomic,strong) QHAppController *controller;
@property(nonatomic,strong) id keyboardObserver;
@property(nonatomic) CGRect keyboardFrame;
@property(nonatomic) BOOL keyboardShown;
@property(nonatomic,copy) NSString *keyboardReadyPath;
@property(nonatomic,copy) NSString *keyboardCapturedPath;
@property(nonatomic,copy) NSString *keyboardCaptureFailedPath;
@property(nonatomic,copy) void (^completion)(NSUInteger,NSUInteger);
@property(nonatomic) NSUInteger stage;
@property(nonatomic) NSUInteger checks;
@property(nonatomic) NSUInteger failures;
@property(nonatomic) NSUInteger confirmed;
@property(nonatomic) NSUInteger cancelled;
@property(nonatomic) BOOL exitStartedWhilePresented;
- (void)next;
- (void)verifyDetectors;
- (void)checkFieldArea:(UITextField *)field name:(NSString *)name;
- (void)checkRealPresentationConfiguration:(QHDialogController *)dialog centered:(BOOL)centered phase:(NSString *)phase;
- (void)sampleMotion:(QHDialogMotionRecord *)record card:(UIView *)card background:(UIView *)background dialog:(QHDialogController *)dialog started:(NSTimeInterval)started;
- (void)sampleEntranceUntil:(NSTimeInterval)deadline record:(QHDialogMotionRecord *)record card:(UIView *)card background:(UIView *)background dialog:(QHDialogController *)dialog started:(NSTimeInterval)started completion:(void (^)(void))completion;
- (void)sampleExitWithRecord:(QHDialogMotionRecord *)record card:(UIView *)card background:(UIView *)background dialog:(QHDialogController *)dialog started:(NSTimeInterval)started before:(NSUInteger)before;
- (void)checkEntranceRecord:(QHDialogMotionRecord *)record card:(UIView *)card dialog:(QHDialogController *)dialog;
- (void)checkExitRecord:(QHDialogMotionRecord *)record dialog:(QHDialogController *)dialog;
- (void)completeDismissalChecks:(NSUInteger)before;
- (void)watchCenteredExit:(QHDialogController *)dialog stage:(NSUInteger)stage before:(NSUInteger)before;
@end
@implementation QHDialogProbe
- (void)check:(BOOL)ok name:(NSString *)name {
    self.checks++;if(!ok){self.failures++;NSLog(@"DIALOG FAIL %@",name);}
}
- (void)snapshot:(UIView *)view name:(NSString *)name {
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:view.bounds];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
        (void)context;[view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }];
    NSString *directory=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    [UIImagePNGRepresentation(image) writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES];
}
- (void)verifyDetectors {
    // The gate must not pass unconditionally. A disposable fixture reproduces
    // the old defect shapes (no autoresizing-mask change, no frame) and the
    // detectors must flag them; an identity transform must stay stable while a
    // 1.08 card must be reported as scaled. No product view is touched.
    UIView *holder=[UIView new];
    holder.frame=CGRectMake(0,0,300,QHDialogFieldMinimumHeight);
    UITextField *unfixed=[UITextField new];
    [holder addSubview:unfixed];
    QHDialogFieldArea *unfixedArea=QHDialogInspectField(unfixed,NO);
    NSLog(@"QH_DIALOG detector fixture unfixed %@",unfixedArea.detail);
    [self check:!unfixedArea.framed name:@"field-area detector rejects the unfixed autoresizing-mask shape"];
    [self check:!unfixedArea.ok name:@"field-area detector does not pass the unfixed shape unconditionally"];
    UIView *fixedHolder=[UIView new];
    fixedHolder.frame=CGRectMake(0,0,300,QHDialogFieldMinimumHeight);
    UITextField *fixedField=[UITextField new];
    fixedField.translatesAutoresizingMaskIntoConstraints=NO;
    fixedField.frame=CGRectMake(QHDialogFieldInset,0,300-2*QHDialogFieldInset,QHDialogFieldMinimumHeight);
    [fixedHolder addSubview:fixedField];
    QHDialogFieldArea *fixedArea=QHDialogInspectField(fixedField,NO);
    [self check:fixedArea.framed && fixedArea.insetMatches && fixedArea.tallEnough name:@"field-area detector accepts correctly inset field geometry"];
    [self check:QHDialogAffineScaleDeviation(CGAffineTransformIdentity)<=QHDialogScaleTolerance name:@"scale detector reports an unscaled card as stable"];
    [self check:QHDialogAffineScaleDeviation(CGAffineTransformMakeScale(1.08,1.08))>QHDialogScaleTolerance name:@"scale detector reports the old 1.08 card as scaled"];
    [self check:QHDialogScaleDeviation(CATransform3DMakeScale(1.08,1.08,1.0))>QHDialogScaleTolerance name:@"presentation-layer scale detector reports a 1.08 card as scaled"];
    NSLog(@"QH_DIALOG detector fixtures fixed=%@ result=%@",NSStringFromCGRect(fixedField.frame),fixedArea.detail);
}
- (void)checkFieldArea:(UITextField *)field name:(NSString *)name {
    UIView *holder=field.superview;
    [self check:[holder isKindOfClass:UIView.class] name:[name stringByAppendingString:@" is hosted by the rounded input holder"]];
    QHDialogFieldArea *area=QHDialogInspectField(field,YES);
    NSLog(@"QH_DIALOG input %@ %@ hitFailures=%lu hitChecks=%lu",name,area.detail,(unsigned long)area.hitFailures,(unsigned long)area.hitChecks);
    [self check:area.inWindow name:[name stringByAppendingString:@" lives in the real UIWindow before the keyboard appears"]];
    [self check:area.framed name:[name stringByAppendingString:@" has a non-empty real frame inside the holder"]];
    [self check:area.insetMatches name:[name stringByAppendingString:@" keeps the 12pt holder insets on both sides"]];
    [self check:area.tallEnough name:[name stringByAppendingString:@" keeps at least 44pt of visible height"]];
    [self check:area.hitChecks>=4 && area.hitFailures==0 name:[name stringByAppendingString:@" answers window hitTest at every valid text point"]];
}
- (void)checkRealPresentationConfiguration:(QHDialogController *)dialog centered:(BOOL)centered phase:(NSString *)phase {
    // A spy observes values that actually reach UIKit, not just what a
    // potentially overridden getter reports. Real controller flows still
    // verify the resulting public presentation properties below.
    if ([dialog isKindOfClass:QHDialogSetterSpy.class]) {
        QHDialogSetterSpy *spy=(QHDialogSetterSpy *)dialog;
        UIModalPresentationStyle expected=centered ? UIModalPresentationOverFullScreen : UIModalPresentationFormSheet;
        UIModalTransitionStyle transition=centered ? UIModalTransitionStyleCrossDissolve : UIModalTransitionStyleCoverVertical;
        [self check:spy.presentationAssignments>0 && spy.lastStoredPresentationStyle==expected
              name:[phase stringByAppendingString:@" expected style reached the actual UIKit setter"]];
        [self check:spy.transitionAssignments>0 && spy.lastStoredTransitionStyle==transition
              name:[phase stringByAppendingString:@" expected transition reached the actual UIKit setter"]];
    }
    if (centered) {
        [self check:dialog.modalPresentationStyle==UIModalPresentationOverFullScreen name:[phase stringByAppendingString:@" short confirmation already stores OverFullScreen"]];
        [self check:dialog.modalTransitionStyle==UIModalTransitionStyleCrossDissolve name:[phase stringByAppendingString:@" short confirmation already stores cross dissolve"]];
    } else {
        [self check:dialog.modalPresentationStyle==UIModalPresentationFormSheet name:[phase stringByAppendingString:@" sheet flows already store FormSheet"]];
        [self check:dialog.modalTransitionStyle==UIModalTransitionStyleCoverVertical name:[phase stringByAppendingString:@" sheet flows already store the cover vertical transition"]];
    }
}
- (void)sampleMotion:(QHDialogMotionRecord *)record card:(UIView *)card background:(UIView *)background dialog:(QHDialogController *)dialog started:(NSTimeInterval)started {
    [record sampleCard:card background:background dialog:dialog elapsed:([NSDate timeIntervalSinceReferenceDate]-started)];
}
- (void)sampleEntranceUntil:(NSTimeInterval)deadline record:(QHDialogMotionRecord *)record card:(UIView *)card background:(UIView *)background dialog:(QHDialogController *)dialog started:(NSTimeInterval)started completion:(void (^)(void))completion {
    // Observe the whole entrance, not only its completion. The deadline is a
    // safety cap, never a performance threshold or an assumed frame rate.
    // presentViewController can return before viewWillAppear builds the card.
    // Resolve it on every tick instead of holding an initial nil forever.
    card=(UIView *)[dialog valueForKey:@"centeredCard"];
    [self sampleMotion:record card:card background:background dialog:dialog started:started];
    BOOL settled=record.presentationCompleted && record.completedPresentationSamples>=2;
    if (settled || [NSDate timeIntervalSinceReferenceDate]>=deadline) {
        [self check:settled name:@"animated presentation completed and a displayed final state was sampled"];
        completion();return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.016*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self sampleEntranceUntil:deadline record:record card:card background:background dialog:dialog started:started completion:completion];
    });
}
- (void)sampleExitWithRecord:(QHDialogMotionRecord *)record card:(UIView *)card background:(UIView *)background dialog:(QHDialogController *)dialog started:(NSTimeInterval)started before:(NSUInteger)before {
    [self sampleMotion:record card:card background:background dialog:dialog started:started];
    NSTimeInterval elapsed=[NSDate timeIntervalSinceReferenceDate]-started;
    // Settle on observed facts, not on an assumed animation duration: the
    // action ran exactly once and the presenter already dropped the dialog.
    BOOL settled=self.confirmed+self.cancelled>=before+1 && self.presenter.presentedViewController==nil;
    if (settled || elapsed>=5.0) {
        [self check:settled name:@"animated dismissal completed before its safety deadline"];
        [self checkExitRecord:record dialog:dialog];
        // Back to the animation state the remaining stages assume.
        [UIView setAnimationsEnabled:NO];
        [self completeDismissalChecks:before];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.016*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self sampleExitWithRecord:record card:card background:background dialog:dialog started:started before:before];
    });
}
- (void)checkEntranceRecord:(QHDialogMotionRecord *)record card:(UIView *)card dialog:(QHDialogController *)dialog {
    // A. No spring entrance: the card, its presentation layer and the dimming
    // background hold one geometry from the animated transition on. Alpha fades
    // of the cross dissolve are deliberately not inspected.
    [self check:record.appearanceSampled name:@"configured appearance sampled before viewDidAppear"];
    [self check:record.modelSamples>0 && record.completedPresentationSamples>=2 name:@"entrance window observed both initial and displayed final state"];
    [self check:record.presentationSamples>=1 name:@"entrance window observed the card presentation layer"];
    [self check:record.maxModelScaleDeviation<=QHDialogScaleTolerance name:@"centered card model transform never scales on entrance"];
    [self check:record.maxPresentationScaleDeviation<=QHDialogScaleTolerance name:@"centered card presentation layer never springs on entrance"];
    [self check:record.sizeSamples>=1 && record.maxWidth-record.minWidth<=QHDialogSizeTolerance &&
        record.maxHeight-record.minHeight<=QHDialogSizeTolerance name:@"centered card keeps one stable bounds size through entrance"];
    [self check:record.maxPresentationBoundsDelta<=QHDialogSizeTolerance name:@"presented card bounds match the model bounds"];
    [self check:record.styleViolations==0 name:@"centered card never flips back to a sheet during entrance"];
    [self check:record.maxBackgroundScaleDeviation<=QHDialogScaleTolerance &&
        record.maxBackgroundPresentationScaleDeviation<=QHDialogScaleTolerance name:@"dimming background is never scaled"];
    [self check:record.maxBackgroundBoundsDelta<=QHDialogSizeTolerance name:@"dimming background size matches its model size"];
    [self check:[card isKindOfClass:UIView.class] && QHDialogViewContains(dialog.view,card) &&
        card.window!=nil && card.window==dialog.view.window name:@"centered card is a real view in the presented window"];
    [self check:card.bounds.size.width>0.0 && card.bounds.size.width<=321.0 name:@"centered card keeps the compact card width"];
    [self check:dialog.modalPresentationStyle==UIModalPresentationOverFullScreen &&
        dialog.modalTransitionStyle==UIModalTransitionStyleCrossDissolve name:@"short confirmation presents as a real full-screen overlay with cross dissolve"];
    [self check:fabs(CGRectGetWidth(dialog.view.bounds)-CGRectGetWidth(dialog.view.window.bounds))<=1.0 &&
        fabs(CGRectGetHeight(dialog.view.bounds)-CGRectGetHeight(dialog.view.window.bounds))<=1.0 name:@"short confirmation fills the window instead of shrinking into a sheet"];
    NSLog(@"QH_DIALOG entrance model=%lu presentation=%lu first=%.3f modelDev=%.4f presentationDev=%.4f sizes=%lu width=%.2f..%.2f height=%.2f..%.2f backgroundDev=%.4f styleViolations=%lu",
        (unsigned long)record.modelSamples,(unsigned long)record.presentationSamples,record.firstSampleDelay,
        (double)record.maxModelScaleDeviation,(double)record.maxPresentationScaleDeviation,(unsigned long)record.sizeSamples,
        (double)record.minWidth,(double)record.maxWidth,(double)record.minHeight,(double)record.maxHeight,
        (double)record.maxBackgroundScaleDeviation,(unsigned long)record.styleViolations);
}
- (void)checkExitRecord:(QHDialogMotionRecord *)record dialog:(QHDialogController *)dialog {
    [self check:record.modelSamples>0 name:@"exit window observed the card state"];
    [self check:record.presentationSamples>=1 name:@"exit window observed the card presentation layer"];
    [self check:record.maxModelScaleDeviation<=QHDialogScaleTolerance name:@"centered card model transform never scales while dismissing"];
    [self check:record.maxPresentationScaleDeviation<=QHDialogScaleTolerance name:@"centered card presentation layer never springs while dismissing"];
    [self check:record.maxPresentationBoundsDelta<=QHDialogSizeTolerance name:@"dismissing card bounds match the model bounds"];
    [self check:record.styleViolations==0 name:@"centered card never flips back to a sheet while dismissing"];
    [self check:record.maxBackgroundScaleDeviation<=QHDialogScaleTolerance &&
        record.maxBackgroundPresentationScaleDeviation<=QHDialogScaleTolerance name:@"dismissing background is never scaled"];
    [self check:self.exitStartedWhilePresented name:@"exit window really covered the animated dismissal"];
    NSLog(@"QH_DIALOG exit model=%lu presentation=%lu modelDev=%.4f presentationDev=%.4f styles=%lu stillPresented=%d style=%ld",
        (unsigned long)record.modelSamples,(unsigned long)record.presentationSamples,(double)record.maxModelScaleDeviation,
        (double)record.maxPresentationScaleDeviation,(unsigned long)record.styleViolations,self.exitStartedWhilePresented,
        (long)dialog.modalPresentationStyle);
}
- (void)completeDismissalChecks:(NSUInteger)before {
    [self check:self.confirmed+self.cancelled==before+1 name:@"rapid duplicate click invokes exactly once"];
    [self check:self.presenter.presentedViewController==nil name:@"completed dialog dismissed"];
    if(self.presenter.presentedViewController) {
        [self.presenter dismissViewControllerAnimated:NO completion:^{[self next];}];
    } else [self next];
}
- (void)watchCenteredExit:(QHDialogController *)dialog stage:(NSUInteger)stage before:(NSUInteger)before {
    QHDialogMotionRecord *exitRecord=[QHDialogMotionRecord new];
    UIView *card=(UIView *)[dialog valueForKey:@"centeredCard"];
    UIView *background=dialog.view;
    NSTimeInterval started=[NSDate timeIntervalSinceReferenceDate];
    self.exitStartedWhilePresented=(self.presenter.presentedViewController==dialog);
    NSLog(@"QH_DIALOG stage=%lu exit watch started while presented=%d",(unsigned long)stage,self.exitStartedWhilePresented);
    [self sampleExitWithRecord:exitRecord card:card background:background dialog:dialog started:started before:before];
}
- (void)finishStage:(QHDialogController *)dialog stage:(NSUInteger)stage {
    NSString *target=(stage==0 || stage>=4) ? @"Cancel test" : @"Confirm test";
    UIControl *control=DialogControl(dialog.view,target);
    [self check:control!=nil name:@"real actionable control found"];
    if(stage<=1) {
        UIControl *cancel=DialogControl(dialog.view,@"Cancel test");
        UIControl *confirm=DialogControl(dialog.view,@"Confirm test");
        [self check:cancel && confirm name:@"paired actions are reachable controls"];
        if(cancel && confirm) {
            CGRect primaryRect=[confirm convertRect:confirm.bounds toView:dialog.view];
            CGRect cancelRect=[cancel convertRect:cancel.bounds toView:dialog.view];
            [self check:CGRectGetMidY(primaryRect)<CGRectGetMidY(cancelRect) name:@"primary action sits above the text-only cancel"];
            [self check:fabs(CGRectGetMidX(primaryRect)-CGRectGetMidX(cancelRect))<=1.0 name:@"stacked dialog actions share one centered column"];
            [self check:fabs(CGRectGetWidth(primaryRect)-CGRectGetWidth(cancelRect))<=1.0 name:@"stacked dialog actions share the card width"];
            [self check:CGRectGetHeight(primaryRect)>=45.0 && CGRectGetHeight(cancelRect)>=43.0 name:@"stacked dialog actions keep touch-friendly heights"];
        }
    }
    if(stage>=4) {
        UIScrollView *scroll=DialogScroll(dialog.topViewController.view);
        [self check:scroll.contentSize.height>scroll.bounds.size.height name:@"long diagnostics are scrollable"];
        UIControl *confirm=DialogControl(dialog.view,@"Confirm test");
        CGRect rect=[confirm convertRect:confirm.bounds toView:scroll];
        [scroll scrollRectToVisible:rect animated:NO];[dialog.view layoutIfNeeded];
        [self check:CGRectGetMaxY(rect)<=CGRectGetMaxY(scroll.bounds)+1 name:@"long-text confirmation reachable by scrolling"];
        [self snapshot:dialog.view name:stage==4 ? @"dialog-long-light.png" : @"dialog-long-dark.png"];
    }
    NSUInteger before=self.confirmed+self.cancelled;
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    if(stage<=1) {
        // Animated short confirmations keep their dismissal under observation:
        // the shared duplicate-click and dismissal checks still run, but only
        // once the exit really happened.
        [self watchCenteredExit:dialog stage:stage before:before];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.7*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self completeDismissalChecks:before];
    });
}
- (void)waitForKeyboardCapture:(QHDialogController *)dialog stage:(NSUInteger)stage attempt:(NSUInteger)attempt {
    NSFileManager *files=NSFileManager.defaultManager;
    BOOL captured=[files fileExistsAtPath:self.keyboardCapturedPath];
    BOOL failed=[files fileExistsAtPath:self.keyboardCaptureFailedPath];
    // 120s bound: the CI driver budget for one screenshot on a loaded runner
    // can exceed the old 20s window; a failure marker still exits immediately.
    if(captured || failed || attempt>=600) {
        NSString *reason=failed ? @"driver reported capture failure" : (captured ? @"capture completed" : @"capture flag never appeared; driver budget exceeded");
        [self check:captured name:[NSString stringWithFormat:@"full-screen capture completed before keyboard dismissal (%@)",reason]];
        if(!captured) {
            NSString *ready=[files fileExistsAtPath:self.keyboardReadyPath] ? @"ready flag present" : @"ready flag missing";
            NSLog(@"DIALOG NOTE keyboard capture diagnostics: %@; %@",reason,ready);
        }
        [self check:dialog.textFields.lastObject.isFirstResponder name:@"keyboard focus retained during screen capture"];
        // The field that is not focused must survive focus switching intact.
        [self check:[dialog.textFields.firstObject.text isEqual:@"Mock source name"] name:@"unfocused source name field keeps its text during capture"];
        [self finishStage:dialog stage:stage];return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self waitForKeyboardCapture:dialog stage:stage attempt:attempt+1];
    });
}
- (void)next {
    if (self.stage>=6) { [self controllerFlow:0];return; }
    NSUInteger stage=self.stage++;
    NSString *detail=@"MOCK ONLY: 完整诊断与确认说明，不读取或写入 Hosts。";
    if(stage>=4) {
        NSMutableString *longText=[NSMutableString new];
        for(NSUInteger index=0;index<30;index++) [longText appendFormat:@"诊断 %lu：target-conflict。保留原始备份，不会自动修复路径或覆盖陌生文件。\n",(unsigned long)index];
        detail=longText;
    }
    QHDialogController *dialog=[QHDialogSetterSpy dialogControllerWithTitle:@"统一弹层 / Modal test"
        message:detail preferredStyle:stage==2 ? UIAlertControllerStyleActionSheet : UIAlertControllerStyleAlert];
    [dialog loadViewIfNeeded];
    [self check:dialog.actions.count==0 && dialog.textFields.count==0 name:@"eager navigation view does not build content before configuration"];
    __weak QHDialogController *weakDialog=dialog;
    __weak typeof(self) weak=self;
    if(stage==3) {
        // Real HTTPS shape: source name first, URL last (two distinct fields).
        [dialog addTextFieldWithConfigurationHandler:^(UITextField *field){field.accessibilityLabel=@"Source name";field.autocorrectionType=UITextAutocorrectionTypeNo;}];
        [dialog addTextFieldWithConfigurationHandler:^(UITextField *field){field.accessibilityLabel=@"URL";field.keyboardType=UIKeyboardTypeURL;}];
    }
    [dialog addAction:[QHDialogAction actionWithTitle:@"Cancel test" style:UIAlertActionStyleCancel handler:^(QHDialogAction *action){
        (void)action;weak.cancelled++;
        [weak check:weak.presenter.presentedViewController==nil name:@"cancel runs after dismissal"];
    }]];
    [dialog addAction:[QHDialogAction actionWithTitle:@"Confirm test" style:stage==1 ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault handler:^(QHDialogAction *action){
        (void)action;weak.confirmed++;
        [weak check:weak.presenter.presentedViewController==nil name:@"confirm runs after dismissal"];
        if(stage==3) {
            // The URL lives in the last field and must be distinguishable from
            // the source name that the first field carries.
            [weak check:[weakDialog.textFields.lastObject.text isEqual:@"https://example.invalid/raw?private=mock"] name:@"weak URL fields survive handler"];
            [weak check:[weakDialog.textFields.firstObject.text isEqual:@"Mock source name"] name:@"source name text survives the handler as its own value"];
            [weak check:![weakDialog.textFields.firstObject.text isEqual:weakDialog.textFields.lastObject.text] name:@"handled fields keep two different values"];
        }
    }]];
    // The stored presentation must already be the real one; the previous
    // implementation returned it from dynamic getters and stored nothing.
    [self checkRealPresentationConfiguration:dialog centered:stage<=1 phase:@"before present"];
    if(stage<=1) [UIView setAnimationsEnabled:YES];
    QHDialogMotionRecord *entrance=[QHDialogMotionRecord new];
    NSTimeInterval entranceStarted=[NSDate timeIntervalSinceReferenceDate];
    UIView *entranceBackground=dialog.view;
    if(stage<=1) {
        ((QHDialogSetterSpy *)dialog).configuredAppearanceSample=^(QHDialogController *appearing) {
            UIView *card=(UIView *)[appearing valueForKey:@"centeredCard"];
            [self check:[card isKindOfClass:UIView.class] name:@"centered card is reachable for KVC animation sampling"];
            entrance.appearanceSampled=[card isKindOfClass:UIView.class];
            [self sampleMotion:entrance card:card background:appearing.view dialog:appearing started:entranceStarted];
        };
    }
    NSLog(@"QH_DIALOG stage=%lu reduceMotion=%d animations=%d",(unsigned long)stage,UIAccessibilityIsReduceMotionEnabled(),[UIView areAnimationsEnabled]);
    [self.presenter presentViewController:dialog animated:stage<=1 completion:^{
        [self check:dialog.modalInPresentation name:@"explicit cancel required"];
        if(stage<=1) {
            [self check:dialog.usesCenteredConfirmation name:@"short confirmation uses the centered card"];
            [self check:dialog.sheetPresentationController==nil name:@"short confirmation is not a bottom sheet"];
            [self check:dialog.navigationBarHidden name:@"short confirmation hides navigation chrome"];
        } else {
            [self check:dialog.sheetPresentationController.prefersGrabberVisible name:@"sheet chrome"];
            BOOL menuDetent=[dialog.sheetPresentationController.selectedDetentIdentifier isEqual:@"qh.menu"] ||
                             [dialog.sheetPresentationController.selectedDetentIdentifier isEqual:UISheetPresentationControllerDetentIdentifierMedium];
            BOOL expectedDetent=stage==2 ? menuDetent :
                [dialog.sheetPresentationController.selectedDetentIdentifier isEqual:UISheetPresentationControllerDetentIdentifierLarge];
            [self check:expectedDetent name:@"correct opening detent without manual dragging"];
            NSString *navTitle=dialog.topViewController.navigationItem.title;
            BOOL expectedNavTitle=stage==2 ? navTitle.length==0 : [navTitle isEqual:@"统一弹层 / Modal test"];
            [self check:expectedNavTitle name:@"form sheet shows its title in the navigation bar, menu hides the empty bar"];
        }
        [self check:self.confirmed+self.cancelled==stage name:@"presentation has no implicit action"];
        if(stage>=4) {
            dialog.overrideUserInterfaceStyle=stage==4 ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
            if(@available(iOS 17.0,*)) dialog.traitOverrides.preferredContentSizeCategory=UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
            [dialog.view setNeedsLayout];[dialog.view layoutIfNeeded];
        }
        if(stage<=1) {
            // The continuous sampler already covers entrance. Completion is
            // the observed end marker, not the point where sampling starts.
            entrance.presentationCompleted=YES;
            return;
        }
        if(stage==2) [self snapshot:dialog.view name:@"dialog-options.png"];
        if(stage!=3) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self finishStage:dialog stage:stage];});
            return;
        }
        // A. HTTPS-shaped input. Inspect both real hit areas in the window
        // before any keyboard exists, then prove that each field can take focus
        // and text in turn instead of only calling becomeFirstResponder.
        NSArray<UITextField *> *fields=dialog.textFields;
        [self check:fields.count==2 name:@"HTTPS-shaped dialog configures exactly two input fields"];
        UITextField *nameField=fields.firstObject;
        UITextField *urlField=fields.lastObject;
        [self check:nameField!=nil && urlField!=nil && nameField!=urlField name:@"source name and URL are two distinct fields"];
        [self check:[nameField.accessibilityLabel isEqual:@"Source name"] name:@"first input is the source name field"];
        [self check:[urlField.accessibilityLabel isEqual:@"URL"] name:@"last input is the URL field with its own configuration"];
        [self check:!self.keyboardShown && !nameField.isFirstResponder && !urlField.isFirstResponder name:@"field hit areas inspected before the keyboard appears"];
        [dialog.view layoutIfNeeded];
        [self checkFieldArea:nameField name:@"source name field"];
        [self checkFieldArea:urlField name:@"URL field"];
        self.keyboardShown=NO;
        NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        self.keyboardReadyPath=[documents stringByAppendingPathComponent:@"software-keyboard-ready.flag"];
        self.keyboardCapturedPath=[documents stringByAppendingPathComponent:@"software-keyboard-captured.flag"];
        self.keyboardCaptureFailedPath=[documents stringByAppendingPathComponent:@"software-keyboard-capture-failed.flag"];
        self.keyboardObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardDidShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
            weak.keyboardShown=YES;weak.keyboardFrame=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        }];
        [self check:[nameField becomeFirstResponder] name:@"source name field becomes the real first responder"];
        [nameField insertText:@"Mock source name"];
        [self check:[nameField.text isEqual:@"Mock source name"] name:@"source name text lands through the real first responder"];
        [self check:[urlField becomeFirstResponder] name:@"focus switches to the URL field inside the same dialog"];
        [self check:urlField.isFirstResponder && !nameField.isFirstResponder name:@"focus switching stays exclusive between both fields"];
        [urlField insertText:@"https://example.invalid/raw?private=mock"];
        [self check:[urlField.text isEqual:@"https://example.invalid/raw?private=mock"] name:@"URL text lands in the last field"];
        [self check:![nameField.text isEqual:urlField.text] name:@"both fields keep their own text after focus switching"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            [self check:self.keyboardShown && CGRectGetHeight(self.keyboardFrame)>0 name:@"software keyboard actually shown"];
            [self check:urlField.isFirstResponder name:@"URL input remains first responder"];
            [dialog.view layoutIfNeeded];
            CGRect fieldRect=[urlField convertRect:urlField.bounds toView:dialog.view.window];
            CGRect keyboard=[dialog.view.window convertRect:self.keyboardFrame fromWindow:nil];
            [self check:CGRectGetMaxY(fieldRect)<=CGRectGetMinY(keyboard)+1 name:@"active input not hidden by keyboard"];
            [self snapshot:dialog.view.window name:@"dialog-url-keyboard.png"];
            [@"keyboard ready" writeToFile:self.keyboardReadyPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [NSNotificationCenter.defaultCenter removeObserver:self.keyboardObserver];self.keyboardObserver=nil;
            // The CI driver captures the complete simulator display. The app's
            // own UIWindow renderer cannot include the separate keyboard window.
            [self waitForKeyboardCapture:dialog stage:stage attempt:0];
        });
    }];
    if(stage<=1) {
        // UIKit may defer construction; the spy samples the true initial
        // state in viewWillAppear and each tick re-resolves the card.
        UIView *card=(UIView *)[dialog valueForKey:@"centeredCard"];
        [self sampleEntranceUntil:[NSDate timeIntervalSinceReferenceDate]+5.0 record:entrance card:card background:entranceBackground dialog:dialog started:entranceStarted completion:^{
            [self checkEntranceRecord:entrance card:(UIView *)[dialog valueForKey:@"centeredCard"] dialog:dialog];
            [self snapshot:dialog.view name:stage==0 ? @"dialog-message.png" : @"dialog-danger.png"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self finishStage:dialog stage:stage];});
        }];
    }
}
- (void)click:(NSString *)key in:(UIViewController *)dialog {
    UIControl *control=DialogControl(dialog.view,NSLocalizedString(key,nil));
    [self check:control!=nil name:[@"real controller action: " stringByAppendingString:key]];
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)finishControllerFlow:(NSUInteger)flow {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.7*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self check:![[self.controller valueForKey:@"busy"] boolValue] name:@"real controller busy released after cancel/error"];
        [self check:self.presenter.presentedViewController==nil name:@"real controller chain completely dismissed"];
        if(self.presenter.presentedViewController) {
            [self.presenter dismissViewControllerAnimated:NO completion:^{[self controllerFlow:flow+1];}];
        } else [self controllerFlow:flow+1];
    });
}
- (void)controllerFlow:(NSUInteger)flow {
    if(flow>=4) {self.completion(self.checks,self.failures);return;}
    [self check:![[self.controller valueForKey:@"busy"] boolValue] name:@"controller idle before next flow"];
    if(flow==2) [self.controller showDiagnostics:YES];
    else [self.controller chooseImport:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        UIViewController *first=self.presenter.presentedViewController;
        [self check:[first isKindOfClass:QHDialogController.class] name:@"controller uses unified dialog"];
        BOOL importMenuDetent=[first.sheetPresentationController.selectedDetentIdentifier isEqual:@"qh.menu"] ||
                                 [first.sheetPresentationController.selectedDetentIdentifier isEqual:UISheetPresentationControllerDetentIdentifierMedium];
        BOOL importOrDiagnosticsDetent=flow==0 ? importMenuDetent :
            [first.sheetPresentationController.selectedDetentIdentifier isEqual:UISheetPresentationControllerDetentIdentifierLarge];
        [self check:importOrDiagnosticsDetent name:@"real import and diagnostics open expanded without a swipe"];
        if(flow==0 || flow==2) [self snapshot:first.view name:flow==0 ? @"dialog-real-import-expanded.png" : @"dialog-real-diagnostics-expanded.png"];
        if(flow==0) {
            [self check:[[self.controller valueForKey:@"busy"] boolValue] name:@"import owns busy until explicit cancel"];
            [self click:@"Cancel" in:first];[self finishControllerFlow:flow];return;
        }
        [self click:flow==2 ? @"Restore verified baseline" : @"HTTPS URL" in:first];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            QHDialogController *next=(QHDialogController *)self.presenter.presentedViewController;
            [self check:[next isKindOfClass:QHDialogController.class] && next!=first name:@"new sheet presented after previous dismissed"];
            [self check:[[self.controller valueForKey:@"busy"] boolValue] name:@"nested flow keeps busy until decision"];
            if(flow==2) {
                [self snapshot:next.view name:@"dialog-real-restore.png"];
                [self click:@"Cancel" in:next];[self finishControllerFlow:flow];return;
            }
            [self check:next.textFields.count==2 name:@"real URL dialog has name and URL inputs"];
            // The real HTTPS dialog must give the same real hit areas, without
            // focusing anything and without starting a download.
            BOOL realTwoFields=[next isKindOfClass:QHDialogController.class] && next.textFields.count==2;
            if(realTwoFields) {
                [next.view layoutIfNeeded];
                [self check:next.textFields.firstObject!=next.textFields.lastObject name:@"real HTTPS fields are two distinct inputs"];
                [self checkFieldArea:next.textFields.firstObject name:@"real source name field"];
                [self checkFieldArea:next.textFields.lastObject name:@"real URL field"];
            }
            if(flow==1) {
                [self click:@"Cancel" in:next];[self finishControllerFlow:flow];return;
            }
            next.textFields[0].text=@"Invalid URL smoke";
            next.textFields[1].text=@"not a valid https URL";
            [self click:@"Download and preview" in:next];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                UIViewController *error=self.presenter.presentedViewController;
                [self check:[error isKindOfClass:QHDialogController.class] && error!=next name:@"invalid URL returns unified error sheet without network"];
                [self check:![[self.controller valueForKey:@"busy"] boolValue] name:@"invalid input releases actual busy"];
                QHDialogController *message=(QHDialogController *)error;
                UIControl *close=DialogControl(message.view,NSLocalizedString(@"OK",nil));
                [self check:message.topViewController.navigationItem.title.length==0 name:@"one visible card title without duplicate navigation text"];
                [self check:message.topViewController.navigationItem.leftBarButtonItem==nil && CGRectGetHeight(close.bounds)>=44 name:@"single dismissal action is a reachable full-sized primary button"];
                [self snapshot:error.view name:@"dialog-real-error.png"];
                [self click:@"OK" in:error];[self finishControllerFlow:flow];
            });
        });
    });
}

@end
void QHRunDialogSmoke(QHAppController *controller,void (^completion)(NSUInteger,NSUInteger)) {
    QHDialogProbe *probe=[QHDialogProbe new];
    probe.controller=controller;probe.presenter=controller.rootController;probe.completion=completion;
    [probe verifyDetectors];
    [probe next];
}
