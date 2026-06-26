#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <substrate.h>
#import "MediaManager.h"

// 自定义穿透Window
@interface VCamOverlayWindow : UIWindow
@property (nonatomic, assign) BOOL isShowingAlert; // 标记是否正在弹出弹窗
@end
@implementation VCamOverlayWindow
- (BOOL)isPointHitButtonArea:(CGPoint)point {
    if (!self.rootViewController) return NO;
    UIView *rootV = self.rootViewController.view;
    for (UIView *sub in rootV.subviews) {
        CGRect winRect = [sub convertRect:sub.bounds toView:self];
        if (CGRectContainsPoint(winRect, point)) {
            return YES;
        }
    }
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // 如果正在弹出Alert，不做穿透拦截，正常接收所有触摸
    if (self.isShowingAlert) {
        return [super hitTest:point withEvent:event];
    }
    // 无弹窗状态：仅按钮区域响应，其余透传
    if (![self isPointHitButtonArea:point]) {
        return nil;
    }
    return [super hitTest:point withEvent:event];
}
@end

// 根视图兜底穿透
@interface VCamRootView : UIView
@end
@implementation VCamRootView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.subviews) {
        CGPoint innerP = [self convertPoint:point toView:sub];
        if ([sub pointInside:innerP withEvent:event]) {
            return sub;
        }
    }
    return nil;
}
@end

// ============================================================================
// MARK: - 全局状态
// ============================================================================
static BOOL g_vcamEnabled = NO;
static VCamOverlayWindow *g_overlayWindow = nil; // 改为自定义窗口类型
static UIButton *g_floatButton = nil;

// ============================================================================
// MARK: - 悬浮按钮 UI
// ============================================================================
@interface VCamFloatButton : UIButton
@property (nonatomic, assign) CGPoint initialCenter;
@end
@implementation VCamFloatButton
@end

static void setupFloatButton(void);
static void handlePanGesture(UIPanGestureRecognizer *gesture);
static void handleTapGesture(UITapGestureRecognizer *gesture);

static void setupFloatButton() {
    if (g_floatButton) return;
    
    CGFloat btnSize = 50;
    CGRect screen = [UIScreen mainScreen].bounds;
    
    g_floatButton = [VCamFloatButton buttonWithType:UIButtonTypeSystem];
    g_floatButton.frame = CGRectMake(screen.size.width - btnSize - 15, 100, btnSize, btnSize);
    g_floatButton.layer.cornerRadius = btnSize / 2.0;
    g_floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
    g_floatButton.layer.shadowOffset = CGSizeMake(0, 2);
    g_floatButton.layer.shadowOpacity = 0.3;
    g_floatButton.layer.shadowRadius = 4;
    g_floatButton.backgroundColor = g_vcamEnabled 
        ? [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9]
        : [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:0.9];
    
    [g_floatButton setTitle:@"📷" forState:UIControlStateNormal];
    g_floatButton.titleLabel.font = [UIFont systemFontOfSize:24];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] 
        initWithTarget:g_floatButton action:@selector(handlePan:)];
    [g_floatButton addGestureRecognizer:pan];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] 
        initWithTarget:g_floatButton action:@selector(handleTap:)];
    [g_floatButton addGestureRecognizer:tap];
    
    // 使用自定义穿透窗口
    g_overlayWindow = [[VCamOverlayWindow alloc] initWithFrame:screen];
    // 默认低层级，空白区域透传
    g_overlayWindow.windowLevel = UIWindowLevelStatusBar - 1;
    g_overlayWindow.isShowingAlert = NO;
    g_overlayWindow.hidden = NO;
    g_overlayWindow.backgroundColor = [UIColor clearColor];
    
    VCamRootView *rootView = [[VCamRootView alloc] initWithFrame:g_overlayWindow.bounds];
    rootView.backgroundColor = [UIColor clearColor];
    // 移除 userInteractionEnabled=NO，改用hitTest精准控制
    [rootView addSubview:g_floatButton];
    
    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view = rootView;
    g_overlayWindow.rootViewController = rootVC;
    
    class_addMethod([g_floatButton class], @selector(handlePan:), 
                    (IMP)handlePanGesture, "v@:@");
    class_addMethod([g_floatButton class], @selector(handleTap:), 
                    (IMP)handleTapGesture, "v@:@");
}

static void handlePanGesture(UIPanGestureRecognizer *gesture) {
    UIView *btn = gesture.view;
    CGPoint translation = [gesture translationInView:btn.superview];
    btn.center = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:btn.superview];
    
    if (gesture.state == UIGestureRecognizerStateEnded) {
        CGRect screen = [UIScreen mainScreen].bounds;
        CGFloat x = btn.center.x < screen.size.width / 2 ? 35 : screen.size.width - 35;
        [UIView animateWithDuration:0.2 animations:^{
            btn.center = CGPointMake(x, btn.center.y);
        }];
    }
}

static UIViewController *findTopViewController(void) {
    UIViewController *topVC = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *w in scene.windows) {
                if (w.isKeyWindow) {
                    topVC = w.rootViewController;
                    break;
                }
            }
        }
    }
    while (topVC && topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

@interface VCamImagePickerControllerDelegate : NSObject <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@end

@implementation VCamImagePickerControllerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker 
        didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    NSURL *url = info[UIImagePickerControllerMediaURL];
    if (!url) return;
    
    NSURL *tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() 
        stringByAppendingPathComponent:@"vcam_input.mp4"]];
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    [[NSFileManager defaultManager] copyItemAtURL:url toURL:tempURL error:nil];
    
    [[MediaManager sharedManager] loadMediaFromURL:tempURL];
    g_vcamEnabled = YES;
    [[MediaManager sharedManager] start];
    if (g_floatButton) {
        g_floatButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9];
    }
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
@end

static VCamImagePickerControllerDelegate *g_pickerDelegate = nil;

static void handleTapGesture(UITapGestureRecognizer *gesture) {
    UIViewController *topVC = findTopViewController();
    if (!topVC) return;
    
    // ========== 弹窗前：提升窗口层级，关闭穿透逻辑 ==========
    g_overlayWindow.isShowingAlert = YES;
    g_overlayWindow.windowLevel = UIWindowLevelAlert + 1;
    
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"VCam" 
        message:g_vcamEnabled ? @"虚拟相机已启用" : @"虚拟相机已关闭"
        preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"选择视频" 
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]) {
            return;
        }
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
        picker.mediaTypes = @[@"public.movie"];
        picker.delegate = g_pickerDelegate;
        [topVC presentViewController:picker animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:g_vcamEnabled ? @"关闭虚拟相机" : @"开启虚拟相机" 
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        g_vcamEnabled = !g_vcamEnabled;
        if (g_floatButton) {
            g_floatButton.backgroundColor = g_vcamEnabled 
                ? [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9]
                : [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:0.9];
        }
        if (g_vcamEnabled) {
            [[MediaManager sharedManager] start];
        } else {
            [[MediaManager sharedManager] stop];
        }
    }]];
    
    // 取消按钮清空复位代码
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = gesture.view;
        alert.popoverPresentationController.sourceRect = gesture.view.bounds;
    }
    
    // 弹窗完全关闭后统一恢复穿透，所有关闭方式都会触发
    [topVC presentViewController:alert animated:YES completion:^{
        g_overlayWindow.isShowingAlert = NO;
        g_overlayWindow.windowLevel = UIWindowLevelStatusBar - 1;
    }];
}

// ============================================================================
// MARK: - Hook AVCapture 原版完全保留
// ============================================================================
%group VCamHooks

%hook AVCaptureSession
- (void)startRunning { %orig; }
- (void)stopRunning { %orig; }
%end

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate 
                          queue:(dispatch_queue_t)queue {
    %orig;
}
%end

%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output 
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer 
           fromConnection:(AVCaptureConnection *)connection {
    
    if (g_vcamEnabled && [[MediaManager sharedManager] isRunning]) {
        CMSampleBufferRef fakeFrame = [[MediaManager sharedManager] nextVideoFrame];
        if (fakeFrame) {
            %orig(output, fakeFrame, connection);
            CFRelease(fakeFrame);
            return;
        }
    }
    %orig;
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings 
                        delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    %orig;
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)setSession:(AVCaptureSession *)session {
    %orig;
}
%end

%end // VCamHooks group

// ============================================================================
// MARK: - 构造函数
// ============================================================================

%ctor {
    @autoreleasepool {
        g_pickerDelegate = [[VCamImagePickerControllerDelegate alloc] init];
        
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.apple.springboard"]) {
            %init(VCamHooks);
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), 
            dispatch_get_main_queue(), ^{
                @autoreleasepool {
                    setupFloatButton();
                }
            });
    }
}
