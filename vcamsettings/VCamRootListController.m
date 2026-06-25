#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>

@interface VCamRootListController : PSListController
@end

@implementation VCamRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)respring {
    notify_post("com.apple.uikit.respring");
}

- (void)selectVideo {
    // Open PHPicker from settings
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"选择视频" 
        message:@"请在任意 App 中点击悬浮按钮选择视频"
        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
