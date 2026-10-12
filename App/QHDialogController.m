#import "QHDialogController.h"
#import "QHVisualComponents.h"

static UIColor *DColor(unsigned light, unsigned dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        unsigned rgb=trait.userInterfaceStyle==UIUserInterfaceStyleDark ? dark : light;
        return [UIColor colorWithRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
    }];
}
void QHConfigureModal(UIViewController *controller) {
    // Centered confirmations get their own presentation; the generic chrome
    // must not force them back into a bottom sheet.
    if (![controller isKindOfClass:QHDialogController.class] ||
        ![(QHDialogController *)controller usesCenteredConfirmation]) {
        controller.modalPresentationStyle=UIModalPresentationFormSheet;
    }
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
@property(nonatomic,strong) UIStackView *centeredCard;
@property(nonatomic) BOOL resolvedCentered;
@property(nonatomic) BOOL entranceAnimated;
@end
/* Forward declaration: QHCenteredActionButton runs before the @implementation
 * and must be able to dispatch chooseAction: through the weak owner. */
@interface QHDialogController (QHDialogActions)
- (void)chooseAction:(QHDialogAction *)action;
@end

static BOOL QHCenteredConfirmationFor(UIAlertControllerStyle style, NSUInteger fields, NSUInteger actions,
                                      NSString *detail) {
    // Only genuinely short, simple alerts become centered cards. Chinese
    // diagnostics, multi-row choices and long previews stay in the sheet.
    return style==UIAlertControllerStyleAlert && fields==0 && actions>0 && actions<=2 &&
           detail.length<500 && [detail rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location==NSNotFound;
}

static UIButton *QHCenteredActionButton(QHDialogAction *action, BOOL primary, QHDialogController *owner) {
    __weak typeof(owner) weak=owner;
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration=UIButtonConfiguration.filledButtonConfiguration;
    configuration.title=action.title;
    if (primary) {
        configuration.baseBackgroundColor=action.style==UIAlertActionStyleDestructive ? DColor(0xb42336,0xff8995) : DColor(0x5b54e8,0x9b95ff);
        configuration.baseForegroundColor=DColor(0xffffff,0x13131a);
    } else {
        configuration.baseBackgroundColor=DColor(0xe9e7f6,0x2c2c3a);
        configuration.baseForegroundColor=DColor(0x5b54e8,0x9b95ff);
    }
    configuration.cornerStyle=UIButtonConfigurationCornerStyleLarge;
    configuration.contentInsets=NSDirectionalEdgeInsetsMake(12,16,12,16);
    button.configuration=configuration;
    button.titleLabel.numberOfLines=0;
    button.titleLabel.adjustsFontForContentSizeCategory=YES;
    button.accessibilityLabel=action.title;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:46].active=YES;
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *event) {
        (void)event;[weak chooseAction:action];
    }] forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static UIStackView *QHCenteredCard(void) {
    UIStackView *card=QHVCard();
    card.translatesAutoresizingMaskIntoConstraints=NO;
    return card;
}

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
- (BOOL)usesCenteredConfirmation {
    if (self.contentBuilt) return self.resolvedCentered;
    return QHCenteredConfirmationFor(self.dialogStyle, self.mutableFields.count,
                                     self.mutableActions.count, self.detail);
}
- (UIModalPresentationStyle)modalPresentationStyle {
    return self.usesCenteredConfirmation ? UIModalPresentationOverFullScreen
                                          : UIModalPresentationFormSheet;
}
- (UIModalTransitionStyle)modalTransitionStyle {
    if (self.usesCenteredConfirmation) return UIModalTransitionStyleCrossDissolve;
    return [super modalTransitionStyle];
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
- (void)buildCenteredConfirmation {
    [self setNavigationBarHidden:YES animated:NO];
    UIView *root=self.view;
    root.backgroundColor=[UIColor colorWithWhite:0 alpha:0.45];
    UIScrollView *scroll=[UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.alwaysBounceVertical=NO;
    scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    [root addSubview:scroll];
    UIView *canvas=[UIView new];
    canvas.translatesAutoresizingMaskIntoConstraints=NO;
    [scroll addSubview:canvas];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [canvas.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [canvas.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [canvas.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [canvas.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [canvas.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [canvas.heightAnchor constraintGreaterThanOrEqualToAnchor:scroll.frameLayoutGuide.heightAnchor]
    ]];
    BOOL danger=NO;
    for (QHDialogAction *action in self.mutableActions) if (action.style==UIAlertActionStyleDestructive) danger=YES;
    UIStackView *card=QHCenteredCard();
    [card addArrangedSubview:QHVInfo(self.content.title,self.detail,danger ? @"exclamationmark.shield" : @"doc.text",nil)];
    QHDialogAction *cancel=nil,*primary=nil;
    for (QHDialogAction *action in self.mutableActions) {
        if (action.style==UIAlertActionStyleCancel && !cancel) { cancel=action; continue; }
        if (!primary) primary=action;
    }
    if (self.mutableActions.count==1) {
        [card addArrangedSubview:QHCenteredActionButton(self.mutableActions.firstObject, YES, self)];
    } else if (cancel && primary) {
        UIStackView *row=[UIStackView new];
        row.axis=UILayoutConstraintAxisHorizontal;
        row.spacing=10;
        row.distribution=UIStackViewDistributionFillEqually;
        [row addArrangedSubview:QHCenteredActionButton(cancel, NO, self)];
        [row addArrangedSubview:QHCenteredActionButton(primary, YES, self)];
        [card addArrangedSubview:row];
    } else {
        for (QHDialogAction *action in self.mutableActions) [card addArrangedSubview:QHCenteredActionButton(action, YES, self)];
    }
    CGFloat width=MIN(320.0, CGRectGetWidth(UIScreen.mainScreen.bounds)-64.0);
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:canvas.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:canvas.centerYAnchor],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:canvas.topAnchor constant:20],
        [card.bottomAnchor constraintLessThanOrEqualToAnchor:canvas.bottomAnchor constant:-20],
        [card.widthAnchor constraintEqualToConstant:width]
    ]];
    self.centeredCard=card;
    if (self.entranceAnimated && !UIAccessibilityIsReduceMotionEnabled()) {
        card.transform=CGAffineTransformMakeScale(1.08,1.08);
    }
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    UIStackView *card=self.centeredCard;
    if (!card) return;
    if (self.entranceAnimated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.24 delay:0 usingSpringWithDamping:0.92 initialSpringVelocity:0.5
                            options:UIViewAnimationOptionAllowUserInteraction animations:^{
            card.transform=CGAffineTransformIdentity;
        } completion:nil];
    } else {
        card.transform=CGAffineTransformIdentity;
    }
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
    self.entranceAnimated=animated;
    if (self.contentBuilt) return;
    NSAssert(self.content && self.mutableActions && self.mutableFields,@"Dialog factory must configure content before first presentation");
    // Freeze the centered decision before the presentation style is read, so
    // a later nil-out of actions cannot flip the presentation mid-dismissal.
    self.resolvedCentered=QHCenteredConfirmationFor(self.dialogStyle, self.mutableFields.count,
                                                    self.mutableActions.count, self.detail);
    self.contentBuilt=YES;
    self.content.navigationItem.title=@""; // The card owns the single visible heading.
    QHConfigureModal(self);
    if (self.usesCenteredConfirmation) {
        [self buildCenteredConfirmation];
        return;
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
            // Rounded input container: the system rounded-rect border radius is
            // too small next to the 22pt cards. The field itself stays
            // transparent so the holder owns the corner and color.
            UIView *holder=[UIView new];
            holder.translatesAutoresizingMaskIntoConstraints=NO;
            holder.backgroundColor=field.backgroundColor;
            holder.layer.cornerRadius=12;
            holder.layer.masksToBounds=YES;
            field.borderStyle=UITextBorderStyleNone;
            field.backgroundColor=UIColor.clearColor;
            [holder addSubview:field];
            [NSLayoutConstraint activateConstraints:@[
                [field.topAnchor constraintEqualToAnchor:holder.topAnchor],
                [field.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
                [field.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:12],
                [field.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:-12],
                [holder.heightAnchor constraintGreaterThanOrEqualToConstant:44]
            ]];
            [inputs addArrangedSubview:label];[inputs addArrangedSubview:holder];
        }
        [stack addArrangedSubview:inputs];
    }
    __weak typeof(self) weak=self;
    for (QHDialogAction *action in self.mutableActions) {
        if (action.style==UIAlertActionStyleCancel && self.mutableActions.count>1) {
            // Same plain spec as the app-wide secondary Button: accent text,
            // body type, 8/12 insets. Only the height stays at 44 because this
            // one lives inside the navigation bar.
            UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];
            UIButtonConfiguration *configuration=UIButtonConfiguration.plainButtonConfiguration;
            configuration.title=action.title;
            configuration.cornerStyle=UIButtonConfigurationCornerStyleLarge;
            configuration.baseForegroundColor=DColor(0x5b54e8,0x9b95ff);
            configuration.contentInsets=NSDirectionalEdgeInsetsMake(8,12,8,12);
            configuration.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *input){
                NSMutableDictionary *attributes=[input mutableCopy];
                attributes[NSFontAttributeName]=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
                return attributes;
            };
            close.configuration=configuration;
            close.titleLabel.numberOfLines=0;
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
            configuration.contentInsets=NSDirectionalEdgeInsetsMake(12,16,12,16);
            button.configuration=configuration;
            button.titleLabel.numberOfLines=0;button.titleLabel.adjustsFontForContentSizeCategory=YES;
            button.accessibilityLabel=action.title;
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:46].active=YES;
            [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *event) {
                (void)event;[weak chooseAction:action];
            }] forControlEvents:UIControlEventTouchUpInside];
            [stack addArrangedSubview:button];
        }
    }
}
@end
