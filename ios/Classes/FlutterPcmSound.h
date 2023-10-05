
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif
#import <CoreAudio/CoreAudio.h>

#define NAMESPACE @"flutter_pcm_sound"

@interface FlutterPcmSoundPlugin : NSObject<FlutterPlugin, CBCentralManagerDelegate, CBPeripheralDelegate>
@end

@interface FlutterPcmSoundStreamHandler : NSObject<FlutterStreamHandler>
@end
