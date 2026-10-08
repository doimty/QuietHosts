#import <UIKit/UIKit.h>

UIStackView *QHVCard(void);
UIView *QHVIconTile(NSString *symbol, BOOL large, BOOL danger);
UIView *QHVBadge(NSString *text, BOOL positive);
UIView *QHVBrandHeader(NSString *title, NSString *state, BOOL positive, NSString *subtitle);
UIView *QHVInfo(NSString *title, NSString *subtitle, NSString *symbol, UIView *trailing);
UIControl *QHVRow(NSString *title, NSString *subtitle, NSString *symbol, NSString *value, BOOL danger, BOOL enabled, void (^action)(void));
UIView *QHVStats(NSString *firstTitle, NSString *firstValue, NSString *secondTitle, NSString *secondValue);
UIView *QHVFormRow(NSString *title, NSString *value);
UIView *QHVNote(NSString *text, NSString *symbol);
UILabel *QHVSection(NSString *title);
UIView *QHVSeparator(void);
