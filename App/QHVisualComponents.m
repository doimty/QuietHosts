#import "QHVisualComponents.h"

#if defined(QH_TESTING)
extern void QHSmokeLayoutTrace(UIView *view, const char *phase);
#define QHV_LAYOUT_TRACE(view, phase) QHSmokeLayoutTrace((view), (phase))
#else
#define QHV_LAYOUT_TRACE(view, phase) do { } while (0)
#endif

static UIColor *VColor(unsigned light, unsigned dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        unsigned rgb = traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
        return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                               green:((rgb >> 8) & 255) / 255.0
                                blue:(rgb & 255) / 255.0 alpha:1];
    }];
}
UIColor *QHVBackgroundColor(void) { return VColor(0xe9e7f0, 0x0e0e13); }
UIColor *QHVCardColor(void) { return VColor(0xffffff, 0x1c1c24); }
UIColor *QHVInnerColor(void) { return VColor(0xf5f3fb, 0x252430); }
UIColor *QHVAccentColor(void) { return VColor(0x5644cc, 0xaba0ff); }
UIColor *QHVPrimaryTextColor(void) { return VColor(0x211d30, 0xf4f2fa); }
UIColor *QHVSecondaryTextColor(void) { return VColor(0x645f70, 0xaea8bb); }
UIColor *QHVLineColor(void) { return VColor(0xe2deed, 0x35323f); }
UIColor *QHVDestructiveColor(void) { return VColor(0xae243e, 0xff929f); }
UIColor *QHVPrimaryForegroundColor(void) { return VColor(0xffffff, 0x171322); }
static UIColor *VTile(void) { return VColor(0xede8fb, 0x332d4d); }
/* The managed card is a neutral surface: the status colour (green/amber) is the
 * signal, the way a protection app marks an active shield. Lavender stays for
 * brand and the primary action only. */
static UIColor *VHero(void) { return VColor(0xffffff, 0x1c1c24); }
static UIColor *VDangerBackground(void) { return VColor(0xffedf1, 0x402630); }
static UIColor *VGood(void) { return VColor(0x246449, 0x93dcba); }
static UIColor *VGoodBackground(void) { return VColor(0xe4f1e9, 0x223b31); }
static UIColor *VAttention(void) { return VColor(0x875018, 0xefc083); }
static UIColor *VAttentionBackground(void) { return VColor(0xf7ecdb, 0x423324); }
static UIColor *VBorder(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (traits.accessibilityContrast == UIAccessibilityContrastHigh) {
            return [VColor(0xb7afcc, 0x756b8b) resolvedColorWithTraitCollection:traits];
        }
        return [QHVLineColor() resolvedColorWithTraitCollection:traits];
    }];
}
static UILabel *VLabel(NSString *text, UIFontTextStyle style, BOOL secondary) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    label.textColor = secondary ? QHVSecondaryTextColor() : QHVPrimaryTextColor();
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh
                                          forAxis:UILayoutConstraintAxisVertical];
    return label;
}
static UILabel *VTypeLabel(NSString *text, UIFontTextStyle style, CGFloat size,
                           UIFontWeight weight, BOOL secondary) {
    UILabel *label = VLabel(text, style, secondary);
    label.font = [[UIFontMetrics metricsForTextStyle:style]
        scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
    return label;
}
static UIStackView *VStack(void) {
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    return stack;
}

// Layer CGColors cannot inherit UIColor's dynamic provider. Resolve them again
// for the actual view traits, including increased contrast and window changes.
typedef NS_ENUM(NSUInteger, QHVSurfaceStyle) {
    QHVSurfaceStyleCard,
    QHVSurfaceStyleInset,
    QHVSurfaceStyleHero
};
@interface QHVSurfaceStack : UIStackView
@property(nonatomic) QHVSurfaceStyle surfaceStyle;
- (void)updateChrome;
@end
@implementation QHVSurfaceStack
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.axis = UILayoutConstraintAxisVertical;
        self.spacing = 8;
        self.layoutMarginsRelativeArrangement = YES;
        self.layoutMargins = UIEdgeInsetsMake(14, 14, 14, 14);
        self.layer.cornerRadius = 16;
        [self updateChrome];
    }
    return self;
}
- (void)setSurfaceStyle:(QHVSurfaceStyle)surfaceStyle {
    _surfaceStyle = surfaceStyle;
    [self updateChrome];
    if (surfaceStyle == QHVSurfaceStyleHero) {
        // The managed-state hero is the one card that must read first on Home:
        // larger radius and breathing room, no shadow, no new hue.
        self.layer.cornerRadius = 22;
        self.layoutMargins = UIEdgeInsetsMake(18, 18, 18, 18);
        self.spacing = 10;
    }
}
- (void)updateChrome {
    self.backgroundColor = self.surfaceStyle == QHVSurfaceStyleHero ? VHero() :
        self.surfaceStyle == QHVSurfaceStyleInset ? QHVInnerColor() : QHVCardColor();
    CGFloat scale = self.window ? self.window.screen.scale : UIScreen.mainScreen.scale;
    self.layer.borderWidth = self.traitCollection.accessibilityContrast == UIAccessibilityContrastHigh
        ? 1.0 : 1.0 / MAX(scale, 1.0);
    self.layer.borderColor = [VBorder() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    // Flat grouped surfaces: a hairline border separates cards cleanly, while a
    // soft drop shadow on every card is what made the layout read as a mockup.
    self.layer.shadowOpacity = 0;
    self.layer.shadowRadius = 0;
    self.layer.shadowOffset = CGSizeZero;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!previousTraitCollection ||
        [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] ||
        self.traitCollection.accessibilityContrast != previousTraitCollection.accessibilityContrast ||
        self.traitCollection.displayScale != previousTraitCollection.displayScale) {
        [self updateChrome];
    }
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateChrome];
}
- (void)layoutSubviews {
    QHV_LAYOUT_TRACE(self, "surface-before-super");
    [super layoutSubviews];
    QHV_LAYOUT_TRACE(self, "surface-after-super");
}
@end

// Reflow follows the real available width and the current Dynamic Type scale.
// Auxiliary sizes use a single column; no fixed row or page height is imposed.
@interface QHVFlexibleStack : UIStackView
@property(nonatomic) CGFloat baseWidth;
@property(nonatomic) BOOL equalColumns;
@property(nonatomic, strong) id categoryObserver;
@end
@implementation QHVFlexibleStack
- (void)updateFlow {
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat threshold = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledValueForValue:self.baseWidth compatibleWithTraitCollection:self.traitCollection];
    BOOL narrow = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
        || (width > 0 && width < threshold);
    UILayoutConstraintAxis desired = narrow ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    if (self.axis != desired) self.axis = desired;
    UIStackViewAlignment alignment = narrow ? (self.equalColumns ? UIStackViewAlignmentFill : UIStackViewAlignmentLeading) : UIStackViewAlignmentCenter;
    if (self.alignment != alignment) self.alignment = alignment;
    UIStackViewDistribution distribution = (!narrow && self.equalColumns) ? UIStackViewDistributionFillEqually : UIStackViewDistributionFill;
    if (self.distribution != distribution) self.distribution = distribution;
}
- (void)layoutSubviews {
    QHV_LAYOUT_TRACE(self, "flow-before-update");
    [self updateFlow];
    QHV_LAYOUT_TRACE(self, "flow-before-super");
    [super layoutSubviews];
    QHV_LAYOUT_TRACE(self, "flow-after-super");
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        __weak typeof(self) weak = self;
        _categoryObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:UIContentSizeCategoryDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) {
                (void)notification;
                [weak setNeedsLayout];
            }];
    }
    return self;
}
- (void)dealloc {
    if (_categoryObserver) [NSNotificationCenter.defaultCenter removeObserver:_categoryObserver];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self setNeedsLayout];
}
@end
static QHVFlexibleStack *VFlow(CGFloat threshold) {
    QHVFlexibleStack *stack = [QHVFlexibleStack new];
    stack.baseWidth = threshold;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 10;
    return stack;
}
static void VPin(UIView *container, UIView *content, CGFloat inset) {
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:inset],
        [content.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-inset],
        [content.topAnchor constraintEqualToAnchor:container.topAnchor constant:inset],
        [content.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-inset]
    ]];
}
UIStackView *QHVCard(void) {
    return [QHVSurfaceStack new];
}
static UIView *VIconTile(NSString *symbol, BOOL large, UIColor *foreground, UIColor *background) {
    UIView *tile = [UIView new];
    CGFloat side = large ? 48 : 32;
    tile.backgroundColor = background;
    tile.layer.cornerRadius = large ? 16 : 10;
    tile.isAccessibilityElement = NO;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration
        configurationWithPointSize:large ? 25 : 17 weight:UIImageSymbolWeightMedium];
    UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:configuration]];
    image.tintColor = foreground;
    image.contentMode = UIViewContentModeScaleAspectFit;
    image.isAccessibilityElement = NO;
    image.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:image];
    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:side],
        [tile.heightAnchor constraintEqualToConstant:side],
        [image.widthAnchor constraintEqualToConstant:large ? 26 : 18],
        [image.heightAnchor constraintEqualToConstant:large ? 26 : 18],
        [image.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [image.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor]
    ]];
    return tile;
}
UIView *QHVIconTile(NSString *symbol, BOOL large, BOOL danger) {
    return VIconTile(symbol, large, danger ? QHVDestructiveColor() : QHVAccentColor(),
                     danger ? VDangerBackground() : VTile());
}
static UIView *VBadge(NSString *text, UIColor *foreground, UIColor *background) {
    UIStackView *badge = VStack();
    // Fill binds the background to the label's natural width plus margins.
    // Soft hugging permits long localized values to wrap instead of adding a
    // required badge-width equality that can destabilize live category reflow.
    badge.alignment = UIStackViewAlignmentFill;
    badge.layoutMarginsRelativeArrangement = YES;
    badge.layoutMargins = UIEdgeInsetsMake(4, 9, 4, 9);
    badge.layer.cornerRadius = 10;
    badge.backgroundColor = background;
    UILabel *label = VTypeLabel(text, UIFontTextStyleCaption1, 12, UIFontWeightMedium, YES);
    label.textColor = foreground;
    label.textAlignment = NSTextAlignmentCenter;
    [label setContentHuggingPriority:UILayoutPriorityDefaultHigh + 1 forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 1 forAxis:UILayoutConstraintAxisHorizontal];
    [badge addArrangedSubview:label];
    [badge setContentHuggingPriority:UILayoutPriorityDefaultHigh + 1 forAxis:UILayoutConstraintAxisHorizontal];
    [badge setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 1 forAxis:UILayoutConstraintAxisHorizontal];
    return badge;
}
UIView *QHVBadge(NSString *text, BOOL positive) {
    return VBadge(text, positive ? VGood() : QHVSecondaryTextColor(),
                   positive ? VGoodBackground() : QHVInnerColor());
}
static void VNativeSwitchSize(UISwitch *toggle) {
    [toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [toggle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [toggle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
}
UIView *QHVBrandHeader(NSString *title, NSString *state, BOOL positive, NSString *subtitle) {
    /* A trailing pill kept being stretched by the flexible stack, and its inset
     * fill was invisible on the light page. A plain tagline is legible in both
     * appearances and has no intrinsic-size arbitration to get wrong. */
    (void)positive;
    UIStackView *text = VStack();
    text.spacing = 6;
    UILabel *brand = VTypeLabel(title, UIFontTextStyleTitle1, 28, UIFontWeightBold, NO);
    brand.textColor = QHVAccentColor();
    brand.accessibilityTraits |= UIAccessibilityTraitHeader;
    [text addArrangedSubview:brand];
    NSString *tagline = subtitle.length && state.length
        ? [NSString stringWithFormat:@"%@ · %@", subtitle, state]
        : (subtitle.length ? subtitle : state);
    if (tagline.length) [text addArrangedSubview:VTypeLabel(tagline, UIFontTextStyleSubheadline, 14, UIFontWeightRegular, YES)];
    [text.widthAnchor constraintLessThanOrEqualToConstant:680].active = YES;
    return text;
}
UIStackView *QHVStatusCard(NSString *title, NSString *state, NSString *detail,
                         NSString *countTitle, NSString *countValue, UISwitch *toggle,
                         BOOL active, BOOL attention) {
    QHVSurfaceStack *card = (QHVSurfaceStack *)QHVCard();
    card.surfaceStyle = QHVSurfaceStyleHero;
    card.accessibilityIdentifier = @"qh.managed.card";
    QHVFlexibleStack *header = VFlow(280);
    // Status stays in the brand accent; simplicity, not a new hue, is the goal.
    UIColor *tint = attention ? VAttention() : (active ? QHVAccentColor() : QHVSecondaryTextColor());
    UIColor *tile = attention ? VAttentionBackground() : (active ? VTile() : QHVInnerColor());
    [header addArrangedSubview:VIconTile(attention ? @"exclamationmark.shield"
                                                  : (active ? @"checkmark.shield" : @"shield"), YES, tint, tile)];
    UIStackView *text = VStack();
    text.spacing = 4;
    // Status chip rides beside the state at normal sizes and drops to its own
    // line under accessibility text, where a fixed row would squeeze the title.
    QHVFlexibleStack *titleRow = VFlow(160);
    titleRow.alignment = UIStackViewAlignmentCenter;
    titleRow.spacing = 8;
    UILabel *heading = VTypeLabel(title, UIFontTextStyleTitle3, 18, UIFontWeightSemibold, NO);
    heading.accessibilityTraits |= UIAccessibilityTraitHeader;
    [heading setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                             forAxis:UILayoutConstraintAxisHorizontal];
    [titleRow addArrangedSubview:heading];
    if (state.length) {
        UIView *badge = attention ? VBadge(state, VAttention(), VAttentionBackground())
                                  : VBadge(state, active ? QHVAccentColor() : QHVSecondaryTextColor(),
                                           active ? VTile() : QHVInnerColor());
        [titleRow addArrangedSubview:badge];
        UIView *spacer = [UIView new];
        [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [titleRow addArrangedSubview:spacer];
    }
    [text addArrangedSubview:titleRow];
    if (countValue != nil) {
        /* Compact inline count instead of a full two-column form row. */
        UILabel *count = VTypeLabel([NSString stringWithFormat:@"%@ · %@", countTitle, countValue],
                                    UIFontTextStyleFootnote, 13, UIFontWeightRegular, YES);
        count.accessibilityIdentifier = @"qh.managed.count";
        count.accessibilityLabel = countTitle;
        count.accessibilityValue = countValue;
        count.isAccessibilityElement = YES;
        [text addArrangedSubview:count];
    }
    [header addArrangedSubview:text];
    [text.widthAnchor constraintLessThanOrEqualToAnchor:header.widthAnchor].active = YES;
    if (toggle) {
        // Never assign on/enabled/accessibility state here. The controller owns
        // confirmed file state and consent; this is the original native control.
        toggle.onTintColor = QHVAccentColor();
        VNativeSwitchSize(toggle);
        [header addArrangedSubview:toggle];
    }
    [card addArrangedSubview:header];
    if (detail.length) {
        [card addArrangedSubview:VTypeLabel(detail, UIFontTextStyleFootnote, 12, UIFontWeightRegular, YES)];
    }
    return card;
}
static QHVFlexibleStack *VInfo(NSString *title, NSString *subtitle, NSString *symbol, UIView *trailing, BOOL danger) {
    QHVFlexibleStack *row = VFlow(250);
    [row addArrangedSubview:QHVIconTile(symbol, NO, danger)];
    UIStackView *text = VStack();
    text.spacing = 3;
    UILabel *heading = VTypeLabel(title, UIFontTextStyleBody, 16, UIFontWeightSemibold, NO);
    if (danger) heading.textColor = QHVDestructiveColor();
    if ([symbol isEqual:@"plus"]) heading.textColor = QHVAccentColor();
    [text addArrangedSubview:heading];
    if (subtitle.length) [text addArrangedSubview:VTypeLabel(subtitle, UIFontTextStyleFootnote, 13, UIFontWeightRegular, YES)];
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [row addArrangedSubview:text];
    [text.widthAnchor constraintLessThanOrEqualToAnchor:row.widthAnchor].active = YES;
    if (trailing) {
        if ([trailing isKindOfClass:UISwitch.class]) {
            VNativeSwitchSize((UISwitch *)trailing);
        } else {
            [trailing setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
            [trailing setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
        }
        [row addArrangedSubview:trailing];
    }
    return row;
}
UIView *QHVInfo(NSString *title, NSString *subtitle, NSString *symbol, UIView *trailing) {
    return VInfo(title, subtitle, symbol, trailing, NO);
}
@interface QHVActionRow : UIControl
@end
@implementation QHVActionRow
- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1.0 : 0.55;
    if (enabled) self.accessibilityTraits &= ~UIAccessibilityTraitNotEnabled;
    else self.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted && self.enabled ? QHVInnerColor() : UIColor.clearColor;
}
- (BOOL)accessibilityActivate {
    if (!self.enabled || !(self.allControlEvents & UIControlEventTouchUpInside)) return NO;
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
    return YES;
}
@end
static UIControl *VActionRow(NSString *title, NSString *subtitle, NSString *symbol, NSString *value,
                            BOOL danger, BOOL enabled, void (^action)(void), BOOL disclosure) {
    QHVActionRow *control = [QHVActionRow new];
    control.enabled = enabled;
    control.layer.cornerRadius = 12;
    control.isAccessibilityElement = YES;
    // Descriptive content belongs to the label, not an optional VoiceOver hint.
    control.accessibilityLabel = subtitle.length
        ? [NSString stringWithFormat:@"%@ · %@", title, subtitle]
        : title;
    control.accessibilityValue = value;
    control.accessibilityTraits = action ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    if (!enabled) control.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
    UIStackView *trailing = [UIStackView new];
    trailing.axis = UILayoutConstraintAxisHorizontal;
    trailing.alignment = UIStackViewAlignmentCenter;
    trailing.spacing = 7;
    if (value.length) [trailing addArrangedSubview:QHVBadge(value, NO)];
    if (action && disclosure) {
        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        chevron.tintColor = QHVSecondaryTextColor();
        chevron.isAccessibilityElement = NO;
        [chevron.widthAnchor constraintEqualToConstant:10].active = YES;
        [chevron.heightAnchor constraintEqualToConstant:14].active = YES;
        [trailing addArrangedSubview:chevron];
    }
    QHVFlexibleStack *content = VInfo(title, subtitle, symbol, trailing.arrangedSubviews.count ? trailing : nil, danger);
    content.layoutMarginsRelativeArrangement = YES;
    content.layoutMargins = UIEdgeInsetsMake(11, 0, 11, 0);
    // A single accessible control owns the text and capsule. The native switch
    // is used only in QHVInfo/StatusCard and must never live under this hiding.
    content.accessibilityElementsHidden = YES;
    content.userInteractionEnabled = NO;
    VPin(control, content, 0);
    [control.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    if (action) {
        [control addAction:[UIAction actionWithHandler:^(__kindof UIAction *event) {
            (void)event;
            action();
        }] forControlEvents:UIControlEventTouchUpInside];
    }
    return control;
}
UIControl *QHVRow(NSString *title, NSString *subtitle, NSString *symbol, NSString *value,
                  BOOL danger, BOOL enabled, void (^action)(void)) {
    return VActionRow(title, subtitle, symbol, value, danger, enabled, action, YES);
}
UIControl *QHVCommandRow(NSString *title, NSString *subtitle, NSString *symbol, NSString *value,
                         BOOL danger, BOOL enabled, void (^action)(void)) {
    return VActionRow(title, subtitle, symbol, value, danger, enabled, action, NO);
}
static UIView *VStat(NSString *title, NSString *value) {
    QHVSurfaceStack *panel = (QHVSurfaceStack *)QHVCard();
    panel.surfaceStyle = QHVSurfaceStyleInset;
    panel.layer.cornerRadius = 12;
    panel.spacing = 2;
    panel.layoutMargins = UIEdgeInsetsMake(9, 11, 9, 11);
    UILabel *number = VLabel(value, UIFontTextStyleTitle3, NO);
    number.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle3]
        scaledFontForFont:[UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightSemibold]];
    // Keep the number as arrangedSubviews[0] for the existing live-font fixture.
    [panel addArrangedSubview:number];
    [panel addArrangedSubview:VTypeLabel(title, UIFontTextStyleFootnote, 11, UIFontWeightRegular, YES)];
    panel.isAccessibilityElement = YES;
    panel.accessibilityLabel = title;
    panel.accessibilityValue = value;
    return panel;
}
UIView *QHVStats(NSString *firstTitle, NSString *firstValue, NSString *secondTitle, NSString *secondValue) {
    QHVFlexibleStack *grid = VFlow(300);
    grid.equalColumns = YES;
    [grid addArrangedSubview:VStat(firstTitle, firstValue)];
    [grid addArrangedSubview:VStat(secondTitle, secondValue)];
    return grid;
}
UIView *QHVFormRow(NSString *title, NSString *value) {
    QHVFlexibleStack *row = VFlow(260);
    UILabel *name = VTypeLabel(title, UIFontTextStyleSubheadline, 14, UIFontWeightRegular, YES);
    UILabel *number = VTypeLabel(value, UIFontTextStyleBody, 15, UIFontWeightSemibold, NO);
    [name setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [number setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [row addArrangedSubview:name];
    [row addArrangedSubview:number];
    row.isAccessibilityElement = YES;
    row.accessibilityLabel = title;
    row.accessibilityValue = value;
    return row;
}
UIView *QHVNote(NSString *text, NSString *symbol) {
    QHVSurfaceStack *card = (QHVSurfaceStack *)QHVCard();
    card.surfaceStyle = QHVSurfaceStyleInset;
    card.layer.cornerRadius = 14;
    card.layoutMargins = UIEdgeInsetsMake(12, 12, 12, 12);
    QHVFlexibleStack *line = VFlow(250);
    [line addArrangedSubview:QHVIconTile(symbol, NO, NO)];
    [line addArrangedSubview:VTypeLabel(text, UIFontTextStyleFootnote, 13, UIFontWeightRegular, YES)];
    [card addArrangedSubview:line];
    return card;
}
UILabel *QHVSection(NSString *title) {
    UILabel *heading = VTypeLabel(title, UIFontTextStyleFootnote, 13, UIFontWeightMedium, YES);
    heading.accessibilityTraits |= UIAccessibilityTraitHeader;
    return heading;
}
UIView *QHVSeparator(void) {
    UIView *line = [UIView new];
    line.backgroundColor = QHVLineColor();
    [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    line.isAccessibilityElement = NO;
    return line;
}
