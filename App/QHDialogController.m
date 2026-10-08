#import "QHDialogController.h"
#import "QHVisualComponents.h"

static UIColor *DColor(unsigned light, unsigned dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        unsigned rgb=trait.userInterfaceStyle==UIUserInterfaceStyleDark ? dark : light;
        return [UIColor colorWithRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
    }];
}
void QHConfigureModal(UIViewController *controller) {
    controller.modalPresentationStyle=UIModalPresentationFormSheet;
    // Swipe cancellation must not skip a caller's finishBusy/consent logic.
    controller.modalInPresentation=YES;
    UISheetPresentationController *sheet=controller.sheetPresentationController;
    sheet.detents=@[UISheetPresentationControllerDetent.largeDetent];
    sheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierLarge;
    sheet.prefersGrabberVisible=YES;
    sheet.preferredCornerRadius=28;
    sheet.prefersScrollingExpandsWhenScrolledToEdge=YES;
    controller.view.tintColor=DColor(0x5b54e8,0x9b95ff);
    if ([controller isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav=(UINavigationController *)controller;
        nav.navigationBar.prefersLargeTitles=NO;
        UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor=DColor(0xf3f2f8,0x13131a);
        appearance.shadowColor=UIColor.clearColor;
        appearance.titleTextAttributes=@{NSForegroundColorAttributeName:DColor(0x1b1b22,0xf0eff8)};
        nav.navigationBar.standardAppearance=appearance;
        nav.navigationBar.scrollEdgeAppearance=appearance;
    }
}
@interface QHDialogAction ()
@property(nonatomic,readwrite,copy) NSString *title;
@property(nonatomic,readwrite) UIAlertActionStyle style;
@property(nonatomic,copy,nullable) QHDialogHandler handler;
@end
@implementation QHDialogAction
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(QHDialogHandler)handler {
    QHDialogAction *action=[QHDialogAction new];
    action.title=title;action.style=style;action.handler=handler;
    return action;
}
@end
@interface QHDialogController ()
@property(nonatomic,strong) UIViewController *content;
@property(nonatomic,copy) NSString *detail;
@property(nonatomic) UIAlertControllerStyle dialogStyle;
@property(nonatomic,strong) NSMutableArray<QHDialogAction *> *mutableActions;
@property(nonatomic,strong) NSMutableArray<UITextField *> *mutableFields;
@property(nonatomic) BOOL resolving;
@property(nonatomic) BOOL contentBuilt;
@end
@implementation QHDialogController
+ (instancetype)dialogControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style {
    UIViewController *content=[UIViewController new];content.title=title;
    QHDialogController *dialog=[[self alloc] initWithRootViewController:content];
    dialog.modalPresentationStyle=UIModalPresentationFormSheet;
    dialog.modalInPresentation=YES;
    dialog.content=content;dialog.detail=message ?: @"";dialog.dialogStyle=style;
    dialog.mutableActions=[NSMutableArray array];dialog.mutableFields=[NSMutableArray array];
    return dialog;
}
- (NSArray<UITextField *> *)textFields { return [self.mutableFields copy]; }
- (NSArray<QHDialogAction *> *)actions { return [self.mutableActions copy]; }
- (void)addAction:(QHDialogAction *)action {
    NSAssert(!self.contentBuilt,@"Configure dialog actions before presentation");
    [self.mutableActions addObject:action];
}
- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *))configuration {
    NSAssert(!self.contentBuilt,@"Configure dialog fields before presentation");
    UITextField *field=[UITextField new];
    field.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.adjustsFontForContentSizeCategory=YES;
    field.borderStyle=UITextBorderStyleRoundedRect;
    field.textColor=DColor(0x1b1b22,0xf0eff8);
    field.backgroundColor=DColor(0xfaf9fe,0x242430);
    field.clearButtonMode=UITextFieldViewModeWhileEditing;
    if (configuration) configuration(field);
    [self.mutableFields addObject:field];
}
- (void)chooseAction:(QHDialogAction *)action {
    if (self.resolving || ![self.mutableActions containsObject:action]) return;
    self.resolving=YES;
    self.view.userInteractionEnabled=NO;
    [self.view endEditing:YES];
    // Keep self, actions and URL input fields alive until the existing handler
    // returns. It may intentionally hold a weak reference to this dialog.
    QHDialogController *keepAlive=self;
    [self dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:^{
        if (action.handler) action.handler(action);
        keepAlive.mutableActions=nil;
    }];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.contentBuilt) return;
    NSAssert(self.content && self.mutableActions && self.mutableFields,@"Dialog factory must configure content before first presentation");
    self.contentBuilt=YES;
    self.content.navigationItem.title=@""; // The card owns the single visible heading.
    QHConfigureModal(self);
    // A character-count heuristic alone underestimates Chinese diagnostics and
    // multi-row choices. Only genuinely short, simple alerts start compact.
    BOOL compact=self.dialogStyle==UIAlertControllerStyleAlert &&
        !self.mutableFields.count && self.mutableActions.count<=2 &&
        self.detail.length<500 && [self.detail rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location==NSNotFound &&
        !UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    if (compact) {
        self.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.mediumDetent,UISheetPresentationControllerDetent.largeDetent];
        self.sheetPresentationController.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierMedium;
    }
    UIView *view=self.content.view;
    view.backgroundColor=DColor(0xf3f2f8,0x13131a);
    UIScrollView *scroll=[UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;
    [view addSubview:scroll];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=14;
    stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:view.keyboardLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-18],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-36]
    ]];
    BOOL danger=NO;
    for (QHDialogAction *action in self.mutableActions) if (action.style==UIAlertActionStyleDestructive) danger=YES;
    UIStackView *intro=QHVCard();
    [intro addArrangedSubview:QHVInfo(self.content.title,self.detail,danger ? @"exclamationmark.shield" : @"doc.text",nil)];
    [stack addArrangedSubview:intro];
    if (self.mutableFields.count) {
        UIStackView *inputs=QHVCard();
        for (UITextField *field in self.mutableFields) {
            UILabel *label=[UILabel new];label.text=field.accessibilityLabel ?: field.placeholder;
            label.numberOfLines=0;label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
            label.adjustsFontForContentSizeCategory=YES;label.textColor=DColor(0x686875,0x9e9ea8);
            [inputs addArrangedSubview:label];[inputs addArrangedSubview:field];
            [field.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
        }
        [stack addArrangedSubview:inputs];
    }
    __weak typeof(self) weak=self;
    for (QHDialogAction *action in self.mutableActions) {
        if (action.style==UIAlertActionStyleCancel && self.mutableActions.count>1) {
            UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];
            [close setTitle:action.title forState:UIControlStateNormal];
            close.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
            close.titleLabel.adjustsFontForContentSizeCategory=YES;
            close.accessibilityLabel=action.title;
            [close.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
            [close.widthAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
            [close addAction:[UIAction actionWithHandler:^(__kindof UIAction *event) {
                (void)event;[weak chooseAction:action];
            }] forControlEvents:UIControlEventTouchUpInside];
            self.content.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithCustomView:close];
        } else if (self.dialogStyle==UIAlertControllerStyleActionSheet) {
            UIStackView *choice=QHVCard();
            [choice addArrangedSubview:QHVRow(action.title,nil,action.style==UIAlertActionStyleDestructive ? @"trash" : @"chevron.right",nil,
                action.style==UIAlertActionStyleDestructive,YES,^{ [weak chooseAction:action]; })];
            [stack addArrangedSubview:choice];
        } else {
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
            UIButtonConfiguration *configuration=UIButtonConfiguration.filledButtonConfiguration;
            configuration.title=action.title;
            configuration.baseBackgroundColor=action.style==UIAlertActionStyleDestructive ? DColor(0xb42336,0xff8995) : DColor(0x5b54e8,0x9b95ff);
            configuration.baseForegroundColor=DColor(0xffffff,0x13131a);
            configuration.cornerStyle=UIButtonConfigurationCornerStyleLarge;
            configuration.contentInsets=NSDirectionalEdgeInsetsMake(14,16,14,16);
            button.configuration=configuration;
            button.titleLabel.numberOfLines=0;button.titleLabel.adjustsFontForContentSizeCategory=YES;
            button.accessibilityLabel=action.title;
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:50].active=YES;
            [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *event) {
                (void)event;[weak chooseAction:action];
            }] forControlEvents:UIControlEventTouchUpInside];
            [stack addArrangedSubview:button];
        }
    }
}
@end
