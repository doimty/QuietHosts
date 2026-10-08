#import "QHVisualComponents.h"

static UIColor *VColor(unsigned light, unsigned dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        unsigned rgb = traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
        return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                               green:((rgb >> 8) & 255) / 255.0
                                blue:(rgb & 255) / 255.0 alpha:1];
    }];
}
static UIColor *VCard(void) { return VColor(0xffffff, 0x1d1d26); }
static UIColor *VInner(void) { return VColor(0xfaf9fe, 0x242430); }
static UIColor *VTile(void) { return VColor(0xedebfa, 0x2b2944); }
static UIColor *VAccent(void) { return VColor(0x5b54e8, 0x9b95ff); }
static UIColor *VText(void) { return VColor(0x1b1b22, 0xf0eff8); }
static UIColor *VSecondary(void) { return VColor(0x686875, 0x9e9ea8); }
static UIColor *VLine(void) { return VColor(0xecebf4, 0x2c2c38); }
static UIColor *VDanger(void) { return VColor(0xb42336, 0xff8995); }
static UIColor *VDangerBackground(void) { return VColor(0xfff0f2, 0x3c232b); }
static UIColor *VGood(void) { return VColor(0x1b7352, 0x8cddb7); }
static UIColor *VGoodBackground(void) { return VColor(0xe3f2ea, 0x203c32); }

static UILabel *VLabel(NSString *text, UIFontTextStyle style, BOOL secondary) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    label.textColor = secondary ? VSecondary() : VText();
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh
                                          forAxis:UILayoutConstraintAxisVertical];
    return label;
}
static UIStackView *VStack(void) {
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    return stack;
}

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
    [self updateFlow];
    [super layoutSubviews];
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
    stack.spacing = 12;
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
    UIStackView *card = VStack();
    card.spacing = 10;
    card.backgroundColor = VCard();
    card.layer.cornerRadius = 22;
    card.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
    card.layoutMarginsRelativeArrangement = YES;
    return card;
}
UIView *QHVIconTile(NSString *symbol, BOOL large, BOOL danger) {
    UIView *tile = [UIView new];
    CGFloat side = large ? 58 : 38;
    tile.backgroundColor = danger ? VDangerBackground() : VTile();
    tile.layer.cornerRadius = large ? 29 : 12;
    tile.isAccessibilityElement = NO;
    UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    image.tintColor = danger ? VDanger() : VAccent();
    image.contentMode = UIViewContentModeScaleAspectFit;
    image.isAccessibilityElement = NO;
    image.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:image];
    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:side],
        [tile.heightAnchor constraintEqualToConstant:side],
        [image.widthAnchor constraintEqualToConstant:large ? 28 : 20],
        [image.heightAnchor constraintEqualToConstant:large ? 28 : 20],
        [image.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [image.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor]
    ]];
    return tile;
}
UIView *QHVBadge(NSString *text, BOOL positive) {
    UIStackView *badge = VStack();
    badge.alignment = UIStackViewAlignmentCenter;
    badge.layoutMarginsRelativeArrangement = YES;
    badge.layoutMargins = UIEdgeInsetsMake(4, 10, 4, 10);
    badge.layer.cornerRadius = 14;
    badge.backgroundColor = positive ? VGoodBackground() : VInner();
    UILabel *label = VLabel(text, UIFontTextStyleCaption1, YES);
    label.textColor = positive ? VGood() : VSecondary();
    label.textAlignment = NSTextAlignmentCenter;
    [badge addArrangedSubview:label];
    [badge setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    return badge;
}
UIView *QHVBrandHeader(NSString *title, NSString *state, BOOL positive, NSString *subtitle) {
    UIStackView *card = QHVCard();
    card.layer.cornerRadius = 26;
    card.layoutMargins = UIEdgeInsetsMake(20, 20, 20, 20);
    QHVFlexibleStack *header = VFlow(260);
    UIStackView *text = VStack();
    UILabel *brand = VLabel(title, UIFontTextStyleTitle1, NO);
    brand.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle1]
        scaledFontForFont:[UIFont systemFontOfSize:30 weight:UIFontWeightBold]];
    [text addArrangedSubview:brand];
    QHVFlexibleStack *status = VFlow(180);
    [status addArrangedSubview:QHVBadge(state, positive)];
    [status addArrangedSubview:VLabel(subtitle, UIFontTextStyleSubheadline, YES)];
    [text addArrangedSubview:status];
    [header addArrangedSubview:text];
    [header addArrangedSubview:QHVIconTile(@"shield", YES, NO)];
    [card addArrangedSubview:header];
    return card;
}
static QHVFlexibleStack *VInfo(NSString *title, NSString *subtitle, NSString *symbol, UIView *trailing, BOOL danger) {
    QHVFlexibleStack *row = VFlow(280);
    [row addArrangedSubview:QHVIconTile(symbol, NO, danger)];
    UIStackView *text = VStack();
    UILabel *heading = VLabel(title, UIFontTextStyleHeadline, NO);
    if (danger) heading.textColor = VDanger();
    if ([symbol isEqual:@"plus"]) heading.textColor = VAccent();
    [text addArrangedSubview:heading];
    if (subtitle.length) [text addArrangedSubview:VLabel(subtitle, UIFontTextStyleFootnote, YES)];
    [row addArrangedSubview:text];
    if (trailing) [row addArrangedSubview:trailing];
    return row;
}
UIView *QHVInfo(NSString *title, NSString *subtitle, NSString *symbol, UIView *trailing) {
    return VInfo(title, subtitle, symbol, trailing, NO);
}
@interface QHVActionRow : UIControl
@end
@implementation QHVActionRow
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? VInner() : UIColor.clearColor;
}
@end
UIControl *QHVRow(NSString *title, NSString *subtitle, NSString *symbol, NSString *value,
                  BOOL danger, BOOL enabled, void (^action)(void)) {
    QHVActionRow *control = [QHVActionRow new];
    control.enabled = enabled;
    control.layer.cornerRadius = 12;
    control.isAccessibilityElement = YES;
    control.accessibilityLabel = title;
    control.accessibilityHint = subtitle;
    control.accessibilityValue = value;
    control.accessibilityTraits = action ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    if (!enabled) control.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
    UIStackView *trailing = [UIStackView new];
    trailing.axis = UILayoutConstraintAxisHorizontal;
    trailing.alignment = UIStackViewAlignmentCenter;
    trailing.spacing = 6;
    if (value.length) [trailing addArrangedSubview:QHVBadge(value, NO)];
    if (action) {
        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        chevron.tintColor = VSecondary();
        chevron.isAccessibilityElement = NO;
        [chevron.widthAnchor constraintEqualToConstant:12].active = YES;
        [chevron.heightAnchor constraintEqualToConstant:16].active = YES;
        [trailing addArrangedSubview:chevron];
    }
    QHVFlexibleStack *content = VInfo(title, subtitle, symbol, trailing.arrangedSubviews.count ? trailing : nil, danger);
    content.layoutMarginsRelativeArrangement = YES;
    content.layoutMargins = UIEdgeInsetsMake(8, 0, 8, 0);
    // A single accessible control owns this row, including its value capsule.
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
static UIView *VStat(NSString *title, NSString *value) {
    UIStackView *panel = VStack();
    panel.backgroundColor = VInner();
    panel.layer.cornerRadius = 16;
    panel.layoutMarginsRelativeArrangement = YES;
    panel.layoutMargins = UIEdgeInsetsMake(14, 14, 14, 14);
    UILabel *number = VLabel(value, UIFontTextStyleTitle2, NO);
    UIFont *base = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    number.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle2] scaledFontForFont:base];
    [panel addArrangedSubview:number];
    [panel addArrangedSubview:VLabel(title, UIFontTextStyleFootnote, YES)];
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
    QHVFlexibleStack *row = VFlow(300);
    UILabel *name = VLabel(title, UIFontTextStyleSubheadline, YES);
    UILabel *number = VLabel(value, UIFontTextStyleHeadline, NO);
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
    UIStackView *card = QHVCard();
    card.backgroundColor = VInner();
    card.layer.cornerRadius = 16;
    QHVFlexibleStack *line = VFlow(260);
    [line addArrangedSubview:QHVIconTile(symbol, NO, NO)];
    [line addArrangedSubview:VLabel(text, UIFontTextStyleFootnote, YES)];
    [card addArrangedSubview:line];
    return card;
}
UILabel *QHVSection(NSString *title) {
    UILabel *heading = VLabel(title, UIFontTextStyleFootnote, YES);
    heading.accessibilityTraits |= UIAccessibilityTraitHeader;
    return heading;
}
UIView *QHVSeparator(void) {
    UIView *line = [UIView new];
    line.backgroundColor = VLine();
    [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    line.isAccessibilityElement = NO;
    return line;
}
