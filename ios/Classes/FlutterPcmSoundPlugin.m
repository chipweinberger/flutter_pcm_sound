#import "FlutterPcmSoundPlugin.h"
#import <AudioToolbox/AudioToolbox.h>

#define kOutputBus 0
#define NAMESPACE @"flutter_pcm_sound" // Assuming this is the namespace you want

typedef NS_ENUM(NSUInteger, LogLevel) {
    none = 0,
    error = 1,
    standard = 2,
    verbose = 3,
};

@interface FlutterPcmSoundPlugin ()
@property(nonatomic) NSObject<FlutterPluginRegistrar> *registrar;
@property(nonatomic) FlutterMethodChannel *mMethodChannel;
@property(nonatomic) LogLevel mLogLevel;
@property(nonatomic) AudioComponentInstance mAudioUnit;
@property(nonatomic) NSMutableData *mSamples;
@property(nonatomic) int mNumChannels; 
@property(nonatomic) int mFeedThreshold; 
@property(nonatomic) bool mDidInvokeFeedCallback; 
@end

@implementation FlutterPcmSoundPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
{
    FlutterMethodChannel *methodChannel = [FlutterMethodChannel methodChannelWithName:NAMESPACE @"/methods"
                                                                    binaryMessenger:[registrar messenger]];

    FlutterPcmSoundPlugin *instance = [[FlutterPcmSoundPlugin alloc] init];
    instance.mMethodChannel = methodChannel;
    instance.mLogLevel = verbose;
    instance.mSamples = [NSMutableData new];
    instance.mFeedThreshold = 8000;
    instance.mDidInvokeFeedCallback = false;

    [registrar addMethodCallDelegate:instance channel:methodChannel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result
{
    @try
    {
        if ([@"setLogLevel" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
            NSNumber *logLevelNumber  = args[@"log_level"];

            self.mLogLevel = (LogLevel)[logLevelNumber integerValue];

            result(@(true));
        }
        else if ([@"setup" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
            NSNumber *sampleRate  = args[@"sample_rate"];
            NSNumber *numChannels = args[@"num_channels"];

            self.mNumChannels = [numChannels intValue];

            // cleanup
            if (_mAudioUnit != nil) {
                [self cleanup];
            }

            // create
            AudioComponentDescription desc;
            desc.componentType = kAudioUnitType_Output;
#if TARGET_OS_IOS
            desc.componentSubType = kAudioUnitSubType_RemoteIO;
#else // MacOS
            desc.componentSubType = kAudioUnitSubType_DefaultOutput;
#endif
            desc.componentFlags = 0;
            desc.componentFlagsMask = 0;
            desc.componentManufacturer = kAudioUnitManufacturer_Apple;

            AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
            OSStatus status = AudioComponentInstanceNew(inputComponent, &_mAudioUnit);
            if (status != noErr) {
                NSString* message = [NSString stringWithFormat:@"AudioComponentInstanceNew failed. OSStatus: %@", @(status)];
                result([FlutterError errorWithCode:@"AudioUnitError" message:message details:nil]);
                return;
            }

            // set stream format
            AudioStreamBasicDescription audioFormat;
            audioFormat.mSampleRate = [sampleRate intValue];
            audioFormat.mFormatID = kAudioFormatLinearPCM;
            audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
            audioFormat.mFramesPerPacket = 1;
            audioFormat.mChannelsPerFrame = self.mNumChannels;
            audioFormat.mBitsPerChannel = 16;
            audioFormat.mBytesPerFrame = self.mNumChannels * (audioFormat.mBitsPerChannel / 8);
            audioFormat.mBytesPerPacket = audioFormat.mBytesPerFrame * audioFormat.mFramesPerPacket;

            status = AudioUnitSetProperty(_mAudioUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input,
                                    kOutputBus,
                                    &audioFormat,
                                    sizeof(audioFormat));
            if (status != noErr) {
                NSString* message = [NSString stringWithFormat:@"AudioUnitSetProperty StreamFormat failed. OSStatus: %@", @(status)];
                result([FlutterError errorWithCode:@"AudioUnitError" message:message details:nil]);
                return;
            }

            // set callback
            AURenderCallbackStruct callback;
            callback.inputProc = RenderCallback;
            callback.inputProcRefCon = (__bridge void *)(self);

            status = AudioUnitSetProperty(_mAudioUnit,
                                kAudioUnitProperty_SetRenderCallback,
                                kAudioUnitScope_Global,
                                kOutputBus,
                                &callback,
                                sizeof(callback));
            if (status != noErr) {
                NSString* message = [NSString stringWithFormat:@"AudioUnitSetProperty SetRenderCallback failed. OSStatus: %@", @(status)];
                result([FlutterError errorWithCode:@"AudioUnitError" message:message details:nil]);
                return;
            }

            // initialize
            status = AudioUnitInitialize(_mAudioUnit);
            if (status != noErr) {
                NSString* message = [NSString stringWithFormat:@"AudioUnitInitialize failed. OSStatus: %@", @(status)];
                result([FlutterError errorWithCode:@"AudioUnitError" message:message details:nil]);
                return;
            }
            
            result(@(true));
        }
        else if ([@"play" isEqualToString:call.method])
        {
            self.mDidInvokeFeedCallback = false;

            OSStatus status = AudioOutputUnitStart(_mAudioUnit);
            if (status != noErr) {
                NSString* message = [NSString stringWithFormat:@"AudioOutputUnitStart failed. OSStatus: %@", @(status)];
                result([FlutterError errorWithCode:@"AudioUnitError" message:message details:nil]);
                return;
            }

            result(@(true));
        }
        else if ([@"pause" isEqualToString:call.method])
        {
            OSStatus status = AudioOutputUnitStop(_mAudioUnit);
            if (status != noErr) {
                NSString* message = [NSString stringWithFormat:@"AudioOutputUnitStop failed. OSStatus: %@", @(status)];
                result([FlutterError errorWithCode:@"AudioUnitError" message:message details:nil]);
                return;
            }

            result(@(true));
        }
        else if ([@"stop" isEqualToString:call.method])
        {
            OSStatus status = AudioOutputUnitStop(_mAudioUnit);
            if (status != noErr) {
                NSString* message = [NSString stringWithFormat:@"AudioOutputUnitStop failed. OSStatus: %@", @(status)];
                result([FlutterError errorWithCode:@"AudioUnitError" message:message details:nil]);
                return;
            }

            @synchronized (self.mSamples) {
                [self.mSamples setLength:0];
            }
            result(@(true));
        }
        else if ([@"clear" isEqualToString:call.method])
        {
            @synchronized (self.mSamples) {
                [self.mSamples setLength:0];
            }
            result(@(true));
        }
        else if ([@"feed" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
            FlutterStandardTypedData *buffer = args[@"buffer"];

            @synchronized (self.mSamples) {
                [self.mSamples appendData:buffer.data];
            }

            // reset
            self.mDidInvokeFeedCallback = false;

            result(@(true));
        }
        else if ([@"setFeedThreshold" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
            NSNumber *feedThreshold = args[@"feed_threshold"];

            self.mFeedThreshold = [feedThreshold intValue];

            result(@(true));
        }
        else if ([@"remainingFrames" isEqualToString:call.method])
        {
            NSUInteger count = 0;
            @synchronized (self.mSamples) {
                count = [self.mSamples length] / (self.mNumChannels * sizeof(short));
            }
            result(@(count));
        }
        else if([@"release" isEqualToString:call.method])
        {
            [self cleanup];
            result(@(true));
        }
        else
        {
            result([FlutterError errorWithCode:@"functionNotImplemented" message:call.method details:nil]);
        }
    }
    @catch (NSException *e)
    {
        NSString *stackTrace = [[e callStackSymbols] componentsJoinedByString:@"\n"];
        NSDictionary *details = @{@"stackTrace": stackTrace};
        result([FlutterError errorWithCode:@"iosException" message:[e reason] details:details]);
    }
}

- (void)cleanup
{
    if (_mAudioUnit != nil) {
        AudioUnitUninitialize(_mAudioUnit);
        AudioComponentInstanceDispose(_mAudioUnit);
        _mAudioUnit = nil;
    }
    @synchronized (self.mSamples) {
        self.mSamples = [NSMutableData new]; 
    }
}

static OSStatus RenderCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData)
{
    FlutterPcmSoundPlugin *instance = (__bridge FlutterPcmSoundPlugin *)(inRefCon);

    NSUInteger remainingFrames;
    BOOL shouldRequestMore = false;

    @synchronized (instance.mSamples) {

        NSUInteger bytesToCopy = MIN(ioData->mBuffers[0].mDataByteSize, [instance.mSamples length]);
        
        // provide samples
        memcpy(ioData->mBuffers[0].mData, [instance.mSamples bytes], bytesToCopy);

        // pop front bytes
        NSRange range = NSMakeRange(0, bytesToCopy);
        [instance.mSamples replaceBytesInRange:range withBytes:NULL length:0];

        remainingFrames = [instance.mSamples length] / (instance.mNumChannels * sizeof(short));

        if (remainingFrames <= instance.mFeedThreshold) { 
            if (instance.mDidInvokeFeedCallback == false) {
                instance.mDidInvokeFeedCallback = true;
                shouldRequestMore = true;
            }
        }
    }

    if (shouldRequestMore) { 
        NSDictionary *response = @{@"remaining_frames": @(remainingFrames)};
        dispatch_async(dispatch_get_main_queue(), ^{
            [instance.mMethodChannel invokeMethod:@"OnFeedSamples" arguments:response];
        });
    }

    return noErr;
}


@end
