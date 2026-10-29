#import <UIKit/UIKit.h>

// Shared semantic tokens. Colors remain dynamic in system/light/dark appearance.
UIColor *QHVBackgroundColor(void);
UIColor *QHVCardColor(void);
UIColor *QHVInnerColor(void);
UIColor *QHVAccentColor(void);
UIColor *QHVPrimaryTextColor(void);
UIColor *QHVSecondaryTextColor(void);
UIColor *QHVLineColor(void);
UIColor *QHVDestructiveColor(void);
UIColor *QHVPrimaryForegroundColor(void);

UIStackView *QHVCard(void);
UIView *QHVIconTile(NSString *symbol, BOOL large, BOOL danger);
UIView *QHVBadge(NSString *text, BOOL positive);
UIView *QHVBrandHeader(NSString *title, NSString *state, BOOL positive, NSString *subtitle);
// Display-only: callers own verified state, consent and the native switch action.
// A nil countValue omits the managed-count row; it never becomes a synthetic zero.
UIStackView *QHVStatusCard(NSString *title, NSString *state, NSString *detail,
                         NSString *countTitle, NSString *countValue, UISwitch *toggle,
                         BOOL active, BOOL attention);
UIView *QHVInfo(NSString *title, NSString *subtitle, NSString *symbol, UIView *trailing);
// Navigation/disclosure rows versus immediate commands; neither infers intent
// from a localized title or symbol. Both use the same accessible row builder.
UIControl *QHVRow(NSString *title, NSString *subtitle, NSString *symbol, NSString *value, BOOL danger, BOOL enabled, void (^action)(void));
UIControl *QHVCommandRow(NSString *title, NSString *subtitle, NSString *symbol, NSString *value, BOOL danger, BOOL enabled, void (^action)(void));
UIView *QHVStats(NSString *firstTitle, NSString *firstValue, NSString *secondTitle, NSString *secondValue);
UIView *QHVFormRow(NSString *title, NSString *value);
UIView *QHVNote(NSString *text, NSString *symbol);
UILabel *QHVSection(NSString *title);
UIView *QHVSeparator(void);
