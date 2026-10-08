#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@class QHDialogAction;
typedef void (^QHDialogHandler)(QHDialogAction *action);
// Public, project-owned sheet API. UIKit action styles retain their meaning.
@interface QHDialogAction : NSObject
@property(nonatomic,readonly,copy) NSString *title;
@property(nonatomic,readonly) UIAlertActionStyle style;
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(nullable QHDialogHandler)handler;
@end
@interface QHDialogController : UINavigationController
@property(nonatomic,readonly,copy) NSArray<UITextField *> *textFields;
@property(nonatomic,readonly,copy) NSArray<QHDialogAction *> *actions;
+ (instancetype)dialogControllerWithTitle:(NSString *)title message:(nullable NSString *)message preferredStyle:(UIAlertControllerStyle)style;
- (void)addAction:(QHDialogAction *)action;
- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *field))configuration;
@end
// Shared chrome for confirmation sheets, previews and text editor navigation.
FOUNDATION_EXPORT void QHConfigureModal(UIViewController *controller);
NS_ASSUME_NONNULL_END
