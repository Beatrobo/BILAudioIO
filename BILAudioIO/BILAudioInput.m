#import "BILAudioInput.h"


@interface BILAudioInput ()
@property (nonatomic, readonly) AudioUnit        inputUnit;
@property (nonatomic, readonly) AudioBufferList* inputBuffer;
@end


#pragma mark - AudioUnit Callback function


static OSStatus InputCallback(void                       *inRefCon,
                              AudioUnitRenderActionFlags *ioActionFlags,
                              const AudioTimeStamp       *inTimeStamp,
                              UInt32                     inBusNumber,
                              UInt32                     inNumberFrames,
                              AudioBufferList            *ioData )
{
    BILAudioInput* audioInput = (__bridge BILAudioInput*)inRefCon;
    OSStatus       result     = noErr;
    
    result = AudioUnitRender(audioInput.inputUnit,
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             audioInput.inputBuffer);
    if (!result) {
        if([audioInput.delegate respondsToSelector:@selector(audioInput:hasBufferList:bufferSize:numberOfChannels:)]){
            [audioInput.delegate audioInput:audioInput
                              hasBufferList:audioInput.inputBuffer
                                 bufferSize:inNumberFrames
                           numberOfChannels:audioInput.streamFormat.mChannelsPerFrame];
        }
    }
    return result;
}


/// Buses
static const AudioUnitScope kBILAudioMicrophoneInputBus  = 1;
static const AudioUnitScope kBILAudioMicrophoneOutputBus = 0;

/// Flags
#if TARGET_OS_IPHONE
static const UInt32 kBILAudioMicrophoneDisableFlag = 1;
#elif TARGET_OS_MAC
static const UInt32 kBILAudioMicrophoneDisableFlag = 0;
#endif
static const UInt32 kBILAudioMicrophoneEnableFlag  = 1;


@interface BILAudioInput ()
{
    AudioStreamBasicDescription _streamFormat;
    AudioUnit                   _inputUnit;
    AudioBufferList            *_inputBuffer;
    Float64                     _deviceSampleRate;
    UInt32                      _deviceBufferFrameSize;
    BOOL                        _isCustomASBD;
}
@property (nonatomic, readonly, getter=isConfigured) BOOL configured;
@end


@implementation BILAudioInput

@synthesize fetchingAudio = _isFetchingAudio;
@synthesize configured    = _isConfigured;

@synthesize inputUnit    = _inputUnit;
@synthesize inputBuffer  = _inputBuffer;

@synthesize deviceBufferFrameSize = _deviceBufferFrameSize;

#pragma mark - Initializer

- (void)dealloc
{
    if (_isConfigured) {
        [BILAudio checkResult:AudioOutputUnitStop(_inputUnit)
                    operation:"Failed to uninitialize output unit"];
        
        [BILAudio checkResult:AudioUnitUninitialize(_inputUnit)
                    operation:"Failed to uninitialize output unit"];
        
        [BILAudio checkResult:AudioComponentInstanceDispose(_inputUnit)
                    operation:"Failed to uninitialize output unit"];
        
        {   // free
            for (UInt32 i = 0; i < _inputBuffer->mNumberBuffers; i++) {
                free(_inputBuffer->mBuffers[i].mData);
            }
            free(_inputBuffer);
        }
        
    }
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self configureInput];
    }
    return self;
}

- (instancetype)initWithDelegate:(id<BILAudioInputDelegate>)delegate
{
    self = [self init];
    if (self) {
        self.delegate = delegate;
    }
    return self;
}

#pragma mark - Execute

- (void)startFetchingAudio
{
    if (_isConfigured) {
        if(!_isFetchingAudio){
            [BILAudio checkResult:AudioOutputUnitStart(_inputUnit)
                        operation:"Microphone failed to start fetching audio"];
            _isFetchingAudio = YES;
        }
    }
}

- (void)stopFetchingAudio
{
    if (_isConfigured) {
        if (_isFetchingAudio) {
            [BILAudio checkResult:AudioOutputUnitStop(_inputUnit)
                       operation:"Microphone failed to stop fetching audio"];
            _isFetchingAudio = NO;
        }
    }
}

#pragma mark - Accessor

- (AudioStreamBasicDescription)streamFormat
{
    return _streamFormat;
}

- (void)setStreamFormat:(AudioStreamBasicDescription)streamFormat
{
    if (_isFetchingAudio) {
        NSAssert(_isFetchingAudio, @"Cannot set the AudioStreamBasicDescription while microphone is fetching audio");
    }
    else {
        _isCustomASBD = YES;
        _streamFormat = streamFormat;
        [self configureStreamFormatWithSampleRate:_deviceSampleRate];
    }  
}

#pragma mark - Configure AudioUnit

- (void)configureInput
{
    if (_isConfigured) {
        return;
    }
    
    // Get component description for input
    AudioComponentDescription inputComponentDescription;
    {   // Create an input component description for mic input
        inputComponentDescription.componentType         = kAudioUnitType_Output;
        inputComponentDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
        inputComponentDescription.componentFlags        = 0;
        inputComponentDescription.componentFlagsMask    = 0;
        #if TARGET_OS_IPHONE
        inputComponentDescription.componentSubType      = kAudioUnitSubType_RemoteIO;
        #elif TARGET_OS_MAC
        inputComponentDescription.componentSubType      = kAudioUnitSubType_HALOutput;
        #endif
    }
    
    // Get the input component
    AudioComponent inputComponent;
    {   // Try and find the component
        inputComponent = AudioComponentFindNext(NULL , &inputComponentDescription);
        NSAssert(inputComponent,@"Couldn't get input component unit!");
    }
    
    {   // Create a new instance of the component and store it for internal use
        [BILAudio checkResult:AudioComponentInstanceNew(inputComponent, &_inputUnit)
                    operation:"Couldn't open component for microphone input unit."];

    }
    
    {   // Enable Input Scope
        [BILAudio checkResult:AudioUnitSetProperty(_inputUnit,
                                                   kAudioOutputUnitProperty_EnableIO,
                                                   kAudioUnitScope_Input,
                                                   kBILAudioMicrophoneInputBus,
                                                   &kBILAudioMicrophoneEnableFlag,
                                                   sizeof(kBILAudioMicrophoneEnableFlag))
                    operation:"Couldn't enable input on I/O unit."];
    }
    
    {   // Disable Output Scope
        [BILAudio checkResult:AudioUnitSetProperty(_inputUnit,
                                                   kAudioOutputUnitProperty_EnableIO,
                                                   kAudioUnitScope_Output,
                                                   kBILAudioMicrophoneOutputBus,
                                                   &kBILAudioMicrophoneDisableFlag,
                                                   sizeof(kBILAudioMicrophoneDisableFlag))
                    operation:"Couldn't disable output on I/O unit."];
    }
    
    // Get the default device if we need to (OSX only, iOS uses RemoteIO)
    #if TARGET_OS_IPHONE
    // Do nothing (using RemoteIO)
    #elif TARGET_OS_MAC
    Float64 inputScopeSampleRate;
    {
        // Get the default audio input device (pulls an abstract type from system preferences)
        AudioDeviceID defaultDevice = kAudioObjectUnknown;
        UInt32 propSize = sizeof(defaultDevice);
        AudioObjectPropertyAddress defaultDeviceProperty;
        {
            defaultDeviceProperty.mSelector = kAudioHardwarePropertyDefaultInputDevice;
            defaultDeviceProperty.mScope    = kAudioObjectPropertyScopeGlobal;
            defaultDeviceProperty.mElement  = kAudioObjectPropertyElementMaster;
        }
        [BILAudio checkResult:AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                         &defaultDeviceProperty,
                                                         0,
                                                         NULL,
                                                         &propSize,
                                                         &defaultDevice)
                    operation:"Couldn't get default input device"];
        
        // Set the default device on the microphone input unit
        propSize = sizeof(defaultDevice);
        [BILAudio checkResult:AudioUnitSetProperty(_inputUnit,
                                                   kAudioOutputUnitProperty_CurrentDevice,
                                                   kAudioUnitScope_Global,
                                                   kBILAudioMicrophoneOutputBus,
                                                   &defaultDevice,
                                                   propSize)
                    operation:"Couldn't set default device on I/O unit"];
        
        // Get the stream format description from the newly created input unit and assign it to the output of the input unit
        AudioStreamBasicDescription inputScopeFormat;
        propSize = sizeof(AudioStreamBasicDescription);
        [BILAudio checkResult:AudioUnitGetProperty(_inputUnit,
                                                   kAudioUnitProperty_StreamFormat,
                                                   kAudioUnitScope_Output,
                                                   kBILAudioMicrophoneInputBus,
                                                   &inputScopeFormat,
                                                   &propSize)
                    operation:"Couldn't get ASBD from input unit (1)"];
        
        // Assign the same stream format description from the output of the input unit and pull the sample rate
        AudioStreamBasicDescription outputScopeFormat;
        propSize = sizeof(AudioStreamBasicDescription);
        [BILAudio checkResult:AudioUnitGetProperty(_inputUnit,
                                                   kAudioUnitProperty_StreamFormat,
                                                   kAudioUnitScope_Input,
                                                   kBILAudioMicrophoneInputBus,
                                                   &outputScopeFormat,
                                                   &propSize)
                    operation:"Couldn't get ASBD from input unit (2)"];
        
        // Store the input scope's sample rate
        inputScopeSampleRate = inputScopeFormat.mSampleRate;
    }
    #endif
    
    {   // Configure device and pull hardware specific sampling rate (default = 44.1 kHz)
        Float64 hardwareSampleRate = 44100.0;
        #if TARGET_OS_IPHONE
            #if !(TARGET_IPHONE_SIMULATOR)
            hardwareSampleRate = [[AVAudioSession sharedInstance] sampleRate];
            #endif
        #elif TARGET_OS_MAC
        hardwareSampleRate = inputScopeSampleRate;
        #endif
        _deviceSampleRate = hardwareSampleRate;
    }
    
    Float32 deviceBufferDuration;
    {   // Configure device and pull hardware specific buffer duration (default = 0.0232)
        Float32 bufferDuration = 0.0232; // Type 1/43 by default
        #if TARGET_OS_IPHONE
            #if !(TARGET_IPHONE_SIMULATOR)
            NSError *err;
            [[AVAudioSession sharedInstance] setPreferredIOBufferDuration:bufferDuration error:&err];
            if (err) {
                NSLog(@"Error setting preferredIOBufferDuration for audio session: %@", err.localizedDescription);
            }
            bufferDuration = [[AVAudioSession sharedInstance] IOBufferDuration];
            #endif
        #elif TARGET_OS_MAC
        // nop
        #endif
        deviceBufferDuration = bufferDuration;
    }
    
    {   // Configure the stream format with the hardware sample rate
        [self configureStreamFormatWithSampleRate:_deviceSampleRate];
    }
        
    {   // Get buffer frame size
        UInt32 bufferFrameSize;
        UInt32 propSize = sizeof(bufferFrameSize);
        [BILAudio checkResult:AudioUnitGetProperty(_inputUnit,
                                                   #if TARGET_OS_IPHONE
                                                   kAudioUnitProperty_MaximumFramesPerSlice,
                                                   #elif TARGET_OS_MAC
                                                   kAudioDevicePropertyBufferFrameSize,
                                                   #endif
                                                   kAudioUnitScope_Global,
                                                   kBILAudioMicrophoneOutputBus,
                                                   &bufferFrameSize,
                                                   &propSize)
                    operation:"Failed to get buffer frame size"];
        _deviceBufferFrameSize = bufferFrameSize;
    }
    
    {   // Create the audio buffer list and pre-malloc the buffers in the list
        UInt32 bufferSizeBytes = _deviceBufferFrameSize * _streamFormat.mBytesPerFrame;
        UInt32 propSize = offsetof(AudioBufferList, mBuffers[0]) + (sizeof(AudioBuffer)*_streamFormat.mChannelsPerFrame);
        _inputBuffer                 = (AudioBufferList*)malloc(propSize);
        _inputBuffer->mNumberBuffers = _streamFormat.mChannelsPerFrame;
        for (UInt32 i = 0; i < _inputBuffer->mNumberBuffers; i++) {
            _inputBuffer->mBuffers[i].mNumberChannels = _streamFormat.mChannelsPerFrame;
            _inputBuffer->mBuffers[i].mDataByteSize   = bufferSizeBytes;
            _inputBuffer->mBuffers[i].mData           = malloc(bufferSizeBytes);
        }
    }
    
    {   // Setup input callback
        AURenderCallbackStruct inputCallbackStruct;
        inputCallbackStruct.inputProc       = InputCallback;
        inputCallbackStruct.inputProcRefCon = (__bridge void *)self;
        [BILAudio checkResult:AudioUnitSetProperty(_inputUnit,
                                                   kAudioOutputUnitProperty_SetInputCallback,
                                                   kAudioUnitScope_Global,
                                                   #if TARGET_OS_IPHONE
                                                   kBILAudioMicrophoneInputBus,
                                                   #elif TARGET_OS_MAC
                                                   kBILAudioMicrophoneOutputBus,
                                                   #endif
                                                   &inputCallbackStruct,
                                                   sizeof(inputCallbackStruct))
                    operation:"Couldn't set input callback"];
    }
    
    {   // Disable buffer allocation (optional - do this if we want to pass in our own)
        [BILAudio checkResult:AudioUnitSetProperty(_inputUnit,
                                                   kAudioUnitProperty_ShouldAllocateBuffer,
                                                   kAudioUnitScope_Output,
                                                   kBILAudioMicrophoneInputBus,
                                                   &kBILAudioMicrophoneDisableFlag,
                                                   sizeof(kBILAudioMicrophoneDisableFlag))
                    operation:"Could not disable audio unit allocating its own buffers"];
    }
    
    // Initialize the audio unit
    [BILAudio checkResult:AudioUnitInitialize(_inputUnit)
                operation:"Couldn't initialize the input unit"];
    
    _isConfigured = YES;
}

- (void)configureStreamFormatWithSampleRate:(Float64)sampleRate
{
    if (_isCustomASBD) {
        _streamFormat.mSampleRate = sampleRate;
    } else {
        _streamFormat = [BILAudio physicalInputWithSampleRate:_deviceSampleRate];
    }
    
    UInt32 propSize = sizeof(_streamFormat);
    // Set the stream format for output on the microphone's input scope
    [BILAudio checkResult:AudioUnitSetProperty(_inputUnit,
                                               kAudioUnitProperty_StreamFormat,
                                               kAudioUnitScope_Input,
                                               kBILAudioMicrophoneOutputBus,
                                               &_streamFormat,
                                               propSize)
                operation:"Could not set microphone's stream format bus 0"];
    
    // Set the stream format for the input on the microphone's output scope
    [BILAudio checkResult:AudioUnitSetProperty(_inputUnit,
                                               kAudioUnitProperty_StreamFormat,
                                               kAudioUnitScope_Output,
                                               kBILAudioMicrophoneInputBus,
                                               &_streamFormat,
                                               propSize)
                operation:"Could not set microphone's stream format bus 1"];
}

@end
