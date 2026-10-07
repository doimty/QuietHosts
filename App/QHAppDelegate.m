#import "QHAppDelegate.h"
#import "QHAppController.h"
@implementation QHAppDelegate {
    QHAppController *_controller;
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;
    (void)options;
    _controller = [QHAppController new];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = _controller.rootController;
    [_controller applyThemeToWindow:self.window];
    // Hold the initial local-load transaction before viewDidAppear can query.
    [_controller start];
    [self.window makeKeyAndVisible];
    return YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    [_controller refreshStatus];
}
@end
