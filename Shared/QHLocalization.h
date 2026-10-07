#ifndef QH_LOCALIZATION_H
#define QH_LOCALIZATION_H
#import <Foundation/Foundation.h>
static inline NSString *QHL(NSString *key) {
    return [NSBundle.mainBundle localizedStringForKey:key value:key table:@"Localizable"];
}
#endif
