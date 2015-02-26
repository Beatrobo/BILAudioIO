#import "BILAudio.h"


@class BILAudioOutput;


@protocol BILAudioOutputDataSource <NSObject>
@optional
- (void)    audioOutput:(BILAudioOutput*)audioOutput
callbackWithActionFlags:(AudioUnitRenderActionFlags*)ioActionFlags
            inTimeStamp:(const AudioTimeStamp*)inTimeStamp
            inBusNumber:(UInt32)inBusNumber
         inNumberFrames:(UInt32)inNumberFrames
                 ioData:(AudioBufferList*)ioData;
@end


@interface BILAudioOutput : NSObject

@property (nonatomic, weak) id<BILAudioOutputDataSource> dataSource;
- (instancetype)initWithDataSource:(id<BILAudioOutputDataSource>)dataSource;

@property (nonatomic) AudioStreamBasicDescription audioStreamBasicDescription;

@property (nonatomic, readonly, getter=isPlaying) BOOL playing;
- (void)startPlayback;
- (void)stopPlayback;

@end
