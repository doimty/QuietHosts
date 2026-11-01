#import "QHDialogController.h"
#import "QHVisualComponents.h"

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
@end

void QHConfigureModal(UIViewController *controller) {
    // Commit the actual UIKit properties while callers are still configuring
    // actions/fields, before presentViewController starts its transition.
    BOOL centered=[controller isKindOfClass:QHDialogController.class] &&
                  [(QHDialogController *)controller usesCenteredConfirmation];
    controller.modalPresentationStyle=centered ? UIModalPresentationOverFullScreen
                                               : UIModalPresentationFormSheet;
    controller.modalTransitionStyle=centered ? UIModalTransitionStyleCrossDissolve
                                             : UIModalTransitionStyleCoverVertical;
    // Swipe cancellation must not skip a caller's finishBusy/consent logic.
    controller.modalInPresentation=YES;
    if (!centered) {
        UISheetPresentationController *sheet=controller.sheetPresentationController;
        BOOL menu=[controller isKindOfClass:QHDialogController.class] &&
                  [(QHDialogController *)controller dialogStyle]==UIAlertControllerStyleActionSheet;
        if (menu) {
            // P2 menu: open at content height, not a full sheet. The 480pt cap
            // covers a short intro plus up to six 52pt rows and the cancel
            // group; longer content scrolls and the sheet can expand to large.
            if (@available(iOS 16.0, *)) {
                UISheetPresentationControllerDetent *contentDetent=
                    [UISheetPresentationControllerDetent customDetentWithIdentifier:@"qh.menu"
                        resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                            return MIN(context.maximumDetentValue, 480);
                        }];
                sheet.detents=@[contentDetent, UISheetPresentationControllerDetent.mediumDetent,
                                UISheetPresentationControllerDetent.largeDetent];
                sheet.selectedDetentIdentifier=@"qh.menu";
            } else {
                sheet.detents=@[UISheetPresentationControllerDetent.mediumDetent,
                                UISheetPresentationControllerDetent.largeDetent];
                sheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierMedium;
            }
        } else {
            sheet.detents=@[UISheetPresentationControllerDetent.largeDetent];
            sheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierLarge;
        }
        sheet.prefersGrabberVisible=YES;
        sheet.preferredCornerRadius=28;
        sheet.prefersScrollingExpandsWhenScrolledToEdge=YES;
    }
    controller.view.tintColor=QHVAccentColor();
    if ([controller isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav=(UINavigationController *)controller;
        nav.navigationBar.prefersLargeTitles=NO;
        UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor=QHVBackgroundColor();
        appearance.shadowColor=UIColor.clearColor;
        appearance.titleTextAttributes=@{NSForegroundColorAttributeName:QHVPrimaryTextColor()};
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

// Compact confirmation copy: heading plus optional explanation, no icon tile.
// The whole block is one VoiceOver element so the title and body are not read
// as two unrelated stops above the decision.
static UIView *QHConfirmTextBlock(NSString *title, NSString *detail) {
    UIStackView *text=[UIStackView new];
    text.axis=UILayoutConstraintAxisVertical;
    text.spacing=6;
    UILabel *heading=[UILabel new];
    heading.text=title;
    heading.numberOfLines=0;
    heading.adjustsFontForContentSizeCategory=YES;
    heading.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
        scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
    heading.textColor=QHVPrimaryTextColor();
    [text addArrangedSubview:heading];
    if (detail.length) {
        UILabel *body=[UILabel new];
        body.text=detail;
        body.numberOfLines=0;
        body.adjustsFontForContentSizeCategory=YES;
        body.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]
            scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightRegular]];
        body.textColor=QHVSecondaryTextColor();
        [text addArrangedSubview:body];
    }
    text.isAccessibilityElement=YES;
    text.accessibilityLabel=detail.length ? [NSString stringWithFormat:@"%@. %@",title,detail] : title;
    return text;
}

// Stacked actions: the committing choice is filled, the escape is plain text.
// Both keep the card width so long localized labels wrap instead of squeezing.
static UIButton *QHConfirmButton(QHDialogAction *action, BOOL primary, QHDialogController *owner) {
    __weak typeof(owner) weak=owner;
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration=primary ? UIButtonConfiguration.filledButtonConfiguration
                                                : UIButtonConfiguration.plainButtonConfiguration;
    configuration.title=action.title;
    if (primary) {
        configuration.baseBackgroundColor=action.style==UIAlertActionStyleDestructive ? QHVDestructiveColor() : QHVAccentColor();
        configuration.baseForegroundColor=QHVPrimaryForegroundColor();
    } else {
        configuration.baseBackgroundColor=UIColor.clearColor;
        configuration.baseForegroundColor=QHVSecondaryTextColor();
    }
    configuration.cornerStyle=UIButtonConfigurationCornerStyleLarge;
    configuration.contentInsets=NSDirectionalEdgeInsetsMake(12,16,12,16);
    configuration.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *input) {
        NSMutableDictionary *attributes=[input mutableCopy];
        attributes[NSFontAttributeName]=primary
            ? [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
                scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]]
            : [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
                scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightRegular]];
        return attributes;
    };
    button.configuration=configuration;
    button.titleLabel.numberOfLines=0;
    button.titleLabel.adjustsFontForContentSizeCategory=YES;
    button.accessibilityLabel=action.title;
    button.accessibilityIdentifier=primary ? @"qh.dialog.confirm.primary" : @"qh.dialog.confirm.cancel";
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:primary ? 46 : 44].active=YES;
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *event) {
        (void)event;[weak chooseAction:action];
    }] forControlEvents:UIControlEventTouchUpInside];
    return button;
}

// P3 form body: no title card. The navigation bar owns the title; the page
// body is split by blank lines into paragraphs with 12pt between them.
static UIStackView *QHFormBodyBlock(NSString *detail) {
    UIStackView *body=[UIStackView new];
    body.axis=UILayoutConstraintAxisVertical;
    body.spacing=12;
    body.accessibilityIdentifier=@"qh.dialog.body";
    for (NSString *paragraph in [detail componentsSeparatedByString:@"\n\n"]) {
        if (!paragraph.length) continue;
        UILabel *label=[UILabel new];
        label.text=paragraph;
        label.numberOfLines=0;
        label.adjustsFontForContentSizeCategory=YES;
        label.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]
            scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightRegular]];
        label.textColor=QHVSecondaryTextColor();
        [body addArrangedSubview:label];
    }
    body.isAccessibilityElement=YES;
    body.accessibilityLabel=detail;
    return body;
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
- (NSArray<UITextField *> *)textFields { return [self.mutableFields copy]; }
- (NSArray<QHDialogAction *> *)actions { return [self.mutableActions copy]; }
- (void)addAction:(QHDialogAction *)action {
    NSAssert(!self.contentBuilt,@"Configure dialog actions before presentation");
    [self.mutableActions addObject:action];
    QHConfigureModal(self);
}
- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *))configuration {
    NSAssert(!self.contentBuilt,@"Configure dialog fields before presentation");
    UITextField *field=[UITextField new];
    field.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.adjustsFontForContentSizeCategory=YES;
    field.borderStyle=UITextBorderStyleRoundedRect;
    field.textColor=QHVPrimaryTextColor();
    field.backgroundColor=QHVInnerColor();
    field.clearButtonMode=UITextFieldViewModeWhileEditing;
    if (configuration) configuration(field);
    [self.mutableFields addObject:field];
    QHConfigureModal(self);
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
    UIStackView *card=QHCenteredCard();
    card.layoutMargins=UIEdgeInsetsMake(20,20,20,20);
    card.accessibilityIdentifier=@"qh.dialog.confirm";
    [canvas addSubview:card];
    UIView *textBlock=QHConfirmTextBlock(self.content.title,self.detail);
    [card addArrangedSubview:textBlock];
    QHDialogAction *cancel=nil,*primary=nil;
    for (QHDialogAction *action in self.mutableActions) {
        if (action.style==UIAlertActionStyleCancel && !cancel) { cancel=action; continue; }
        if (!primary) primary=action;
    }
    // Primary first, then any further defaults, then the escape as plain text:
    // consent never competes visually with cancelling.
    if (primary) [card addArrangedSubview:QHConfirmButton(primary,YES,self)];
    for (QHDialogAction *action in self.mutableActions) {
        if (action==primary || action==cancel) continue;
        [card addArrangedSubview:QHConfirmButton(action,YES,self)];
    }
    // A lone acknowledgement is the decision itself, so it stays filled; only a
    // paired escape is demoted to text.
    if (cancel) [card addArrangedSubview:QHConfirmButton(cancel,!primary,self)];
    [card setCustomSpacing:20 afterView:textBlock];
    CGFloat width=MIN(320.0, CGRectGetWidth(UIScreen.mainScreen.bounds)-64.0);
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:canvas.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:canvas.centerYAnchor],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:canvas.topAnchor constant:20],
        [card.bottomAnchor constraintLessThanOrEqualToAnchor:canvas.bottomAnchor constant:-20],
        [card.widthAnchor constraintEqualToConstant:width]
    ]];
    self.centeredCard=card;
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
    // Freeze the configured shape for the layout and dismissal; presentation
    // properties were already committed by addAction/addTextField.
    self.resolvedCentered=QHCenteredConfirmationFor(self.dialogStyle, self.mutableFields.count,
                                                    self.mutableActions.count, self.detail);
    self.contentBuilt=YES;
    self.content.navigationItem.title=@""; // The card owns the single visible heading.
    if (self.dialogStyle==UIAlertControllerStyleActionSheet) [self setNavigationBarHidden:YES animated:NO];
    if (self.dialogStyle!=UIAlertControllerStyleActionSheet) self.content.navigationItem.title=self.content.title;
    if (self.usesCenteredConfirmation) {
        [self buildCenteredConfirmation];
        return;
    }
    UIView *view=self.content.view;
    view.backgroundColor=QHVBackgroundColor();
    UIScrollView *scroll=[UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;
    [view addSubview:scroll];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=16;
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
    // Every dialog is text-first. Menus keep the title card; form and long
    // content dialogs put the title in the navigation bar and the body
    // directly on the sheet, so there is no title card plus input card.
    if (self.dialogStyle==UIAlertControllerStyleActionSheet) {
        UIStackView *intro=QHVCard();
        intro.layer.cornerRadius=18;
        intro.layoutMargins=UIEdgeInsetsMake(18,18,18,18);
        [intro addArrangedSubview:QHConfirmTextBlock(self.content.title,self.detail)];
        [stack addArrangedSubview:intro];
    } else {
        [stack addArrangedSubview:QHFormBodyBlock(self.detail)];
    }
    if (self.mutableFields.count) {
        UIStackView *inputs=[UIStackView new];
        inputs.axis=UILayoutConstraintAxisVertical;
        inputs.spacing=16;
        for (UITextField *field in self.mutableFields) {
            UILabel *label=[UILabel new];label.text=field.accessibilityLabel ?: field.placeholder;
            label.numberOfLines=0;label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
            label.adjustsFontForContentSizeCategory=YES;label.textColor=QHVSecondaryTextColor();
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
            // The holder is only chrome; the field must own the entire hit
            // area through these anchors, not its initial zero-sized frame.
            field.translatesAutoresizingMaskIntoConstraints=NO;
            [holder addSubview:field];
            [NSLayoutConstraint activateConstraints:@[
                [field.topAnchor constraintEqualToAnchor:holder.topAnchor],
                [field.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
                [field.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:12],
                [field.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:-12],
                [holder.heightAnchor constraintGreaterThanOrEqualToConstant:44]
            ]];
            [inputs addArrangedSubview:label];[inputs addArrangedSubview:holder];
            [inputs setCustomSpacing:8 afterView:label];
        }
        [stack addArrangedSubview:inputs];
    }
    __weak typeof(self) weak=self;
    UIStackView *choices=nil;
    QHDialogAction *menuCancel=nil;
    for (QHDialogAction *action in self.mutableActions) {
        if (action.style==UIAlertActionStyleCancel && self.dialogStyle!=UIAlertControllerStyleActionSheet && self.mutableActions.count>1) {
            // Same plain spec as the app-wide secondary Button: accent text,
            // body type, 8/12 insets. Only the height stays at 44 because this
            // one lives inside the navigation bar.
            UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];
            UIButtonConfiguration *configuration=UIButtonConfiguration.plainButtonConfiguration;
            configuration.title=action.title;
            configuration.cornerStyle=UIButtonConfigurationCornerStyleLarge;
            configuration.baseForegroundColor=QHVAccentColor();
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
            if (action.style==UIAlertActionStyleCancel) { menuCancel=action; continue; }
            if (!choices) {
                // P2 menu: rows sit directly on the sheet background, not in
                // another white card. Separators only between rows.
                choices=[UIStackView new];
                choices.axis=UILayoutConstraintAxisVertical;
                choices.spacing=0;
                choices.accessibilityIdentifier=@"qh.dialog.choices";
                [stack addArrangedSubview:choices];
            }
            if (choices.arrangedSubviews.count) [choices addArrangedSubview:QHVSeparator()];
            UIControl *menuRow=QHVRow(action.title,nil,action.style==UIAlertActionStyleDestructive ? @"trash" : @"circle",nil,
                action.style==UIAlertActionStyleDestructive,YES,^{ [weak chooseAction:action]; });
            [menuRow.heightAnchor constraintGreaterThanOrEqualToConstant:52].active=YES;
            [choices addArrangedSubview:menuRow];
        } else {
            // Same filled spec, insets and height as the compact confirmation's
            // primary action: one button language across every dialog.
            [stack addArrangedSubview:QHConfirmButton(action,YES,self)];
        }
    }
    if (menuCancel) {
        // P2 menu: cancel is its own group below the list, a text button,
        // not a navigation-bar close and not another filled action.
        UIStackView *cancelGroup=[UIStackView new];
        cancelGroup.axis=UILayoutConstraintAxisVertical;
        cancelGroup.accessibilityIdentifier=@"qh.dialog.cancel";
        [cancelGroup addArrangedSubview:QHConfirmButton(menuCancel,NO,self)];
        [stack addArrangedSubview:cancelGroup];
    }
}
@end
