
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#import <CoreAudio/CoreAudio.h>
#else
#import <Flutter/Flutter.h>
#endif

#define NAMESPACE @"flutter_pcm_sound"

@interface FlutterPcmSoundPlugin : NSObject<FlutterPlugin>
@end
