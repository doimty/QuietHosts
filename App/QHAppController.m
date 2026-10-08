#import "QHAppController.h"
#import "QHVisualComponents.h"
#import "QHStore.h"
#import "QHDownload.h"
#include "QHImportLifecycle.h"
#import "../Shared/QHBridge.h"
#import "../Shared/QHLocalization.h"
#import "../Shared/QHStatusPresentation.h"
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
    return Color(0xf3f2f8, 0x13131a);
}
static UIColor *CardBackground(void) {
    return Color(0xffffff, 0x1d1d26);
}
static UIColor *Accent(void) {
    return Color(0x5b54e8, 0x9b95ff);
}
static UIColor *TextPrimary(void) {
    return Color(0x1b1b22, 0xf0eff8);
}
static UIColor *TextSecondary(void) {
    return Color(0x686875, 0x9e9ea8);
}
static UILabel *Label(NSString *text, UIFontTextStyle style, BOOL secondary) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = secondary ? TextSecondary() : TextPrimary();
    return label;
}
static UIStackView *Stack(void) {
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    return stack;
}
static UIButton *Button(NSString *text, BOOL primary, BOOL enabled, void (^action)(void)) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = primary ? UIButtonConfiguration.filledButtonConfiguration
                                            : UIButtonConfiguration.plainButtonConfiguration;
    config.title = text;
    config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    config.baseBackgroundColor = Accent();
    config.baseForegroundColor = primary ? Color(0xffffff, 0x13131a) : Accent();
    config.contentInsets = NSDirectionalEdgeInsetsMake(8, 12, 8, 12);
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *input) {
        NSMutableDictionary *attributes = [input mutableCopy];
        attributes[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        return attributes;
    };
    button.configuration = config;
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.enabled = enabled;
    button.accessibilityLabel = text;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
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
    self.stack.spacing = 14;
    [scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor
                                                 constant:18],
        [self.stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor
                                                  constant:-18],
        [self.stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [self.stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [self.stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-36]
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
    self.textView.backgroundColor = CardBackground();
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

@interface QHAppController () <UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
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
@property(nonatomic, strong) UIDocumentPickerViewController *filePicker;
@property(nonatomic, strong) QHDownload *download;
@property(nonatomic, strong) QHPage *sourceDetailPage;
@property(nonatomic, copy) NSString *detailSourceID;
@property(nonatomic) BOOL draftTipDismissed;
@property(nonatomic) int notificationToken;
@property(nonatomic) BOOL observing;
@end

@implementation QHAppController {
    QHImportLifecycle _fileImport;
}
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
            nav.navigationBar.prefersLargeTitles = NO;
            [nav setNavigationBarHidden:(i == 0) animated:NO];
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
        return QHL(@"Hosts file state is conflicting");
    }
    if (![self.status[@"ok"] boolValue]) {
        return QHL(@"File state unavailable");
    }
    if ([state isEqual:@"active"]) {
        return QHL(@"Hosts rules are enabled");
    }
    if ([state isEqual:@"inactive"]) {
        return QHL(@"Hosts rules are paused");
    }
    if ([state isEqual:@"unmanaged"]) {
        return QHL(@"Hosts rules are not applied");
    }
    return QHL(@"File state unavailable");
}
- (NSString *)statusExplanation:(NSDictionary *)status {
    return QHStatusExplanation(status);
}
- (void)addHeading:(NSString *)text to:(UIStackView *)stack {
    [stack addArrangedSubview:Label(text, UIFontTextStyleHeadline, NO)];
}
- (NSString *)shortState {
    if (!self.status) return QHL(@"Checking file state");
    if (![self statusWritable:self.status]) return QHL(@"Needs attention");
    if ([self.status[@"state"] isEqual:@"active"]) return QHL(@"Enabled");
    if ([self.status[@"state"] isEqual:@"inactive"]) return QHL(@"Paused");
    return QHL(@"Not applied");
}
- (BOOL)hasOnlineSources {
    for (NSDictionary *source in self.draft.document[@"sources"]) {
        if ([source[@"kind"] isEqual:@"url"] && [source[@"enabled"] boolValue]) return YES;
    }
    return NO;
}
- (void)render {
    for (QHPage *page in self.pages) [page clear];
    __weak typeof(self) weak = self;
    UIStackView *home = self.pages[0].stack;
    BOOL writable = [self statusWritable:self.status];
    BOOL active = writable && [self.status[@"state"] isEqual:@"active"];
    BOOL inactive = writable && [self.status[@"state"] isEqual:@"inactive"];
    [home addArrangedSubview:QHVBrandHeader(QHL(@"QuietHosts"), self.shortState, active,
                                           QHL(@"Local Hosts rules"))];
    UIStackView *managed = QHVCard();
    UISwitch *mainSwitch = [UISwitch new];
    mainSwitch.onTintColor = Accent();
    mainSwitch.on = active;
    mainSwitch.enabled = !self.busy && (active || inactive);
    mainSwitch.accessibilityLabel = QHL(@"Hosts rules");
    mainSwitch.accessibilityHint = QHL(@"Uses saved rules. Confirmation is required; the local draft is applied separately.");
    [mainSwitch addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        UISwitch *sender = (UISwitch *)action.sender;
        BOOL requested = sender.on;
        [sender setOn:active animated:NO];
        if (weak.busy || ![weak statusWritable:weak.status]) return;
        [weak prepareHelperCommand:requested ? @"enable" : @"disable"];
    }] forControlEvents:UIControlEventValueChanged];
    [managed addArrangedSubview:QHVInfo(QHL(@"Hosts rules"), self.stateTitle, @"shield", mainSwitch)];
    [managed addArrangedSubview:QHVSeparator()];
    [managed addArrangedSubview:Label([self statusExplanation:self.status], UIFontTextStyleFootnote, YES)];
    if (writable && [self.status[@"domainCount"] isKindOfClass:NSNumber.class] && (active || inactive)) {
        NSString *format = active ? QHL(@"Rules in managed Hosts: %@ domains") : QHL(@"Saved rule set: %@ domains");
        [managed addArrangedSubview:Label([NSString stringWithFormat:format,
            Number([self.status[@"domainCount"] unsignedIntegerValue])], UIFontTextStyleSubheadline, NO)];
    }
    [home addArrangedSubview:managed];
    if (!self.draftTipDismissed) {
        UIStackView *tip = QHVCard();
        [tip addArrangedSubview:QHVNote(QHL(@"Draft is stored on this device. Apply it to update managed Hosts."), @"bolt")];
        [tip addArrangedSubview:QHVRow(QHL(@"Hide this tip"), nil, @"xmark", nil, NO, YES, ^{
            weak.draftTipDismissed = YES;
            [weak render];
        })];
        [home addArrangedSubview:tip];
    }
    if (self.storeError) {
        UIStackView *failure = QHVCard();
        [failure addArrangedSubview:QHVInfo(QHL(@"Local draft unavailable"), self.storeError.localizedDescription,
                                          @"exclamationmark.triangle", nil)];
        [failure addArrangedSubview:QHVRow(QHL(@"Read local storage again"), nil, @"arrow.clockwise", nil,
                                          NO, !self.busy, ^{ [weak start]; })];
        [home addArrangedSubview:failure];
    } else if (self.draft) {
        UIStackView *draftCard = QHVCard();
        NSString *sourceSummary = [NSString stringWithFormat:QHL(@"%@ sources · %@ exact allowlist entries"),
            Number([self.draft.document[@"sources"] count]), Number(self.draft.allowlistCount)];
        [draftCard addArrangedSubview:QHVRow(QHL(@"Draft"), sourceSummary, @"doc.text", nil, NO, YES, ^{
            weak.rootController.selectedIndex = 1;
        })];
        [draftCard addArrangedSubview:QHVStats(QHL(@"Unique domains"), Number(self.draft.compiled.domains.count),
            QHL(@"Merge duplicates"), Number([self.draft.compiled.statistics[@"duplicates"] unsignedIntegerValue]))];
        [draftCard addArrangedSubview:QHVSeparator()];
        BOOL same = [self.appliedLocalRevision isEqual:self.draft.document[@"revision"]] &&
                    [self.appliedHelperRevision isEqual:self.status[@"revision"]] && active;
        [draftCard addArrangedSubview:Label(same ? QHL(@"This draft was confirmed applied in this session.") :
            QHL(@"Draft changes are not applied automatically."), UIFontTextStyleFootnote, YES)];
        [draftCard addArrangedSubview:QHVFormRow(QHL(@"Generated file size"),
            [NSByteCountFormatter stringFromByteCount:(int64_t)self.draft.compiled.hostsData.length
                                           countStyle:NSByteCountFormatterCountStyleFile])];
        [home addArrangedSubview:draftCard];
    }
    [home addArrangedSubview:Button(QHL(@"Apply draft"), YES, !self.busy && self.draft != nil, ^{
        [weak prepareApply];
    })];
    [home addArrangedSubview:QHVSection(QHL(@"Actions"))];
    UIStackView *actions = QHVCard();
    if (self.download) {
        [actions addArrangedSubview:QHVRow(QHL(@"Cancel download"), nil, @"xmark.circle", nil, NO, YES, ^{
            [weak.download cancel];
        })];
        [actions addArrangedSubview:QHVSeparator()];
    } else if ([self hasOnlineSources]) {
        [actions addArrangedSubview:QHVRow(QHL(@"Update online sources"), QHL(@"Manual refresh; failed updates keep existing snapshots."),
            @"arrow.clockwise", nil, NO, !self.busy, ^{ [weak refreshSources]; })];
        [actions addArrangedSubview:QHVSeparator()];
    }
    [actions addArrangedSubview:QHVRow(QHL(@"Refresh file status"), QHL(@"Verify managed Hosts and helper state."),
        @"checkmark.shield", nil, NO, !self.busy, ^{ [weak refreshStatus]; })];
    [actions addArrangedSubview:QHVSeparator()];
    [actions addArrangedSubview:QHVRow(QHL(@"Advanced information"), QHL(@"Dependencies, diagnostics and backup state."),
        @"info.circle", nil, NO, !self.busy, ^{ [weak showDiagnostics:YES]; })];
    [home addArrangedSubview:actions];
    [home addArrangedSubview:Label(self.busy ? QHL(@"Working…") :
        QHL(@"Online sources update only when requested. Reimport files or pasted text to refresh them."),
        UIFontTextStyleFootnote, YES)];
    [self renderRules];
    [self renderSettings];
    [self renderSourceDetail];
}
- (NSString *)sourceKind:(NSDictionary *)source {
    return [source[@"kind"] isEqual:@"url"] ? QHL(@"HTTPS source · manual refresh") :
           [source[@"kind"] isEqual:@"file"] ? QHL(@"Local file · reimport to update") :
                                               QHL(@"Pasted text · reimport to update");
}
- (void)openSource:(NSString *)identifier {
    self.detailSourceID = identifier;
    QHPage *page = [QHPage new];
    self.sourceDetailPage = page;
    [self renderSourceDetail];
    [self.pages[1].navigationController pushViewController:page animated:Animate()];
}
- (void)renderSourceDetail {
    QHPage *page = self.sourceDetailPage;
    if (!page) return;
    [page clear];
    NSDictionary *source = nil;
    for (NSDictionary *item in self.draft.document[@"sources"]) {
        if ([item[@"id"] isEqual:self.detailSourceID]) { source = item; break; }
    }
    if (!source) {
        page.title = QHL(@"Rule source");
        [page.stack addArrangedSubview:QHVNote(QHL(@"This source is no longer in the local draft."), @"doc")];
        return;
    }
    page.title = source[@"name"];
    NSString *identifier = source[@"id"];
    __weak typeof(self) weak = self;
    QHParseResult *result = self.draft.sourceResults[identifier];
    UIStackView *summary = QHVCard();
    UISwitch *toggle = [UISwitch new];
    toggle.onTintColor = Accent();
    toggle.on = [source[@"enabled"] boolValue];
    toggle.enabled = !self.busy;
    toggle.accessibilityLabel = [NSString stringWithFormat:QHL(@"Include source: %@"), source[@"name"]];
    toggle.accessibilityHint = QHL(@"Changes only the local draft. Apply separately.");
    [toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        UISwitch *sender = (UISwitch *)action.sender;
        BOOL enabled = sender.on;
        [sender setOn:!enabled animated:NO];
        [weak toggleSource:identifier enabled:enabled];
    }] forControlEvents:UIControlEventValueChanged];
    [summary addArrangedSubview:QHVInfo(source[@"name"], [self sourceKind:source],
        [source[@"kind"] isEqual:@"url"] ? @"link" : @"doc.text", toggle)];
    [summary addArrangedSubview:QHVSeparator()];
    [summary addArrangedSubview:QHVFormRow(QHL(@"Parsed domains"), Number(result.domains.count))];
    [summary addArrangedSubview:QHVFormRow(QHL(@"Source bytes"), Number([source[@"data"] length]))];
    NSUInteger skipped = [result.statistics[@"unsupported"] unsignedIntegerValue];
    [summary addArrangedSubview:QHVFormRow(QHL(@"Unsupported rules"), Number(skipped))];
    [summary addArrangedSubview:QHVFormRow(QHL(@"Invalid entries"), Number([result.statistics[@"invalid"] unsignedIntegerValue]))];
    [page.stack addArrangedSubview:summary];
    [page.stack addArrangedSubview:QHVNote(QHL(@"Exact DOMAIN/HOST records are converted. Suffix, keyword, IP-range and URL rules are skipped."), @"info.circle")];
    UIStackView *remove = QHVCard();
    [remove addArrangedSubview:QHVRow(QHL(@"Remove from local draft"), QHL(@"Existing managed Hosts remain unchanged until Apply."),
        @"trash", nil, YES, !self.busy, ^{ [weak removeSource:identifier]; })];
    [page.stack addArrangedSubview:remove];
}
- (void)renderRules {
    UIStackView *rules = self.pages[1].stack;
    __weak typeof(self) weak = self;
    [rules addArrangedSubview:QHVSection(QHL(@"Rule sources"))];
    if (!self.draft) {
        [rules addArrangedSubview:QHVNote(QHL(@"Local storage must load successfully before you can change rules."), @"exclamationmark.triangle")];
        return;
    }
    NSArray *sources = self.draft.document[@"sources"];
    UIStackView *list = QHVCard();
    if (!sources.count) {
        [list addArrangedSubview:QHVInfo(QHL(@"Start with a source you trust"),
            QHL(@"No bundled lists. Import a URL, file, or pasted text, review the merged preview, then save locally."), @"doc.badge.plus", nil)];
        [list addArrangedSubview:QHVSeparator()];
    }
    for (NSDictionary *source in sources) {
        NSString *identifier = source[@"id"];
        QHParseResult *result = self.draft.sourceResults[identifier];
        NSString *subtitle = [NSString stringWithFormat:QHL(@"%@ · %@ · %@ unsupported"),
            [self sourceKind:source], [source[@"enabled"] boolValue] ? QHL(@"Included") : QHL(@"Excluded"),
            Number([result.statistics[@"unsupported"] unsignedIntegerValue])];
        NSString *symbol = [source[@"kind"] isEqual:@"url"] ? @"link" :
                           [source[@"kind"] isEqual:@"file"] ? @"doc" : @"text.alignleft";
        [list addArrangedSubview:QHVRow(source[@"name"], subtitle, symbol,
            Number(result.domains.count), NO, YES, ^{ [weak openSource:identifier]; })];
        [list addArrangedSubview:QHVSeparator()];
    }
    [list addArrangedSubview:QHVRow(QHL(@"Add source"), QHL(@"URL, local file or pasted text"), @"plus", nil,
        NO, !self.busy && sources.count < QHMaximumSources, ^{ [weak chooseImport:NO]; })];
    [rules addArrangedSubview:list];
    [rules addArrangedSubview:QHVSection(QHL(@"Allowlist"))];
    UIStackView *allow = QHVCard();
    [allow addArrangedSubview:QHVRow(QHL(@"Exact allowlist"), QHL(@"Only exact domains are excluded from our generated blocklist."),
        @"checkmark", Number(self.draft.allowlistCount), NO, !self.busy, ^{ [weak chooseImport:YES]; })];
    [rules addArrangedSubview:allow];
    [rules addArrangedSubview:QHVSection(QHL(@"Rule formats"))];
    UIStackView *formats = QHVCard();
    [formats addArrangedSubview:QHVInfo(QHL(@"Exact DOMAIN / HOST"), QHL(@"Hosts entries, bare domains and exact blocking domain rules."),
        @"shippingbox", nil)];
    [formats addArrangedSubview:QHVSeparator()];
    [formats addArrangedSubview:QHVInfo(QHL(@"Unsupported rules"), QHL(@"Suffix, keyword, IP-range, URL and unknown policies are not flattened."),
        @"nosign", nil)];
    [rules addArrangedSubview:formats];
    [rules addArrangedSubview:Label(QHL(@"Saving, toggling, or removing a source changes only the local draft. Existing managed Hosts stay unchanged until Apply."),
        UIFontTextStyleFootnote, YES)];
}
- (NSString *)themeTitle {
    NSString *theme = [NSUserDefaults.standardUserDefaults stringForKey:@"QHTheme"];
    return [theme isEqual:@"light"] ? QHL(@"Light") : [theme isEqual:@"dark"] ? QHL(@"Dark") : QHL(@"System");
}
- (void)showThemePicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:QHL(@"Theme") message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *keys = @[ @"system", @"light", @"dark" ];
    NSArray *titles = @[ QHL(@"System"), QHL(@"Light"), QHL(@"Dark") ];
    __weak typeof(self) weak = self;
    for (NSUInteger index = 0; index < keys.count; index++) {
        NSString *key = keys[index];
        [alert addAction:[UIAlertAction actionWithTitle:titles[index] style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *action) {
                (void)action;
                [NSUserDefaults.standardUserDefaults setObject:key forKey:@"QHTheme"];
                [weak applyThemeToWindow:weak.rootController.view.window];
                [weak render];
            }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:QHL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.pages[2].view;
    alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.pages[2].view.bounds),
        CGRectGetMidY(self.pages[2].view.bounds), 1, 1);
    [self.presenter presentViewController:alert animated:Animate() completion:nil];
}
- (void)renderSettings {
    UIStackView *settings = self.pages[2].stack;
    __weak typeof(self) weak = self;
    [settings addArrangedSubview:QHVSection(QHL(@"Appearance"))];
    UIStackView *appearance = QHVCard();
    [appearance addArrangedSubview:QHVRow(QHL(@"Theme"), self.themeTitle, @"paintpalette", nil, NO, YES, ^{
        [weak showThemePicker];
    })];
    [settings addArrangedSubview:appearance];
    [settings addArrangedSubview:QHVSection(QHL(@"Rules and files"))];
    UIStackView *data = QHVCard();
    [data addArrangedSubview:QHVRow(QHL(@"Update online sources"), QHL(@"Manual refresh; failed updates keep existing snapshots."),
        @"arrow.clockwise", nil, NO, !self.busy && [self hasOnlineSources], ^{ [weak refreshSources]; })];
    [data addArrangedSubview:QHVSeparator()];
    [data addArrangedSubview:QHVRow(QHL(@"Refresh file status"), QHL(@"Verify managed Hosts and helper state."),
        @"checkmark.shield", nil, NO, !self.busy, ^{ [weak refreshStatus]; })];
    [data addArrangedSubview:QHVSeparator()];
    [data addArrangedSubview:QHVRow(QHL(@"Backup and restore"), QHL(@"Review the helper's retained baseline."),
        @"externaldrive", nil, NO, !self.busy, ^{ [weak showDiagnostics:NO]; })];
    [data addArrangedSubview:QHVSeparator()];
    [data addArrangedSubview:QHVRow(QHL(@"Retry DNS reload"), QHL(@"Request a DNS service restart without changing Hosts."),
        @"arrow.triangle.2.circlepath", nil, NO, !self.busy && [self statusWritable:self.status], ^{ [weak retryReload]; })];
    [data addArrangedSubview:QHVSeparator()];
    [data addArrangedSubview:QHVRow(QHL(@"Advanced information"), QHL(@"Dependencies, diagnostics and backup state."),
        @"info.circle", nil, NO, !self.busy, ^{ [weak showDiagnostics:YES]; })];
    [settings addArrangedSubview:data];
    if ([self statusWritable:self.status] && [self.status[@"state"] isEqual:@"active"]) {
        UIStackView *restore = QHVCard();
        [restore addArrangedSubview:QHVRow(QHL(@"Pause rules and restore original Hosts"),
            QHL(@"Keeps local sources; restores only the verified baseline."), @"trash", nil, YES, !self.busy, ^{
                [weak prepareHelperCommand:@"disable"];
            })];
        [settings addArrangedSubview:restore];
    } else if ([self statusWritable:self.status] && [self.status[@"state"] isEqual:@"inactive"]) {
        UIStackView *resume = QHVCard();
        [resume addArrangedSubview:QHVRow(QHL(@"Resume saved rules"), QHL(@"This does not apply local draft changes."),
            @"play.circle", nil, NO, !self.busy, ^{ [weak prepareHelperCommand:@"enable"]; })];
        [settings addArrangedSubview:resume];
    }
    [settings addArrangedSubview:QHVSection(QHL(@"About"))];
    UIStackView *about = QHVCard();
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *version = [NSString stringWithFormat:@"%@ (%@)",
        [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"—",
        [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"—"];
    [about addArrangedSubview:QHVInfo(QHL(@"QuietHosts"), QHL(@"Version"), @"shield", QHVBadge(version, NO))];
    [about addArrangedSubview:QHVSeparator()];
    [about addArrangedSubview:QHVRow(QHL(@"Dependencies"), @"LetMeBlock · libSandy", @"square.stack.3d.up", nil,
        NO, !self.busy, ^{ [weak showDiagnostics:YES]; })];
    [settings addArrangedSubview:about];
    [settings addArrangedSubview:Label(QHL(@"Local hosts rules. No scheduled refresh or per-domain DNS lookups."),
        UIFontTextStyleFootnote, YES)];
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
            QHL(@"%@\n\nRequired: native RootHide, LetMeBlock 1.3.0-1+native1, libSandy 1.1.6-4. "
                @"Installed versions are not verified here.\n\nFixed managed entry: "
                @"jbroot('/etc/hosts'). RootHide may mirror this as a symlink. Only the helper may "
                @"replace the entry after validation; this app never writes system Hosts.\n\nLocal "
                @"sources: this app's Application Support/QuietHosts. Source URLs are private local "
                @"refresh metadata. No arbitrary path operations are available."),
                detail];
        detail = [[self statusExplanation:self.status] stringByAppendingFormat:@"\n\n%@", detail];
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
    UIStackView *intro = QHVCard();
    [intro addArrangedSubview:QHVInfo(title, detail, @"doc.text", nil)];
    [page.stack addArrangedSubview:intro];
    UIStackView *counts = QHVCard();
    NSDictionary *s = preview.compiled.statistics, *p = preview.parseStatistics;
    [counts addArrangedSubview:QHVFormRow(QHL(@"Merged unique domains"), Number(preview.compiled.domains.count))];
    [counts addArrangedSubview:QHVSeparator()];
    [counts addArrangedSubview:QHVFormRow(QHL(@"Merge duplicates"), Number([s[@"duplicates"] unsignedIntegerValue]))];
    [counts addArrangedSubview:QHVSeparator()];
    [counts addArrangedSubview:QHVFormRow(QHL(@"Allowlist exclusions"), Number([s[@"excluded"] unsignedIntegerValue]))];
    [counts addArrangedSubview:QHVSeparator()];
    [counts addArrangedSubview:QHVFormRow(QHL(@"Generated file size"),
        [NSByteCountFormatter stringFromByteCount:(int64_t)preview.compiled.hostsData.length
                                       countStyle:NSByteCountFormatterCountStyleFile])];
    [page.stack addArrangedSubview:counts];
    [page.stack addArrangedSubview:QHVSection(QHL(@"All source inputs, including disabled sources:"))];
    UIStackView *inputs = QHVCard();
    [inputs addArrangedSubview:QHVFormRow(QHL(@"Accepted domains"), Number([p[@"accepted"] unsignedIntegerValue]))];
    [inputs addArrangedSubview:QHVSeparator()];
    [inputs addArrangedSubview:QHVFormRow(QHL(@"Input duplicates"), Number([p[@"duplicates"] unsignedIntegerValue]))];
    [inputs addArrangedSubview:QHVSeparator()];
    [inputs addArrangedSubview:QHVFormRow(QHL(@"Redirects"), Number([p[@"redirects"] unsignedIntegerValue]))];
    [inputs addArrangedSubview:QHVSeparator()];
    [inputs addArrangedSubview:QHVFormRow(QHL(@"Local metadata"), Number([p[@"local"] unsignedIntegerValue]))];
    [inputs addArrangedSubview:QHVSeparator()];
    [inputs addArrangedSubview:QHVFormRow(QHL(@"Invalid entries"), Number([p[@"invalid"] unsignedIntegerValue]))];
    [inputs addArrangedSubview:QHVSeparator()];
    [inputs addArrangedSubview:QHVFormRow(QHL(@"Unsupported rules"), Number([p[@"unsupported"] unsignedIntegerValue]))];
    [page.stack addArrangedSubview:inputs];
    [page.stack addArrangedSubview:QHVNote(QHL(@"Exact DOMAIN/HOST records are converted. Suffix, keyword, IP-range and URL rules are skipped."), @"info.circle")];
    [page.stack addArrangedSubview:Button(button, YES, YES, ^{
                    weakPage.view.userInteractionEnabled = NO;
                    [weakNav dismissViewControllerAnimated:Animate() completion:confirm];
                })];
    UIStackView *sampleCard = QHVCard();
    [sampleCard addArrangedSubview:QHVRow(QHL(@"Sample · first 50 merged domains at most"), nil,
        @"text.alignleft", nil, NO, YES, ^{
            QHPage *samplePage = [QHPage new];
            samplePage.title = QHL(@"Sample · first 50 merged domains at most");
            [samplePage loadViewIfNeeded];
            NSUInteger count = MIN((NSUInteger)50, preview.compiled.domains.count);
            NSString *sample = count ? [[preview.compiled.domains subarrayWithRange:NSMakeRange(0, count)]
                componentsJoinedByString:@"\n"] : QHL(@"No generated domains");
            [samplePage.stack addArrangedSubview:Label(sample, UIFontTextStyleFootnote, NO)];
            [weakNav pushViewController:samplePage animated:Animate()];
        })];
    [page.stack addArrangedSubview:sampleCard];
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
                   detail:saved ? QHL(@"Draft saved. Managed Hosts were not changed. Return to Home and choose Apply draft to install these rules.")
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
                                     : QHL(@"Hosts, bare domains, exact DOMAIN and HOST rules are supported. Preview before saving. Suffix, keyword, IP-range and URL rules cannot be expressed by Hosts and are skipped. Large lists should be imported as files.")
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
    self.filePicker = picker;
    QHImportBegin(&_fileImport, (__bridge const void *)picker);
    // A swipe dismissal on iOS15 need not send documentPickerWasCancelled.
    picker.presentationController.delegate = self;
    __weak typeof(self) weak = self;
    [self.rootController presentViewController:picker animated:Animate() completion:^{
        if (weak.filePicker == picker) picker.presentationController.delegate = weak;
    }];
}
- (void)cancelFilePicker:(UIDocumentPickerViewController *)picker {
    if (!QHImportCancel(&_fileImport, (__bridge const void *)picker)) return;
    self.filePicker = nil;
    self.pickingAllowlist = NO;
    [self finishBusy];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self cancelFilePicker:controller];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    UIViewController *dismissed = presentationController.presentedViewController;
    if ([dismissed isKindOfClass:UIDocumentPickerViewController.class]) {
        [self cancelFilePicker:(UIDocumentPickerViewController *)dismissed];
    }
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.count == 1 ? urls.firstObject : nil;
    if (!url) { [self cancelFilePicker:controller]; return; }
    uint64_t generation = QHImportSelect(&_fileImport, (__bridge const void *)controller);
    if (!generation) return; // stale selection after cancellation/new picker
    BOOL allowlist = self.pickingAllowlist;
    self.pickingAllowlist = NO;
    self.filePicker = nil;
    __weak typeof(self) weak = self;
    void (^readSelectedFile)(void) = ^{
        QHAppController *owner = weak;
        if (!owner || !QHImportIsReading(&owner->_fileImport, generation)) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            NSData *data = [QHStore readImportURL:url error:&error];
            NSString *name = url.lastPathComponent;
            if (!name.length || name.length > 120 ||
                [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
                name = QHL(@"Local file");
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                QHAppController *current = weak;
                if (!current || !QHImportFinishRead(&current->_fileImport, generation)) return;
                if (!data) {
                    [current finishBusy];
                    [current message:QHL(@"Nothing saved") detail:error.localizedDescription];
                    return;
                }
                [current stageData:data kind:@"file" name:name URL:nil allowlist:allowlist];
            });
        });
    };
    // Mark Reading BEFORE dismissal: its late dismiss/cancel callback must not
    // unlock buttons while the selected file is being validated off-main.
    if (controller.presentingViewController) {
        [controller dismissViewControllerAnimated:Animate() completion:readSelectedFile];
    } else {
        readSelectedFile();
    }
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
            BOOL adoption = QHStatusRequiresAdoption(status);
            [weak
                showPreview:draft
                      title:adoption ? QHL(@"Back up and adopt basic Hosts") : QHL(@"Apply draft")
                     detail:
                         adoption
                             ? QHL(@"You are authorizing QuietHosts to take over the existing basic Hosts "
                                   @"file. The helper will preserve its exact contents and permissions "
                                   @"before applying this draft. Disable restores that saved file. If the "
                                   @"file or directory mapping changes after this preview, the operation is "
                                   @"refused. No directory ownership or links will be repaired "
                                   @"automatically.")
                             : QHL(@"This will validate and update the managed Hosts file. The original system "
                                   @"Hosts file is not written through. Success confirms file state only; "
                                   @"DNS blocking is not tested.")
                     button:adoption ? QHL(@"Confirm backup and Apply") : QHL(@"Confirm Apply")
                    confirm:^{
                        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                            NSMutableDictionary *payload = [@{
                                @"expectedRevision" : expectedRevision,
                                @"hostsBase64" : [draft.compiled.hostsData base64EncodedStringWithOptions:0],
                                @"domainCount" : @(draft.compiled.domains.count)
                            } mutableCopy];
                            // Send consent only from this explicitly approved first-apply preview.
                            if (adoption) {
                                payload[@"adoptExistingHosts"] = @YES;
                            }
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
                                                      : QHL(@"Resume saved rules?")
                                    message:disabling
                                                ? QHL(@"The helper restores only its trusted baseline. Local "
                                                      @"sources are kept. Conflicting files cause refusal, "
                                                      @"not deletion.")
                                                : QHL(@"The saved managed rules will be enabled. This does "
                                                    @"not apply changes in the local draft.")
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
        detail = [detail stringByAppendingFormat:@"\n\n%@",
            [NSString stringWithFormat:QHL(@"DNS reload diagnostic: %@"),
                QHStatusErrorCode(@{@"errorCode":result[@"reloadError"]})]];
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
