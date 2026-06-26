#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <substrate.h>
#import "MediaManager.h"

#pragma mark - 全局保存所有App原始相机代理（改用数组防止覆盖）
static NSMutableArray* g_allVideoDelegates = nil;

#pragma mark - 自定义顶层悬浮窗口类（触摸穿透逻辑不变）
@interface VCamOverlayWindow : UIWindow
@property (nonatomic, assign) BOOL isShowingAlert;
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
    if (self.isShowingAlert) {
        return [super hitTest:point withEvent:event];
    }
    if (![self isPointHitButtonArea:point]) {
        return nil;
    }
    return [super hitTest:point withEvent:event];
}
@end

#pragma mark - 悬浮窗口根视图兜底穿透
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

#pragma mark - 全局静态状态
static BOOL g_vcamEnabled = NO;
static VCamOverlayWindow *g_overlayWindow = nil;
static UIButton *g_floatButton = nil;

#pragma mark - 悬浮按钮自定义类
@interface VCamFloatButton : UIButton
@property (nonatomic, assign) CGPoint initialCenter;
@end
@implementation VCamFloatButton
@end

#pragma mark - 前置函数声明
static void setupFloatButton(void);
static void handlePanGesture(UIPanGestureRecognizer *gesture);
static void handleTapGesture(UITapGestureRecognizer *gesture);

#pragma mark - 创建悬浮窗口与按钮
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

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:g_floatButton action:@selector(handlePan:)];
    [g_floatButton addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:g_floatButton action:@selector(handleTap:)];
    [g_floatButton addGestureRecognizer:tap];

    g_overlayWindow = [[VCamOverlayWindow alloc] initWithFrame:screen];
    g_overlayWindow.windowLevel = UIWindowLevelStatusBar - 1;
    g_overlayWindow.isShowingAlert = NO;
    g_overlayWindow.hidden = NO;
    g_overlayWindow.backgroundColor = [UIColor clearColor];

    VCamRootView *rootView = [[VCamRootView alloc] initWithFrame:g_overlayWindow.bounds];
    rootView.backgroundColor = [UIColor clearColor];
    [rootView addSubview:g_floatButton];
    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view = rootView;
    g_overlayWindow.rootViewController = rootVC;

    class_addMethod([g_floatButton class], @selector(handlePan:), (IMP)handlePanGesture, "v@:@");
    class_addMethod([g_floatButton class], @selector(handleTap:), (IMP)handleTapGesture, "v@:@");
}

#pragma mark - 拖拽吸附逻辑
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

#pragma mark - 获取顶层控制器
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

#pragma mark - 相册视频选择代理（修复解码延迟+沙盒权限提示）
@interface VCamImagePickerControllerDelegate : NSObject <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@end
@implementation VCamImagePickerControllerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSURL *srcUrl = info[UIImagePickerControllerMediaURL];
    if (!srcUrl) {
        NSLog(@"[VCam] 未选中视频");
        return;
    }
    // 不拷贝临时文件，直接使用相册原始URL，规避无根沙盒读不到文件
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        BOOL loadOk = [[MediaManager sharedManager] loadMediaFromURL:srcUrl];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (loadOk) {
                g_vcamEnabled = YES;
                [[MediaManager sharedManager] start];
                if (g_floatButton) g_floatButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9];
                NSLog(@"[VCam] 视频加载成功，虚拟相机开启");
            } else {
                NSLog(@"[VCam] MediaManager加载视频失败，检查视频格式(MP4 YUV420)");
            }
        });
    });
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
@end
static VCamImagePickerControllerDelegate *g_pickerDelegate = nil;

#pragma mark - 悬浮按钮点击弹出菜单
static void handleTapGesture(UITapGestureRecognizer *gesture) {
    UIViewController *topVC = findTopViewController();
    if (!topVC) return;
    g_overlayWindow.isShowingAlert = YES;
    g_overlayWindow.windowLevel = UIWindowLevelAlert + 1;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"VCam" message:g_vcamEnabled ? @"虚拟相机已启用" : @"虚拟相机已关闭" preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"选择视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]) return;
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
        picker.mediaTypes = @[@"public.movie"];
        picker.delegate = g_pickerDelegate;
        [topVC presentViewController:picker animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:g_vcamEnabled ? @"关闭虚拟相机" : @"开启虚拟相机" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        g_vcamEnabled = !g_vcamEnabled;
        if (g_floatButton) g_floatButton.backgroundColor = g_vcamEnabled ? [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9] : [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:0.9];
        if (g_vcamEnabled) [[MediaManager sharedManager] start];
        else [[MediaManager sharedManager] stop];
        NSLog(@"[VCam] 虚拟相机开关切换：%d", g_vcamEnabled);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        g_overlayWindow.isShowingAlert = NO;
        g_overlayWindow.windowLevel = UIWindowLevelStatusBar - 1;
    }]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = gesture.view;
        alert.popoverPresentationController.sourceRect = gesture.view.bounds;
    }
    [topVC presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Theos Hook分组（修复代理覆盖、帧推送逻辑）
%group VCamHooks

// 1、捕获所有AVCaptureVideoDataOutput代理，存入数组防止覆盖
%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate queue:(dispatch_queue_t)queue {
    %orig;
    if (!g_allVideoDelegates) g_allVideoDelegates = [NSMutableArray array];
    if (delegate && ![g_allVideoDelegates containsObject:delegate]) {
        [g_allVideoDelegates addObject:delegate];
        NSLog(@"[VCam] 新增相机代理 %@", delegate);
    }
}
%end

// 2、修复核心：先执行原生%orig，再批量推送假帧（解决预览层依旧真实画面）
%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // 先执行原生逻辑，拿到底层渲染通道
    %orig;

    if (!g_vcamEnabled || ![[MediaManager sharedManager] isRunning]) return;
    CMSampleBufferRef fakeFrame = [[MediaManager sharedManager] nextVideoFrame];
    if (!fakeFrame) {
        NSLog(@"[VCam] 无可用视频帧");
        return;
    }
    // 遍历全部缓存代理，统一推送假帧，覆盖多层渲染
    for (id del in g_allVideoDelegates) {
        if ([del respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            [del captureOutput:output didOutputSampleBuffer:fakeFrame fromConnection:connection];
        }
    }
    NSLog(@"[VCam] 成功推送虚拟帧");
}
%end

%hook AVCaptureSession
- (void)startRunning { %orig; }
- (void)stopRunning { %orig; }
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate { %orig; }
%end

%hook AVCaptureVideoPreviewLayer
- (void)setSession:(AVCaptureSession *)session { %orig; }
%end

%end

#pragma mark - Tweak入口
%ctor {
    @autoreleasepool {
        g_pickerDelegate = [[VCamImagePickerControllerDelegate alloc] init];
        g_allVideoDelegates = nil;
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSLog(@"[VCam] 系统版本：%@ 进程：%@", [[UIDevice currentDevice] systemVersion], bundleID);
        if (![bundleID isEqualToString:@"com.apple.springboard"]) {
            %init(VCamHooks);
            NSLog(@"[VCam] 相机Hook加载完成");
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @autoreleasepool {
                setupFloatButton();
            }
        });
    }
}
