#import "FlutterPcmSoundPlugin.h"
#import <AudioToolbox/AudioToolbox.h>

#if TARGET_OS_IOS
#import <AVFoundation/AVFoundation.h>
#endif

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
@property(nonatomic) float volumeLevel;
@property(nonatomic) NSMutableData *mSamples;
@property(nonatomic) int mNumChannels; 
@property(nonatomic) int mFeedThreshold; 
@property(nonatomic) bool mDidInvokeFeedCallback; 
@property(nonatomic) bool mDidSetup; 
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
    instance.mDidSetup = false;
    instance.volumeLevel = 1.0f;

    [registrar addMethodCallDelegate:instance channel:methodChannel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result
{
    @try
    {
#if TARGET_OS_OSX
        if ([@"getAudioDevices" isEqualToString:call.method]) {
            result([self getAudioOutputDevices]);
        } else if ([@"setAudioDevice" isEqualToString:call.method]) {
            NSString *deviceName = call.arguments[@"deviceName"];
            if ([self setAudioOutputDeviceByName:deviceName]) {
                result(nil);
            } else {
                result([FlutterError errorWithCode:@"DEVICE_NOT_FOUND"
                                           message:@"Audio device not found"
                                           details:nil]);
            }
        } else
#endif

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
            NSNumber *sampleRate       = args[@"sample_rate"];
            NSNumber *numChannels      = args[@"num_channels"];
#if TARGET_OS_IOS
            NSString *iosAudioCategory = args[@"ios_audio_category"];
#endif

            self.mNumChannels = [numChannels intValue];

#if TARGET_OS_IOS
	        // handle background audio in iOS
            // Default to Playback if no matching case is found
            AVAudioSessionCategory category = AVAudioSessionCategorySoloAmbient;
            if ([iosAudioCategory isEqualToString:@"ambient"]) {
                category = AVAudioSessionCategoryAmbient;
            } else if ([iosAudioCategory isEqualToString:@"soloAmbient"]) {
                category = AVAudioSessionCategorySoloAmbient;
            } else if ([iosAudioCategory isEqualToString:@"playback"]) {
                category = AVAudioSessionCategoryPlayback;
            }
            else if ([iosAudioCategory isEqualToString:@"playAndRecord"]) {
                category = AVAudioSessionCategoryPlayAndRecord;
            }
            
            // Set the AVAudioSession category based on the string value
            NSError *error = nil;
            [[AVAudioSession sharedInstance] setCategory:category error:&error];
            if (error) {
                NSLog(@"Error setting AVAudioSession category: %@", error);
                result([FlutterError errorWithCode:@"AVAudioSessionError" 
                                        message:@"Error setting AVAudioSession category" 
                                        details:[error localizedDescription]]);
                return;
            }
            
            // Activate the audio session
            [[AVAudioSession sharedInstance] setActive:YES error:&error];
            if (error) {
                NSLog(@"Error activating AVAudioSession: %@", error);
                result([FlutterError errorWithCode:@"AVAudioSessionError" 
                                        message:@"Error activating AVAudioSession" 
                                        details:[error localizedDescription]]);
                return;
            }
#endif

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

            self.mDidSetup = true;
            
            result(@(true));
        } else if ([@"getVolume" isEqualToString:call.method]) {
            result(@(_volumeLevel));
        } else if ([@"setVolume" isEqualToString:call.method]) {
            NSNumber *volume = call.arguments[@"volume"];
            [self setVolume:volume];
            result(@(true));
        } else if ([@"feed" isEqualToString:call.method])
        {
            // setup check
            if (self.mDidSetup == false) {
                result([FlutterError errorWithCode:@"Setup" message:@"must call setup first" details:nil]);
                return;
            }

            NSDictionary *args = (NSDictionary*)call.arguments;
            FlutterStandardTypedData *buffer = args[@"buffer"];

            @synchronized (self.mSamples) {
                [self.mSamples appendData:buffer.data];
            }

            // reset
            self.mDidInvokeFeedCallback = false;

            // start
            OSStatus status = AudioOutputUnitStart(_mAudioUnit);
            if (status != noErr) {
                NSString* message = [NSString stringWithFormat:@"AudioOutputUnitStart failed. OSStatus: %@", @(status)];
                result([FlutterError errorWithCode:@"AudioUnitError" message:message details:nil]);
                return;
            }

            result(@(true));
        }
        else if ([@"setFeedThreshold" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
            NSNumber *feedThreshold = args[@"feed_threshold"];

            self.mFeedThreshold = [feedThreshold intValue];

            result(@(true));
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
        self.mDidSetup = false;
    }
    @synchronized (self.mSamples) {
        self.mSamples = [NSMutableData new]; 
    }
}

- (void)stopAudioUnit
{
    if (_mAudioUnit != nil) {
        UInt32 isRunning = 0;
        UInt32 size = sizeof(isRunning);
        OSStatus status = AudioUnitGetProperty(_mAudioUnit,
                                            kAudioOutputUnitProperty_IsRunning,
                                            kAudioUnitScope_Global,
                                            0,
                                            &isRunning,
                                            &size);
        if (status != noErr) {
            NSLog(@"AudioUnitGetProperty IsRunning failed. OSStatus: %@", @(status));
            return;
        }
        if (isRunning) {
            status = AudioOutputUnitStop(_mAudioUnit);
            if (status != noErr) {
                NSLog(@"AudioOutputUnitStop failed. OSStatus: %@", @(status));
            } else {
                NSLog(@"AudioUnit stopped because no more samples");
            }
        }
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

        // clear
        memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);

        NSUInteger bytesToCopy = MIN(ioData->mBuffers[0].mDataByteSize, [instance.mSamples length]);
        
        // provide samples
        memcpy(ioData->mBuffers[0].mData, [instance.mSamples bytes], bytesToCopy);

        // modifying volume
        int16_t *samples = (int16_t *)ioData->mBuffers[0].mData;
        for (NSUInteger i = 0; i < bytesToCopy / sizeof(int16_t); i++) {
            samples[i] = (int16_t)(samples[i] * instance.volumeLevel);
        }

        // pop front bytes
        NSRange range = NSMakeRange(0, bytesToCopy);
        [instance.mSamples replaceBytesInRange:range withBytes:NULL length:0];

        remainingFrames = [instance.mSamples length] / (instance.mNumChannels * sizeof(short));

        // should request more frames?
        shouldRequestMore = remainingFrames <= instance.mFeedThreshold && !instance.mDidInvokeFeedCallback;
    }

    // stop running, if needed
    if (remainingFrames == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [instance stopAudioUnit];
        });
    }

    if (shouldRequestMore) { 
        instance.mDidInvokeFeedCallback = true;
        NSDictionary *response = @{@"remaining_frames": @(remainingFrames)};
        dispatch_async(dispatch_get_main_queue(), ^{
            [instance.mMethodChannel invokeMethod:@"OnFeedSamples" arguments:response];
        });
    }

    return noErr;
}

- (void)setVolume:(NSNumber *)volume {
    float vol = [volume floatValue];
    if (vol < 0.0f) vol = 0.0f;
    if (vol > 1.0f) vol = 1.0f;
    self.volumeLevel = vol;
}

#if TARGET_OS_OSX

- (NSArray *)getAudioOutputDevices {
    NSMutableArray *deviceList = [NSMutableArray array];
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 propertySize;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &propertySize) != noErr) {
        return deviceList;
    }

    int deviceCount = propertySize / sizeof(AudioObjectID);
    AudioObjectID deviceIDs[deviceCount];

    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &propertySize, deviceIDs) != noErr) {
        return deviceList;
    }

    for (int i = 0; i < deviceCount; i++) {
        // Checking if the device supports the output audio stream
        AudioObjectPropertyAddress streamAddress = {
            kAudioDevicePropertyStreams,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain
        };

        UInt32 streamPropertySize;
        if (AudioObjectGetPropertyDataSize(deviceIDs[i], &streamAddress, 0, NULL, &streamPropertySize) != noErr || streamPropertySize == 0) {
            continue; // If the device has no output streams, skip it
        }

        CFStringRef deviceName;
        propertySize = sizeof(deviceName);
        AudioObjectPropertyAddress nameAddress = {
            kAudioDevicePropertyDeviceNameCFString,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };

        if (AudioObjectGetPropertyData(deviceIDs[i], &nameAddress, 0, NULL, &propertySize, &deviceName) == noErr) {
            [deviceList addObject:(__bridge NSString *)deviceName];
            CFRelease(deviceName);
        }
    }

    return deviceList;
}

- (BOOL)setAudioOutputDeviceByName:(NSString *)deviceName {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 propertySize;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &propertySize) != noErr) {
        return NO;
    }

    int deviceCount = propertySize / sizeof(AudioObjectID);
    AudioObjectID deviceIDs[deviceCount];

    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &propertySize, deviceIDs) != noErr) {
        return NO;
    }

    for (int i = 0; i < deviceCount; i++) {
        CFStringRef currentDeviceName;
        propertySize = sizeof(currentDeviceName);
        AudioObjectPropertyAddress nameAddress = {
            kAudioDevicePropertyDeviceNameCFString,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain
        };

        if (AudioObjectGetPropertyData(deviceIDs[i], &nameAddress, 0, NULL, &propertySize, &currentDeviceName) == noErr) {
            if ([(__bridge NSString *)currentDeviceName isEqualToString:deviceName]) {
                // Applying a device to the AudioUnit
                OSStatus status = AudioUnitSetProperty(
                    _mAudioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &deviceIDs[i],
                    sizeof(AudioObjectID)
                );

                CFRelease(currentDeviceName);

                if (status == noErr) {
                    return YES;
                } else {
                    NSLog(@"Error setting AudioUnit output device: %d", status);
                    return NO;
                }
            }
            CFRelease(currentDeviceName);
        }
    }

    return NO;
}


#endif



@end
