#import "MediaManager.h"
#import <CoreImage/CoreImage.h>

@interface MediaManager ()
@property (nonatomic, strong) dispatch_queue_t decodeQueue;
@property (nonatomic, assign) CMTime startTime;
@property (nonatomic, assign) int64_t frameIndex;
@end

@implementation MediaManager

+ (instancetype)sharedManager {
    static MediaManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MediaManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mode = VCamModeBlack;
        _loopPlayback = YES;
        _isRunning = NO;
        _videoSize = CGSizeMake(1920, 1080);
        _decodeQueue = dispatch_queue_create("com.vcam.decode", DISPATCH_QUEUE_SERIAL);
        _startTime = kCMTimeZero;
        _frameIndex = 0;
    }
    return self;
}

#pragma mark - Media Loading

- (void)loadMediaFromURL:(NSURL *)url {
    dispatch_async(_decodeQueue, ^{
        AVAsset *asset = [AVAsset assetWithURL:url];
        if (!asset) return;
        
        self.currentAsset = asset;
        self.videoDuration = asset.duration;
        
        // Get video dimensions
        NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (tracks.count > 0) {
            AVAssetTrack *track = tracks.firstObject;
            CGSize size = track.naturalSize;
            CGAffineTransform t = track.preferredTransform;
            size = CGSizeApplyAffineTransform(size, t);
            size.width = fabs(size.width);
            size.height = fabs(size.height);
            if (size.width > 0 && size.height > 0) {
                self.videoSize = size;
            }
        }
        
        [self resetReaders];
        self.mode = VCamModeVideo;
    });
}

- (void)resetReaders {
    NSError *error = nil;
    
    // --- Video Reader ---
    if (self.currentAsset) {
        self.videoReader = [AVAssetReader assetReaderWithAsset:self.currentAsset error:&error];
        
        NSArray<AVAssetTrack *> *videoTracks = [self.currentAsset tracksWithMediaType:AVMediaTypeVideo];
        if (videoTracks.count > 0) {
            NSDictionary *settings = @{
                (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            };
            self.videoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTracks.firstObject
                                                                          outputSettings:settings];
            self.videoOutput.alwaysCopiesSampleData = NO;
            [self.videoReader addOutput:self.videoOutput];
        }
        
        [self.videoReader startReading];
    }
    
    // --- Audio Reader ---
    if (self.currentAsset) {
        self.audioReader = [AVAssetReader assetReaderWithAsset:self.currentAsset error:&error];
        
        NSArray<AVAssetTrack *> *audioTracks = [self.currentAsset tracksWithMediaType:AVMediaTypeAudio];
        if (audioTracks.count > 0) {
            NSDictionary *settings = @{
                AVFormatIDKey: @(kAudioFormatLinearPCM),
                AVSampleRateKey: @(44100),
                AVNumberOfChannelsKey: @(1),
                AVLinearPCMBitDepthKey: @(16),
                AVLinearPCMIsFloatKey: @(NO),
                AVLinearPCMIsBigEndianKey: @(NO),
            };
            self.audioOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTracks.firstObject
                                                                          outputSettings:settings];
            self.audioOutput.alwaysCopiesSampleData = NO;
            [self.audioReader addOutput:self.audioOutput];
        }
        
        [self.audioReader startReading];
    }
}

#pragma mark - Frame Generation

- (CMSampleBufferRef)nextVideoFrame {
    if (self.mode != VCamModeVideo || !self.videoOutput) {
        CMTime pts = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
        return [self generateBlackFrameWithSize:self.videoSize presentationTime:pts];
    }
    
    CMSampleBufferRef sample = [self.videoOutput copyNextSampleBuffer];
    
    // Handle end-of-stream: loop
    if (!sample) {
        if (self.loopPlayback) {
            [self resetReaders];
            sample = [self.videoOutput copyNextSampleBuffer];
        }
        if (!sample) {
            CMTime pts = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
            return [self generateBlackFrameWithSize:self.videoSize presentationTime:pts];
        }
    }
    
    // Re-timestamp to wall clock so AVCapture consumers see continuous PTS
    CMTime now = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    CMSampleBufferRef retimed = NULL;
    CMSampleBufferRef copy = NULL;
    
    CMSampleBufferCreateCopy(kCFAllocatorDefault, sample, &copy);
    if (copy) {
        CMSampleBufferSetOutputPresentationTimeStamp(copy, now);
        retimed = copy;
    }
    CFRelease(sample);
    
    return retimed;
}

- (CMSampleBufferRef)nextAudioFrame {
    if (!self.audioOutput) return NULL;
    
    CMSampleBufferRef sample = [self.audioOutput copyNextSampleBuffer];
    if (!sample && self.loopPlayback) {
        // Audio reader reset handled separately if needed
        return NULL;
    }
    return sample;
}

#pragma mark - Black Frame

- (CMSampleBufferRef)generateBlackFrameWithSize:(CGSize)size presentationTime:(CMTime)pts {
    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *attrs = @{
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          (size_t)size.width,
                                          (size_t)size.height,
                                          kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                          (__bridge CFDictionaryRef)attrs,
                                          &pixelBuffer);
    if (status != kCVReturnSuccess || !pixelBuffer) return NULL;
    
    // Fill with black (zero all planes)
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    void *yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    size_t yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    size_t yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    memset(yPlane, 16, yBytesPerRow * yHeight);  // Y=16 for black in limited range, 0 for full
    
    void *uvPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    size_t uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    size_t uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
    memset(uvPlane, 128, uvBytesPerRow * uvHeight);  // UV=128 for neutral chroma
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    // Create CMVideoFormatDescription
    CMVideoFormatDescriptionRef formatDesc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);
    
    // Create CMSampleBuffer
    CMSampleBufferRef sampleBuffer = NULL;
    CMSampleTimingInfo timing = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = pts,
        .decodeTimeStamp = pts,
    };
    
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                       pixelBuffer,
                                       YES,
                                       NULL, NULL,
                                       formatDesc,
                                       &timing,
                                       &sampleBuffer);
    
    if (formatDesc) CFRelease(formatDesc);
    CVPixelBufferRelease(pixelBuffer);
    
    return sampleBuffer;
}

#pragma mark - Lifecycle

- (void)start {
    self.isRunning = YES;
    self.startTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
}

- (void)stop {
    self.isRunning = NO;
}

@end
