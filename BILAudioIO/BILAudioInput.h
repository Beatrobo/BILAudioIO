#import "BILAudio.h"


@class BILAudioInput;


@protocol BILAudioInputDelegate <NSObject>
@optional
- (void)audioInput:(BILAudioInput*)audioInput
     hasBufferList:(AudioBufferList*)bufferList
        bufferSize:(UInt32)bufferSize
  numberOfChannels:(UInt32)numberOfChannels;
@end


@interface BILAudioInput : NSObject

@property (nonatomic, weak) id<BILAudioInputDelegate> delegate;
- (instancetype)initWithDelegate:(id<BILAudioInputDelegate>)delegate;

@property (nonatomic) AudioStreamBasicDescription streamFormat;
@property (nonatomic, readonly) UInt32 deviceBufferFrameSize;

@property (nonatomic, readonly, getter=isFetchingAudio) BOOL fetchingAudio;
- (void)startFetchingAudio;
- (void)stopFetchingAudio;

@end
