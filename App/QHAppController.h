#import <UIKit/UIKit.h>
@interface QHAppController : NSObject
@property(nonatomic, readonly, strong) UITabBarController *rootController;
- (void)start;
- (void)refreshStatus;
- (void)applyThemeToWindow:(UIWindow *)window;
@end
