#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

typedef NS_ENUM(NSInteger, VCamMode) {
    VCamModeVideo,
    VCamModePhoto,
    VCamModeBlack,
};

@interface MediaManager : NSObject

@property (nonatomic, assign) VCamMode mode;
@property (nonatomic, strong, nullable) AVAsset *currentAsset;
@property (nonatomic, strong, nullable) AVAssetReader *videoReader;
@property (nonatomic, strong, nullable) AVAssetReader *audioReader;
@property (nonatomic, strong, nullable) AVAssetReaderTrackOutput *videoOutput;
@property (nonatomic, strong, nullable) AVAssetReaderTrackOutput *audioOutput;
@property (nonatomic, assign) CGSize videoSize;
@property (nonatomic, assign) CMTime videoDuration;
@property (nonatomic, assign) BOOL loopPlayback;
@property (nonatomic, assign) BOOL isRunning;

+ (nonnull instancetype)sharedManager;

- (void)loadMediaFromURL:(nonnull NSURL *)url;
- (void)resetReaders;

- (nullable CMSampleBufferRef)nextVideoFrame CF_RETURNS_RETAINED;
- (nullable CMSampleBufferRef)nextAudioFrame CF_RETURNS_RETAINED;
- (nullable CMSampleBufferRef)generateBlackFrameWithSize:(CGSize)size
                                         presentationTime:(CMTime)pts CF_RETURNS_RETAINED;

- (void)start;
- (void)stop;

@end
