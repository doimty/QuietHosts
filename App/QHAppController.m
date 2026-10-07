#import "QHAppController.h"
#import "QHStore.h"
#import "QHDownload.h"
#import "../Shared/QHBridge.h"
#import "../Shared/QHLocalization.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <notify.h>

static UIColor *Color(unsigned light, unsigned dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        unsigned rgb = traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
        return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                               green:((rgb >> 8) & 255) / 255.0
                                blue:(rgb & 255) / 255.0
                               alpha:1];
    }];
}
static UIColor *Background(void) {
    return Color(0xf5f6f4, 0x121918);
}
static UIColor *Accent(void) {
    return Color(0x277669, 0x8fc3ad);
}
static UILabel *Label(NSString *text, UIFontTextStyle style, BOOL secondary) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = secondary ? UIColor.secondaryLabelColor : Color(0x202b29, 0xe6ece8);
    return label;
}
static UIStackView *Stack(void) {
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    return stack;
}
static UIStackView *Card(void) {
    UIStackView *card = Stack();
    card.backgroundColor = Color(0xffffff, 0x1b2321);
    card.layer.cornerRadius = 22;
    card.layoutMargins = UIEdgeInsetsMake(22, 20, 22, 20);
    card.layoutMarginsRelativeArrangement = YES;
    return card;
}
static UIButton *Button(NSString *text, BOOL primary, BOOL enabled, void (^action)(void)) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = primary ? UIButtonConfiguration.filledButtonConfiguration
                                            : UIButtonConfiguration.plainButtonConfiguration;
    config.title = text;
    config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    config.baseBackgroundColor = Accent();
    config.baseForegroundColor = primary ? Background() : Accent();
    config.contentInsets = NSDirectionalEdgeInsetsMake(14, 16, 14, 16);
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *input) {
        NSMutableDictionary *attributes = [input mutableCopy];
        attributes[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        return attributes;
    };
    button.configuration = config;
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.enabled = enabled;
    button.accessibilityLabel = text;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
                (void)a;
                if (action) {
                    action();
                }
            }]
        forControlEvents:UIControlEventTouchUpInside];
    return button;
}
static NSString *Number(NSUInteger value) {
    return [NSNumberFormatter localizedStringFromNumber:@(value) numberStyle:NSNumberFormatterDecimalStyle];
}
static BOOL Animate(void) {
    return !UIAccessibilityIsReduceMotionEnabled();
}

@interface QHPage : UIViewController
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, copy) void (^appeared)(void);
- (void)clear;
@end
@implementation QHPage
- (void)loadView {
    self.view = [UIView new];
    self.view.backgroundColor = Background();
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];
    self.stack = Stack();
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.spacing = 18;
    [scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor
                                                 constant:22],
        [self.stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor
                                                  constant:-22],
        [self.stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [self.stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-30],
        [self.stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-44]
    ]];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.appeared) {
        self.appeared();
    }
}
- (void)clear {
    [self loadViewIfNeeded];
    for (UIView *view in self.stack.arrangedSubviews) {
        [view removeFromSuperview];
    }
}
@end

@interface QHEditor : UIViewController <UITextViewDelegate>
@property(nonatomic, copy) NSString *initial;
@property(nonatomic, copy) NSString *explanation;
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, copy) void (^submit)(NSString *);
@property(nonatomic, copy) void (^cancel)(void);
@end
@implementation QHEditor
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = Background();
    UIStackView *stack = Stack();
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [stack addArrangedSubview:Label(self.explanation, UIFontTextStyleFootnote, YES)];
    self.textView = [UITextView new];
    self.textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.textView.adjustsFontForContentSizeCategory = YES;
    self.textView.backgroundColor = Color(0xffffff, 0x1b2321);
    self.textView.layer.cornerRadius = 16;
    self.textView.textContainerInset = UIEdgeInsetsMake(16, 12, 16, 12);
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.smartQuotesType = UITextSmartQuotesTypeNo;
    self.textView.smartDashesType = UITextSmartDashesTypeNo;
    self.textView.text = self.initial ?: @"";
    self.textView.accessibilityLabel = self.title;
    self.textView.delegate = self;
    [stack addArrangedSubview:self.textView];
    __weak typeof(self) weak = self;
    [stack addArrangedSubview:Button(QHL(@"Preview"), YES, YES, ^{
               if (weak.submit) {
                   weak.submit(weak.textView.text);
               }
           })];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:QHL(@"Cancel")
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(cancelTapped)];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-14],
        [self.textView.heightAnchor constraintGreaterThanOrEqualToConstant:100]
    ]];
}
- (void)cancelTapped {
    if (self.cancel) {
        self.cancel();
    }
}
- (BOOL)textView:(UITextView *)textView
    shouldChangeTextInRange:(NSRange)range
            replacementText:(NSString *)text {
    if (textView.text.length - range.length + text.length <= 65536) {
        return YES;
    }
    UIAccessibilityPostNotification(
        UIAccessibilityAnnouncementNotification,
        QHL(@"For large lists, import a file instead. The editor is limited to 64 K characters."));
    return NO;
}
@end

@interface QHAppController () <UIDocumentPickerDelegate>
@property(nonatomic, readwrite, strong) UITabBarController *rootController;
@property(nonatomic, strong) NSArray<QHPage *> *pages;
@property(nonatomic, strong) QHStore *store;
@property(nonatomic, strong) QHStorePreview *draft;
@property(nonatomic, strong) NSError *storeError;
@property(nonatomic, copy) NSDictionary *status;
@property(nonatomic, copy) NSString *appliedLocalRevision;
@property(nonatomic, copy) NSString *appliedHelperRevision;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL pendingStatus;
@property(nonatomic) BOOL pickingAllowlist;
@property(nonatomic, strong) QHDownload *download;
@property(nonatomic) int notificationToken;
@property(nonatomic) BOOL observing;
@end

@implementation QHAppController
- (instancetype)init {
    if ((self = [super init])) {
        _store = [QHStore new];
        _rootController = [UITabBarController new];
        _rootController.view.tintColor = Accent();
        NSArray *titles = @[ QHL(@"QuietHosts"), QHL(@"Rules"), QHL(@"Settings") ];
        NSArray *tabs = @[ QHL(@"Home"), QHL(@"Rules"), QHL(@"Settings") ];
        NSArray *symbols = @[ @"house", @"line.3.horizontal.decrease.circle", @"slider.horizontal.3" ];
        NSMutableArray *pages = [NSMutableArray array], *controllers = [NSMutableArray array];
        __weak typeof(self) weak = self;
        for (NSUInteger i = 0; i < 3; i++) {
            QHPage *page = [QHPage new];
            page.title = titles[i];
            page.appeared = ^{
                [weak refreshStatus];
            };
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
            nav.navigationBar.prefersLargeTitles = YES;
            nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:tabs[i]
                                                           image:[UIImage systemImageNamed:symbols[i]]
                                                             tag:(NSInteger)i];
            [pages addObject:page];
            [controllers addObject:nav];
        }
        _pages = pages;
        _rootController.viewControllers = controllers;
        _notificationToken = 0;
        int token = 0;
        if (notify_register_dispatch("com.doimty.quiethosts.changed", &token, dispatch_get_main_queue(),
                                     ^(int t) {
                                         (void)t;
                                         [weak refreshStatus];
                                     }) == NOTIFY_STATUS_OK) {
            _notificationToken = token;
            _observing = YES;
        }
    }
    return self;
}
- (void)dealloc {
    if (_observing) {
        notify_cancel(_notificationToken);
    }
}
- (void)applyThemeToWindow:(UIWindow *)window {
    NSString *theme = [NSUserDefaults.standardUserDefaults stringForKey:@"QHTheme"];
    window.overrideUserInterfaceStyle = [theme isEqual:@"light"]  ? UIUserInterfaceStyleLight
                                        : [theme isEqual:@"dark"] ? UIUserInterfaceStyleDark
                                                                  : UIUserInterfaceStyleUnspecified;
}
- (UIViewController *)presenter {
    return self.rootController.presentedViewController ?: self.rootController;
}
- (void)message:(NSString *)title detail:(NSString *)detail {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:detail
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:QHL(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self.presenter presentViewController:alert animated:Animate() completion:nil];
}
- (void)finishBusy {
    self.busy = NO;
    self.download = nil;
    [self render];
    if (self.pendingStatus) {
        self.pendingStatus = NO;
        [self refreshStatus];
    }
}
- (void)start {
    if (self.busy) {
        return;
    }
    self.busy = YES;
    [self render];
    __weak typeof(self) weak = self;
    QHStore *store = self.store;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        QHStorePreview *draft = [store load:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            weak.draft = draft;
            weak.storeError = error;
            weak.pendingStatus = YES;
            [weak finishBusy];
        });
    });
}
- (void)refreshStatus {
    if (self.busy) {
        self.pendingStatus = YES;
        return;
    }
    self.busy = YES;
    [self render];
    __weak typeof(self) weak = self;
    [QHBridge request:@"status"
              payload:@{}
           completion:^(NSDictionary *result) {
               weak.status = result;
               // A status query never implies that the local draft matches helper content.
               if (![weak.appliedHelperRevision isEqual:result[@"revision"]] ||
                   ![result[@"state"] isEqual:@"active"]) {
                   weak.appliedHelperRevision = nil;
                   weak.appliedLocalRevision = nil;
               }
               [weak finishBusy];
           }];
}
- (BOOL)statusWritable:(NSDictionary *)status {
    return [status[@"ok"] boolValue] && [status[@"revision"] isKindOfClass:NSString.class] &&
           [status[@"revision"] length] &&
           [@[ @"unmanaged", @"inactive", @"active" ] containsObject:status[@"state"]];
}
- (NSString *)stateTitle {
    NSString *state = self.status[@"state"];
    if (!self.status) {
        return QHL(@"Checking file state");
    }
    if ([state isEqual:@"conflict"]) {
        return QHL(@"File conflict");
    }
    if (![self.status[@"ok"] boolValue]) {
        return QHL(@"Helper unavailable");
    }
    if ([state isEqual:@"active"]) {
        return QHL(@"Files applied");
    }
    if ([state isEqual:@"inactive"]) {
        return QHL(@"Baseline restored");
    }
    if ([state isEqual:@"unmanaged"]) {
        return QHL(@"Not yet applied");
    }
    return QHL(@"State unavailable");
}
- (NSString *)statusExplanation:(NSDictionary *)status {
    if (!status) {
        return QHL(@"Checking file state");
    }
    if ([status[@"state"] isEqual:@"conflict"] || [status[@"errorCode"] isEqual:@"baseline-conflict"]) {
        return QHL(@"Existing Hosts or helper state conflicts with this request. Review Advanced information "
                   @"and resolve the external conflict; nothing will be deleted automatically.");
    }
    if (![status[@"ok"] boolValue]) {
        return QHL(
            @"The helper could not verify file state. Check the native RootHide package and dependencies, "
            @"then check again. Do not remove existing Hosts files to force activation.");
    }
    return QHL(@"This is verified file state, not a DNS or traffic protection test. Apps may retain cached "
               @"DNS results.");
}
- (void)addHeading:(NSString *)text to:(UIStackView *)stack {
    [stack addArrangedSubview:Label(text, UIFontTextStyleHeadline, NO)];
}
- (void)render {
    for (QHPage *page in self.pages) {
        [page clear];
    }
    __weak typeof(self) weak = self;
    UIStackView *home = self.pages[0].stack;
    [home addArrangedSubview:Label(QHL(@"Local rules. Clear control."), UIFontTextStyleSubheadline, YES)];
    UIStackView *hero = Card();
    UIImageView *symbol =
        [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shield.lefthalf.filled"]];
    symbol.tintColor = Accent();
    symbol.contentMode = UIViewContentModeScaleAspectFit;
    [symbol.heightAnchor constraintEqualToConstant:36].active = YES;
    symbol.isAccessibilityElement = NO;
    [hero addArrangedSubview:symbol];
    [hero addArrangedSubview:Label(self.stateTitle, UIFontTextStyleTitle1, NO)];
    [hero addArrangedSubview:Label([self statusExplanation:self.status], UIFontTextStyleFootnote, YES)];
    if ([self.status[@"ok"] boolValue] && [self.status[@"domainCount"] isKindOfClass:NSNumber.class]) {
        [hero addArrangedSubview:Label([NSString stringWithFormat:QHL(@"Managed snapshot: %@ domains"),
                                                                  Number([self.status[@"domainCount"]
                                                                      unsignedIntegerValue])],
                                       UIFontTextStyleSubheadline, NO)];
    }
    [home addArrangedSubview:hero];
    if (self.storeError) {
        UIStackView *failure = Card();
        [failure addArrangedSubview:Label(QHL(@"Local draft unavailable"), UIFontTextStyleHeadline, NO)];
        [failure
            addArrangedSubview:Label(self.storeError.localizedDescription, UIFontTextStyleFootnote, YES)];
        [failure addArrangedSubview:Button(QHL(@"Read local storage again"), NO, !self.busy, ^{
                     [weak start];
                 })];
        [home addArrangedSubview:failure];
    } else if (self.draft) {
        UIStackView *counts = Card();
        [counts addArrangedSubview:Label(Number(self.draft.compiled.domains.count), UIFontTextStyleLargeTitle,
                                         NO)];
        [counts
            addArrangedSubview:Label(QHL(@"Merged domains in local draft"), UIFontTextStyleSubheadline, YES)];
        [counts addArrangedSubview:Label([NSString
                                             stringWithFormat:QHL(@"%@ sources · %@ exact exceptions"),
                                                              Number([self.draft.document[@"sources"] count]),
                                                              Number(self.draft.allowlistCount)],
                                         UIFontTextStyleSubheadline, NO)];
        BOOL matched = [self.appliedLocalRevision isEqual:self.draft.document[@"revision"]] &&
                       [self.appliedHelperRevision isEqual:self.status[@"revision"]];
        [counts addArrangedSubview:Label(matched ? QHL(@"This draft was saved to the helper in this session.")
                                                 : QHL(@"Local draft · awaiting explicit Apply"),
                                         UIFontTextStyleFootnote, YES)];
        [home addArrangedSubview:counts];
    }
    [home addArrangedSubview:Button(QHL(@"Apply local draft"), YES, !self.busy && self.draft != nil, ^{
              [weak prepareApply];
          })];
    [home addArrangedSubview:Button(QHL(@"Update URL sources"), NO, !self.busy && self.draft != nil, ^{
              [weak refreshSources];
          })];
    if (self.download) {
        [home addArrangedSubview:Button(QHL(@"Cancel download"), NO, YES, ^{
                  [weak.download cancel];
              })];
    }
    if ([self statusWritable:self.status]) {
        if ([self.status[@"state"] isEqual:@"active"]) {
            [home addArrangedSubview:Button(QHL(@"Pause and restore baseline"), NO, !self.busy, ^{
                      [weak prepareHelperCommand:@"disable"];
                  })];
        } else if ([self.status[@"state"] isEqual:@"inactive"]) {
            [home addArrangedSubview:Button(QHL(@"Enable saved helper snapshot"), NO, !self.busy, ^{
                      [weak prepareHelperCommand:@"enable"];
                  })];
        }
    }
    [home addArrangedSubview:Button(QHL(@"Check file state"), NO, !self.busy, ^{
              [weak refreshStatus];
          })];
    [home addArrangedSubview:
              Label(self.busy ? QHL(@"Working…")
                              : QHL(@"Manual updates only. No background polling or per-domain DNS queries."),
                    UIFontTextStyleFootnote, YES)];
    [self renderRules];
    [self renderSettings];
}
- (void)renderRules {
    UIStackView *rules = self.pages[1].stack;
    __weak typeof(self) weak = self;
    [rules
        addArrangedSubview:Label(QHL(@"Know where every rule comes from."), UIFontTextStyleSubheadline, YES)];
    if (!self.draft) {
        [rules
            addArrangedSubview:Label(
                                   QHL(@"Local storage must load successfully before you can change rules."),
                                   UIFontTextStyleBody, YES)];
        return;
    }
    NSArray *sources = self.draft.document[@"sources"];
    if (!sources.count) {
        UIStackView *empty = Card();
        [empty addArrangedSubview:Label(QHL(@"Start with a source you trust"), UIFontTextStyleTitle2, NO)];
        [empty addArrangedSubview:Label(QHL(@"No bundled lists. Import a URL, file, or pasted text, review "
                                            @"the merged preview, then save locally."),
                                        UIFontTextStyleBody, YES)];
        [rules addArrangedSubview:empty];
    }
    for (NSDictionary *source in sources) {
        UIStackView *card = Card();
        UIStackView *row = [UIStackView new];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 12;
        row.alignment = UIStackViewAlignmentCenter;
        UILabel *name = Label(source[@"name"], UIFontTextStyleHeadline, NO);
        [row addArrangedSubview:name];
        UISwitch *toggle = [UISwitch new];
        toggle.onTintColor = Accent();
        toggle.on = [source[@"enabled"] boolValue];
        toggle.enabled = !self.busy;
        toggle.accessibilityLabel = [NSString stringWithFormat:QHL(@"Include source: %@"), source[@"name"]];
        toggle.accessibilityHint = QHL(@"Changes only the local draft. Apply separately.");
        NSString *identifier = source[@"id"];
        [toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
                    UISwitch *sender = (UISwitch *)action.sender;
                    BOOL enabled = sender.on;
                    [sender setOn:!enabled animated:NO];
                    [weak toggleSource:identifier enabled:enabled];
                }]
            forControlEvents:UIControlEventValueChanged];
        [row addArrangedSubview:toggle];
        [card addArrangedSubview:row];
        NSString *kind = [source[@"kind"] isEqual:@"url"]    ? QHL(@"HTTPS source · manual refresh")
                         : [source[@"kind"] isEqual:@"file"] ? QHL(@"Local file · reimport to update")
                                                             : QHL(@"Pasted text · reimport to update");
        [card addArrangedSubview:Label(kind, UIFontTextStyleFootnote, YES)];
        QHParseResult *result = self.draft.sourceResults[identifier];
        [card addArrangedSubview:Label([NSString stringWithFormat:QHL(@"%@ parsed domains · %@ bytes"),
                                                                  Number(result.domains.count),
                                                                  Number([source[@"data"] length])],
                                       UIFontTextStyleSubheadline, NO)];
        [card addArrangedSubview:Button(QHL(@"Remove from local draft"), NO, !self.busy, ^{
                  [weak removeSource:identifier];
              })];
        [rules addArrangedSubview:card];
    }
    [rules
        addArrangedSubview:Button(QHL(@"Add source"), YES, !self.busy && sources.count < QHMaximumSources, ^{
            [weak chooseImport:NO];
        })];
    UIStackView *allow = Card();
    [allow addArrangedSubview:Label(QHL(@"Exact allowlist"), UIFontTextStyleTitle2, NO)];
    [allow
        addArrangedSubview:
            Label([NSString stringWithFormat:QHL(@"%@ exceptions. Only exact domains are excluded from our "
                                                 @"generated blocklist; no wildcard, suffix, or URL rules."),
                                             Number(self.draft.allowlistCount)],
                  UIFontTextStyleFootnote, YES)];
    [allow addArrangedSubview:Button(QHL(@"Edit or replace allowlist"), NO, !self.busy, ^{
               [weak chooseImport:YES];
           })];
    [rules addArrangedSubview:allow];
    [rules addArrangedSubview:Label(QHL(@"Saving, toggling, or removing a source changes only the local "
                                        @"draft. Existing managed Hosts stay unchanged until Apply."),
                                    UIFontTextStyleFootnote, YES)];
}
- (void)renderSettings {
    UIStackView *settings = self.pages[2].stack;
    __weak typeof(self) weak = self;
    [settings addArrangedSubview:Label(QHL(@"Simple by default. Control when needed."),
                                       UIFontTextStyleSubheadline, YES)];
    UIStackView *appearance = Card();
    [self addHeading:QHL(@"Appearance") to:appearance];
    UISegmentedControl *theme =
        [[UISegmentedControl alloc] initWithItems:@[ QHL(@"System"), QHL(@"Light"), QHL(@"Dark") ]];
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"QHTheme"];
    theme.selectedSegmentIndex = [saved isEqual:@"light"] ? 1 : [saved isEqual:@"dark"] ? 2 : 0;
    theme.accessibilityLabel = QHL(@"Appearance");
    [theme setTitleTextAttributes:@{
        NSFontAttributeName : [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]
    }
                         forState:UIControlStateNormal];
    [theme.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [theme addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
               UISegmentedControl *control = (UISegmentedControl *)action.sender;
               [NSUserDefaults.standardUserDefaults
                   setObject:@[ @"system", @"light", @"dark" ][(NSUInteger)control.selectedSegmentIndex]
                      forKey:@"QHTheme"];
               [weak applyThemeToWindow:weak.rootController.view.window];
           }]
        forControlEvents:UIControlEventValueChanged];
    [appearance addArrangedSubview:theme];
    [settings addArrangedSubview:appearance];
    UIStackView *manual = Card();
    [self addHeading:QHL(@"Manual updates") to:manual];
    [manual addArrangedSubview:
                Label(QHL(@"URL refresh is explicit and sequential. If any source fails, every existing "
                          @"snapshot is kept. File and pasted sources are updated by reimporting."),
                      UIFontTextStyleBody, YES)];
    [manual addArrangedSubview:Label(QHL(@"Add QuietHosts to Control Center using CCSupport. The module "
                                         @"queries the same helper file state."),
                                     UIFontTextStyleFootnote, YES)];
    [settings addArrangedSubview:manual];
    UIStackView *data = Card();
    [self addHeading:QHL(@"Data and diagnostics") to:data];
    [data addArrangedSubview:Button(QHL(@"Backup and restore"), NO, !self.busy, ^{
              [weak showDiagnostics:NO];
          })];
    [data addArrangedSubview:Button(QHL(@"Retry DNS reload"), NO,
                                    !self.busy && [self statusWritable:self.status], ^{
                                        [weak retryReload];
                                    })];
    [data addArrangedSubview:Button(QHL(@"Advanced information"), NO, !self.busy, ^{
              [weak showDiagnostics:YES];
          })];
    [settings addArrangedSubview:data];
    [settings addArrangedSubview:Label(QHL(@"QuietHosts · native RootHide"), UIFontTextStyleFootnote, YES)];
}
- (void)retryReload {
    if (self.busy || ![self statusWritable:self.status]) {
        return;
    }
    NSString *revision = [self.status[@"revision"] copy];
    __weak typeof(self) weak = self;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:QHL(@"Retry DNS reload")
                         message:QHL(@"This requests a restart of the two DNS services. Connections may "
                                     @"briefly be interrupted; Hosts files are not changed.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:QHL(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:QHL(@"Confirm")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                                (void)a;
                                                weak.busy = YES;
                                                [weak render];
                                                [QHBridge request:@"reload"
                                                          payload:@{@"expectedRevision" : revision}
                                                       completion:^(NSDictionary *result) {
                                                           [weak operationCompleted:result applied:NO];
                                                       }];
                                            }]];
    [self.presenter presentViewController:alert animated:Animate() completion:nil];
}
- (void)showDiagnostics:(BOOL)advanced {
    NSString *baseline = QHL(@"Backup availability is not reported by the helper. No backup is assumed.");
    if ([self.status[@"hasBaseline"] isKindOfClass:NSNumber.class]) {
        baseline = [self.status[@"hasBaseline"] boolValue] ? QHL(@"Helper reports a retained baseline.")
                                                           : QHL(@"Helper reports no retained baseline.");
    }
    NSString *detail = [NSString
        stringWithFormat:QHL(@"%@\n\n%@\n\nThe local source document is not a system Hosts backup. Restore "
                             @"uses only the helper's verified baseline, never an app-selected path."),
                         self.stateTitle, baseline];
    if (advanced) {
        detail = [NSString
            stringWithFormat:
                QHL(@"%@\n\nRequired: native RootHide, LetMeBlock 1.3.0-1+native1, libSandy 1.1.6-4, "
                    @"CCSupport. Installed versions are not verified here.\n\nFixed managed entry: "
                    @"jbroot('/etc/hosts'). RootHide may mirror this as a symlink. Only the helper may "
                    @"replace the entry after validation; this app never writes system Hosts.\n\nLocal "
                    @"sources: this app's Application Support/QuietHosts. Source URLs are private local "
                    @"refresh metadata. No arbitrary path operations are available."),
                detail];
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:advanced ? QHL(@"Advanced information") : QHL(@"Backup and restore")
                         message:detail
                  preferredStyle:UIAlertControllerStyleAlert];
    if ([self statusWritable:self.status] && [self.status[@"state"] isEqual:@"active"]) {
        __weak typeof(self) weak = self;
        [alert addAction:[UIAlertAction actionWithTitle:QHL(@"Restore verified baseline")
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *a) {
                                                    (void)a;
                                                    [weak prepareHelperCommand:@"disable"];
                                                }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:QHL(@"Close")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self.presenter presentViewController:alert animated:Animate() completion:nil];
}
- (void)showPreview:(QHStorePreview *)preview
              title:(NSString *)title
             detail:(NSString *)detail
             button:(NSString *)button
            confirm:(void (^)(void))confirm {
    QHPage *page = [QHPage new];
    page.title = title;
    [page loadViewIfNeeded];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    nav.modalInPresentation = YES;
    __weak typeof(self) weak = self;
    __weak UINavigationController *weakNav = nav;
    __weak QHPage *weakPage = page;
    page.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithCustomView:Button(QHL(@"Cancel"), NO, YES, ^{
                                     [weakNav dismissViewControllerAnimated:Animate()
                                                                 completion:^{
                                                                     [weak finishBusy];
                                                                 }];
                                 })];
    [page.stack addArrangedSubview:Label(detail, UIFontTextStyleBody, YES)];
    UIStackView *counts = Card();
    NSDictionary *s = preview.compiled.statistics, *p = preview.parseStatistics;
    NSArray *lines = @[
        [NSString stringWithFormat:QHL(@"Merged unique domains: %@"), Number(preview.compiled.domains.count)],
        [NSString stringWithFormat:QHL(@"Duplicates removed during merge: %@"),
                                   Number([s[@"duplicates"] unsignedIntegerValue])],
        [NSString stringWithFormat:QHL(@"Excluded by exact allowlist: %@"),
                                   Number([s[@"excluded"] unsignedIntegerValue])],
        [NSString stringWithFormat:QHL(@"Generated bytes: %@"), Number(preview.compiled.hostsData.length)],
        QHL(@"All source inputs, including disabled sources:"),
        [NSString stringWithFormat:QHL(@"Accepted: %@ · duplicates: %@"),
                                   Number([p[@"accepted"] unsignedIntegerValue]),
                                   Number([p[@"duplicates"] unsignedIntegerValue])],
        [NSString stringWithFormat:QHL(@"Redirects: %@ · local metadata: %@"),
                                   Number([p[@"redirects"] unsignedIntegerValue]),
                                   Number([p[@"local"] unsignedIntegerValue])],
        [NSString stringWithFormat:QHL(@"Invalid: %@ · unsupported: %@"),
                                   Number([p[@"invalid"] unsignedIntegerValue]),
                                   Number([p[@"unsupported"] unsignedIntegerValue])]
    ];
    for (NSString *line in lines) {
        [counts addArrangedSubview:Label(line, UIFontTextStyleSubheadline, NO)];
    }
    [page.stack addArrangedSubview:counts];
    [page.stack addArrangedSubview:Button(button, YES, YES, ^{
                    weakPage.view.userInteractionEnabled = NO;
                    [weakNav dismissViewControllerAnimated:Animate() completion:confirm];
                })];
    [page.stack addArrangedSubview:Label(QHL(@"Sample · first 50 merged domains at most"),
                                         UIFontTextStyleHeadline, NO)];
    NSUInteger count = MIN((NSUInteger)50, preview.compiled.domains.count);
    NSString *sample = count ? [[preview.compiled.domains subarrayWithRange:NSMakeRange(0, count)]
                                   componentsJoinedByString:@"\n"]
                             : QHL(@"No generated domains");
    [page.stack addArrangedSubview:Label(sample, UIFontTextStyleFootnote, YES)];
    [self.rootController presentViewController:nav animated:Animate() completion:nil];
}
- (void)candidateSources:(NSArray *)sources allowlist:(NSData *)allowlist title:(NSString *)title {
    // Caller holds busy from the beginning of import/download/editor processing.
    NSString *revision = self.draft.document[@"revision"];
    QHStore *store = self.store;
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        QHStorePreview *preview = [store previewSources:sources
                                              allowlist:allowlist
                                       expectedRevision:revision
                                                  error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weak) {
                return;
            }
            if (!preview) {
                [weak finishBusy];
                [weak message:QHL(@"Nothing saved")
                       detail:error.localizedDescription
                                  ?: QHL(@"The preview failed. Existing snapshots were kept.")];
                return;
            }
            [weak showPreview:preview
                        title:title
                       detail:QHL(@"Review the whole prospective draft. Save commits all local changes "
                                  @"together; it does not apply system Hosts. Unsupported and invalid source "
                                  @"lines are skipped as counted below.")
                       button:QHL(@"Save local draft")
                      confirm:^{
                          [weak commitCandidate:preview];
                      }];
        });
    });
}
- (void)commitCandidate:(QHStorePreview *)preview {
    QHStore *store = self.store;
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL saved = [store commitPreview:preview error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (saved) {
                weak.draft = preview;
                weak.appliedLocalRevision = nil;
                weak.appliedHelperRevision = nil;
            }
            [weak finishBusy];
            [weak message:saved ? QHL(@"Saved locally · not applied") : QHL(@"Nothing saved")
                   detail:saved ? QHL(@"Your source snapshots are saved. Use Apply local draft on Home when "
                                      @"you are ready to update managed Hosts.")
                                : error.localizedDescription];
        });
    });
}
- (void)toggleSource:(NSString *)identifier enabled:(BOOL)enabled {
    if (self.busy || !self.draft) {
        return;
    }
    self.busy = YES;
    [self render];
    NSMutableArray *sources = [self.draft.document[@"sources"] mutableCopy];
    for (NSUInteger i = 0; i < sources.count; i++) {
        if ([sources[i][@"id"] isEqual:identifier]) {
            NSMutableDictionary *source = [sources[i] mutableCopy];
            source[@"enabled"] = @(enabled);
            sources[i] = source;
            break;
        }
    }
    [self candidateSources:sources
                 allowlist:self.draft.document[@"allowlist"]
                     title:QHL(@"Review source switch")];
}
- (void)removeSource:(NSString *)identifier {
    if (self.busy || !self.draft) {
        return;
    }
    self.busy = YES;
    [self render];
    NSMutableArray *sources = [NSMutableArray array];
    for (NSDictionary *source in self.draft.document[@"sources"]) {
        if (![source[@"id"] isEqual:identifier]) {
            [sources addObject:source];
        }
    }
    [self candidateSources:sources
                 allowlist:self.draft.document[@"allowlist"]
                     title:QHL(@"Confirm source removal")];
}
- (void)stageData:(NSData *)data
             kind:(NSString *)kind
             name:(NSString *)name
              URL:(NSString *)url
        allowlist:(BOOL)allowlist {
    if (![data isKindOfClass:NSData.class]) {
        [self finishBusy];
        [self message:QHL(@"Nothing saved") detail:QHL(@"The preview failed. Existing snapshots were kept.")];
        return;
    }
    if (allowlist) {
        [self candidateSources:self.draft.document[@"sources"]
                     allowlist:data
                         title:QHL(@"Review exact allowlist")];
        return;
    }
    NSMutableArray *sources = [self.draft.document[@"sources"] mutableCopy];
    NSMutableDictionary *source =
        [@{@"id" : NSUUID.UUID.UUIDString, @"name" : name, @"enabled" : @YES, @"kind" : kind, @"data" : data}
            mutableCopy];
    if (url) {
        source[@"url"] = url;
    }
    [sources addObject:source];
    [self candidateSources:sources
                 allowlist:self.draft.document[@"allowlist"]
                     title:QHL(@"Review new source")];
}
- (void)chooseImport:(BOOL)allowlist {
    if (self.busy || !self.draft) {
        return;
    }
    self.busy = YES;
    [self render];
    __weak typeof(self) weak = self;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:allowlist ? QHL(@"Exact allowlist") : QHL(@"Add source")
                         message:allowlist
                                     ? QHL(@"Replace the entire allowlist. Every nonempty line must be an "
                                           @"exact domain; any invalid entry rejects the whole change.")
                                     : QHL(@"Only Hosts blocking records and bare domains are supported. "
                                           @"Preview before saving. Large lists should be imported as files.")
                  preferredStyle:UIAlertControllerStyleActionSheet];
    if (!allowlist) {
        [alert addAction:[UIAlertAction actionWithTitle:QHL(@"HTTPS URL")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
                                                    (void)a;
                                                    [weak askURL];
                                                }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:QHL(@"Choose file")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                                (void)a;
                                                [weak chooseFile:allowlist];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:allowlist ? QHL(@"Edit text") : QHL(@"Paste text")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                                (void)a;
                                                [weak editText:allowlist];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:QHL(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *a) {
                                                (void)a;
                                                [weak finishBusy];
                                            }]];
    alert.popoverPresentationController.sourceView = self.rootController.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(
        CGRectGetMidX(self.rootController.view.bounds), CGRectGetMidY(self.rootController.view.bounds), 1, 1);
    [self.rootController presentViewController:alert animated:Animate() completion:nil];
}
- (void)askURL {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:QHL(@"HTTPS source")
                         message:
                             QHL(@"Use a direct raw file URL without credentials. The full URL, including "
                                 @"any query, is stored only in this app's private source document for "
                                 @"manual refresh. It is never shown in errors or sent to the helper.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = QHL(@"Source name (optional)");
        field.accessibilityLabel = QHL(@"Source name");
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = QHL(@"HTTPS raw file URL");
        field.accessibilityLabel = QHL(@"HTTPS raw file URL");
        field.keyboardType = UIKeyboardTypeURL;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.textContentType = @"";
    }];
    __weak typeof(self) weak = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:QHL(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *a) {
                                                (void)a;
                                                [weak finishBusy];
                                            }]];
    [alert addAction:[UIAlertAction
                         actionWithTitle:QHL(@"Download and preview")
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *a) {
                                     (void)a;
                                     NSString *name = weakAlert.textFields[0].text;
                                     NSString *text = weakAlert.textFields[1].text;
                                     NSError *error = nil;
                                     NSURL *url = text.length <= 4096
                                                      ? [QHDownload validatedURLFromString:text error:&error]
                                                      : nil;
                                     if (!url || name.length > 120 ||
                                         [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet]
                                                 .location != NSNotFound) {
                                         [weak finishBusy];
                                         [weak message:QHL(@"Cannot import")
                                                detail:QHL(@"Enter a valid HTTPS URL of at most 4096 "
                                                           @"characters and a source name of at most 120 "
                                                           @"characters without control characters.")];
                                         return;
                                     }
                                     [weak downloadURL:url.absoluteString
                                            completion:^(NSData *data, NSError *downloadError) {
                                                if (!data) {
                                                    [weak finishBusy];
                                                    [weak message:QHL(@"Nothing saved")
                                                           detail:downloadError.localizedDescription];
                                                    return;
                                                }
                                                [weak stageData:data
                                                           kind:@"url"
                                                           name:name.length ? name : QHL(@"HTTPS source")
                                                            URL:url.absoluteString
                                                      allowlist:NO];
                                            }];
                                 }]];
    [self.rootController presentViewController:alert animated:Animate() completion:nil];
}
- (void)downloadURL:(NSString *)url completion:(void (^)(NSData *, NSError *))completion {
    self.download = [QHDownload new];
    [self render];
    __weak typeof(self) weak = self;
    [self.download startURLString:url
                       completion:^(NSData *data, NSError *error) {
                           weak.download = nil;
                           [weak render];
                           if (weak && completion) {
                               completion(data, error);
                           }
                       }];
}
- (void)chooseFile:(BOOL)allowlist {
    self.pickingAllowlist = allowlist;
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeData ] asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self.rootController presentViewController:picker animated:Animate() completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    [self finishBusy];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    BOOL allowlist = self.pickingAllowlist;
    __weak typeof(self) weak = self;
    if (!url) {
        [self finishBusy];
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSData *data = [QHStore readImportURL:url error:&error];
        NSString *name = url.lastPathComponent;
        if (!name.length || name.length > 120 ||
            [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
            name = QHL(@"Local file");
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!data) {
                [weak finishBusy];
                [weak message:QHL(@"Nothing saved") detail:error.localizedDescription];
                return;
            }
            [weak stageData:data kind:@"file" name:name URL:nil allowlist:allowlist];
        });
    });
}
- (void)editText:(BOOL)allowlist {
    QHEditor *editor = [QHEditor new];
    editor.title = allowlist ? QHL(@"Exact allowlist") : QHL(@"Paste source");
    NSData *existing = self.draft.document[@"allowlist"];
    BOOL small = existing.length <= 65536;
    editor.initial =
        allowlist && small ? [[NSString alloc] initWithData:existing encoding:NSUTF8StringEncoding] : @"";
    editor.explanation =
        allowlist ? (small ? QHL(@"One exact domain per line. This replaces the whole allowlist; invalid "
                                 @"input rejects every change. Import files for large lists.")
                           : QHL(@"This allowlist is too large to edit inline. Paste a replacement or cancel "
                                 @"and import a file. Saving replaces the entire allowlist."))
                  : QHL(@"Paste Hosts blocking records or bare domains. The editor is limited to 64 K "
                        @"characters; import files up to 16 MiB for larger lists.");
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    nav.modalInPresentation = YES;
    __weak typeof(self) weak = self;
    __weak UINavigationController *weakNav = nav;
    __weak QHEditor *weakEditor = editor;
    editor.cancel = ^{
        [weakNav dismissViewControllerAnimated:Animate()
                                    completion:^{
                                        [weak finishBusy];
                                    }];
    };
    editor.submit = ^(NSString *text) {
        weakEditor.view.userInteractionEnabled = NO;
        [weakNav
            dismissViewControllerAnimated:Animate()
                               completion:^{
                                   dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                                       NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
                                       dispatch_async(dispatch_get_main_queue(), ^{
                                           [weak stageData:data
                                                      kind:@"paste"
                                                      name:QHL(@"Pasted source")
                                                       URL:nil
                                                 allowlist:allowlist];
                                       });
                                   });
                               }];
    };
    [self.rootController presentViewController:nav animated:Animate() completion:nil];
}
- (void)refreshSources {
    if (self.busy || !self.draft) {
        return;
    }
    BOOL any = NO;
    for (NSDictionary *source in self.draft.document[@"sources"]) {
        if ([source[@"kind"] isEqual:@"url"]) {
            any = YES;
        }
    }
    if (!any) {
        [self message:QHL(@"No URL sources")
               detail:QHL(@"File and pasted sources are offline snapshots. Add or reimport them manually.")];
        return;
    }
    self.busy = YES;
    [self render];
    NSMutableArray *candidate = [self.draft.document[@"sources"] mutableCopy];
    [self refreshBatch:candidate index:0];
}
- (void)refreshBatch:(NSMutableArray *)sources index:(NSUInteger)index {
    while (index < sources.count && ![sources[index][@"kind"] isEqual:@"url"]) {
        index++;
    }
    if (index == sources.count) {
        [self candidateSources:sources
                     allowlist:self.draft.document[@"allowlist"]
                         title:QHL(@"Review all updated sources")];
        return;
    }
    NSUInteger position = index;
    NSDictionary *old = sources[position];
    __weak typeof(self) weak = self;
    [self downloadURL:old[@"url"]
           completion:^(NSData *data, NSError *error) {
               if (!data) {
                   [weak finishBusy];
                   [weak message:QHL(@"No sources updated")
                          detail:[NSString stringWithFormat:QHL(@"%@\n\nThe entire refresh was discarded. "
                                                                @"Every saved snapshot is unchanged."),
                                                            error.localizedDescription
                                                                ?: QHL(@"Download failed.")]];
                   return;
               }
               NSUInteger total = [weak.draft.document[@"allowlist"] length];
               for (NSUInteger i = 0; i < sources.count; i++) {
                   total += i == position ? data.length : [sources[i][@"data"] length];
               }
               if (total > QHMaximumDocumentBytes) {
                   [weak finishBusy];
                   [weak message:QHL(@"No sources updated")
                          detail:QHL(@"The prospective batch exceeds 32 MiB of raw data. Every saved "
                                     @"snapshot is unchanged.")];
                   return;
               }
               NSMutableDictionary *updated = [old mutableCopy];
               updated[@"data"] = data;
               sources[position] = updated;
               [weak refreshBatch:sources index:position + 1];
           }];
}
- (void)prepareApply {
    if (self.busy || !self.draft) {
        return;
    }
    self.busy = YES;
    [self render];
    QHStorePreview *draft = self.draft;
    __weak typeof(self) weak = self;
    [QHBridge
           request:@"status"
           payload:@{}
        completion:^(NSDictionary *status) {
            weak.status = status;
            if (![weak statusWritable:status]) {
                [weak finishBusy];
                [weak message:QHL(@"Cannot apply") detail:[weak statusExplanation:status]];
                return;
            }
            // Capture revision ONCE before the preview. Never fetch a new revision on Save.
            NSString *expectedRevision = [status[@"revision"] copy];
            [weak
                showPreview:draft
                      title:QHL(@"Apply local draft")
                     detail:
                         QHL(@"The helper will validate and atomically apply this generated blocklist. "
                             @"Existing baseline mappings are never silently overridden. A concurrent helper "
                             @"change rejects this preview. Applying files does not prove DNS filtering.")
                     button:QHL(@"Confirm Apply")
                    confirm:^{
                        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                            NSDictionary *payload = @{
                                @"expectedRevision" : expectedRevision,
                                @"hostsBase64" : [draft.compiled.hostsData base64EncodedStringWithOptions:0],
                                @"domainCount" : @(draft.compiled.domains.count)
                            };
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [QHBridge request:@"apply"
                                          payload:payload
                                       completion:^(NSDictionary *result) {
                                           if ([result[@"ok"] boolValue] &&
                                               [result[@"state"] isEqual:@"active"]) {
                                               weak.appliedLocalRevision = draft.document[@"revision"];
                                               weak.appliedHelperRevision = result[@"revision"];
                                           }
                                           [weak operationCompleted:result applied:YES];
                                       }];
                            });
                        });
                    }];
        }];
}
- (void)prepareHelperCommand:(NSString *)command {
    if (self.busy) {
        return;
    }
    self.busy = YES;
    [self render];
    __weak typeof(self) weak = self;
    [QHBridge request:@"status"
              payload:@{}
           completion:^(NSDictionary *status) {
               weak.status = status;
               BOOL disabling = [command isEqual:@"disable"];
               NSString *required = disabling ? @"active" : @"inactive";
               if (![weak statusWritable:status] || ![status[@"state"] isEqual:required]) {
                   [weak finishBusy];
                   [weak message:QHL(@"State changed") detail:[weak statusExplanation:status]];
                   return;
               }
               NSString *revision = [status[@"revision"] copy];
               UIAlertController *alert = [UIAlertController
                   alertControllerWithTitle:disabling ? QHL(@"Restore verified baseline?")
                                                      : QHL(@"Enable saved helper snapshot?")
                                    message:disabling
                                                ? QHL(@"The helper restores only its trusted baseline. Local "
                                                      @"sources are kept. Conflicting files cause refusal, "
                                                      @"not deletion.")
                                                : QHL(@"This enables the helper's stored snapshot, not the "
                                                      @"local draft. Use Apply to install draft changes.")
                             preferredStyle:UIAlertControllerStyleAlert];
               [alert addAction:[UIAlertAction actionWithTitle:QHL(@"Cancel")
                                                         style:UIAlertActionStyleCancel
                                                       handler:^(UIAlertAction *a) {
                                                           (void)a;
                                                           [weak finishBusy];
                                                       }]];
               [alert addAction:[UIAlertAction actionWithTitle:QHL(@"Confirm")
                                                         style:disabling ? UIAlertActionStyleDestructive
                                                                         : UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *a) {
                                                           (void)a;
                                                           [QHBridge request:command
                                                                     payload:@{@"expectedRevision" : revision}
                                                                  completion:^(NSDictionary *result) {
                                                                      weak.appliedLocalRevision = nil;
                                                                      weak.appliedHelperRevision = nil;
                                                                      [weak operationCompleted:result
                                                                                       applied:NO];
                                                                  }];
                                                       }]];
               [weak.rootController presentViewController:alert animated:Animate() completion:nil];
           }];
}
- (void)operationCompleted:(NSDictionary *)result applied:(BOOL)applied {
    self.status = result;
    self.pendingStatus = YES;
    BOOL ok = [result[@"ok"] boolValue];
    NSString *title = ok        ? QHL(@"File operation completed")
                      : applied ? QHL(@"Saved locally · not applied")
                                : QHL(@"Operation refused");
    NSString *detail;
    if (!ok) {
        detail = [self statusExplanation:result];
    } else if (result[@"reloadError"]) {
        detail = QHL(@"Files were saved, but the DNS reload request failed. This is not proof of protection. "
                     @"Review dependencies and check file state; apps may retain DNS caches.");
    } else if ([result[@"reloadRequested"] boolValue]) {
        detail = QHL(@"Files were saved and DNS reload was requested. This does not verify DNS filtering or "
                     @"clear every app's cache.");
    } else {
        detail = QHL(@"The helper verified the resulting file state. No DNS reload was requested. This is "
                     @"not a DNS protection test.");
    }
    [self finishBusy];
    [self message:title detail:detail];
}
@end
