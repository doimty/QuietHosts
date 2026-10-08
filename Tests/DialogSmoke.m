#import <UIKit/UIKit.h>
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

@interface QHDialogProbe : NSObject
@property(nonatomic,strong) UIViewController *presenter;
@property(nonatomic,strong) QHAppController *controller;
@property(nonatomic,strong) id keyboardObserver;
@property(nonatomic) CGRect keyboardFrame;
@property(nonatomic) BOOL keyboardShown;
@property(nonatomic,copy) void (^completion)(NSUInteger,NSUInteger);
@property(nonatomic) NSUInteger stage;
@property(nonatomic) NSUInteger checks;
@property(nonatomic) NSUInteger failures;
@property(nonatomic) NSUInteger confirmed;
@property(nonatomic) NSUInteger cancelled;
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
- (void)finishStage:(QHDialogController *)dialog stage:(NSUInteger)stage {
    NSString *target=(stage==0 || stage>=4) ? @"Cancel test" : @"Confirm test";
    UIControl *control=DialogControl(dialog.view,target);
    [self check:control!=nil name:@"real actionable control found"];
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.7*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self check:self.confirmed+self.cancelled==before+1 name:@"rapid duplicate click invokes exactly once"];
        [self check:self.presenter.presentedViewController==nil name:@"completed dialog dismissed"];
        if(self.presenter.presentedViewController) {
            [self.presenter dismissViewControllerAnimated:NO completion:^{[self next];}];
        } else [self next];
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
    QHDialogController *dialog=[QHDialogController dialogControllerWithTitle:@"统一弹层 / Modal test"
        message:detail preferredStyle:stage==2 ? UIAlertControllerStyleActionSheet : UIAlertControllerStyleAlert];
    [dialog loadViewIfNeeded];
    [self check:dialog.actions.count==0 && dialog.textFields.count==0 name:@"eager navigation view does not build content before configuration"];
    __weak QHDialogController *weakDialog=dialog;
    __weak typeof(self) weak=self;
    if(stage==3) {
        [dialog addTextFieldWithConfigurationHandler:^(UITextField *field){field.accessibilityLabel=@"URL";field.keyboardType=UIKeyboardTypeURL;}];
    }
    [dialog addAction:[QHDialogAction actionWithTitle:@"Cancel test" style:UIAlertActionStyleCancel handler:^(QHDialogAction *action){
        (void)action;weak.cancelled++;
        [weak check:weak.presenter.presentedViewController==nil name:@"cancel runs after dismissal"];
    }]];
    [dialog addAction:[QHDialogAction actionWithTitle:@"Confirm test" style:stage==1 ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault handler:^(QHDialogAction *action){
        (void)action;weak.confirmed++;
        [weak check:weak.presenter.presentedViewController==nil name:@"confirm runs after dismissal"];
        if(stage==3) [weak check:[weakDialog.textFields.firstObject.text isEqual:@"https://example.invalid/raw?private=mock"] name:@"weak URL fields survive handler"];
    }]];
    [self.presenter presentViewController:dialog animated:NO completion:^{
        [self check:dialog.modalInPresentation name:@"explicit cancel required"];
        [self check:dialog.sheetPresentationController.prefersGrabberVisible name:@"sheet chrome"];
        [self check:self.confirmed+self.cancelled==stage name:@"presentation has no implicit action"];
        if(stage>=4) {
            dialog.overrideUserInterfaceStyle=stage==4 ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
            if(@available(iOS 17.0,*)) dialog.traitOverrides.preferredContentSizeCategory=UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
            [dialog.view setNeedsLayout];[dialog.view layoutIfNeeded];
        }
        if(stage==0) [self snapshot:dialog.view name:@"dialog-message.png"];
        if(stage==1) [self snapshot:dialog.view name:@"dialog-danger.png"];
        if(stage==2) [self snapshot:dialog.view name:@"dialog-options.png"];
        if(stage!=3) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self finishStage:dialog stage:stage];});
            return;
        }
        self.keyboardShown=NO;
        self.keyboardObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardDidShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
            weak.keyboardShown=YES;weak.keyboardFrame=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        }];
        UITextField *field=dialog.textFields.firstObject;
        [self check:[field becomeFirstResponder] name:@"URL field becomes real first responder"];
        [field insertText:@"https://example.invalid/raw?private=mock"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            [self check:self.keyboardShown && CGRectGetHeight(self.keyboardFrame)>0 name:@"software keyboard actually shown"];
            [self check:field.isFirstResponder name:@"URL input remains first responder"];
            [dialog.view layoutIfNeeded];
            CGRect fieldRect=[field convertRect:field.bounds toView:dialog.view.window];
            CGRect keyboard=[dialog.view.window convertRect:self.keyboardFrame fromWindow:nil];
            [self check:CGRectGetMaxY(fieldRect)<=CGRectGetMinY(keyboard)+1 name:@"active input not hidden by keyboard"];
            [self snapshot:dialog.view.window name:@"dialog-url-keyboard.png"];
            NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
            [@"keyboard ready" writeToFile:[documents stringByAppendingPathComponent:@"software-keyboard-ready.flag"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [NSNotificationCenter.defaultCenter removeObserver:self.keyboardObserver];self.keyboardObserver=nil;
            // The CI driver captures the complete simulator display. The app's
            // own UIWindow renderer cannot include the separate keyboard window.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                [self finishStage:dialog stage:stage];
            });
        });
    }];
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
    [probe next];
}
