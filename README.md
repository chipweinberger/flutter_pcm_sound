[![pub package](https://img.shields.io/pub/v/flutter_pcm_sound.svg)](https://pub.dartlang.org/packages/flutter_pcm_sound)

<p align="center">
    <img alt="Logo" src="https://github.com/chipweinberger/flutter_pcm_sound/blob/master/site/logo.png?raw=true" style="height: 300px;" />
</p>

Send real-time PCM audio (16-bit integer) to your device speakers, from your Flutter app!

## No Dependencies

FlutterPcmSound has zero dependencies besides Flutter, Android, iOS, and MacOS themselves.

## Callback Based, For Real-Time Audio

In contrast to [raw_sound](https://pub.dev/packages/raw_sound), FlutterPcmSound uses a callback `setFeedCallback` to signal when to feed more samples.

You can also manually `feed` whenever you like.

## ⭐ Stars ⭐

Please star this repo & on [pub.dev](https://pub.dev/packages/flutter_pcm_sound). We all benefit from having a larger community.

## Example App

Enable just the platforms you need.

```
cd ./example
flutter config --enable-web                           
flutter config --enable-macos-desktop                                                      
flutter config --enable-android 
flutter config --enable-ios 
flutter create .
flutter run
```

## Usage

```dart
// for testing purposes, a C-Major scale 
MajorScale scale = MajorScale(sampleRate: 44100, noteDuration: 0.25);

// invoked whenever we need to feed more samples to the platform
void onFeed(int remainingFrames) async {
    List<int> frame = scale.generate(periods: 100);
    await FlutterPcmSound.feed(PcmArrayInt16.fromList(frame));
}

await FlutterPcmSound.setup(sampleRate: 44100, channelCount: 1);
await FlutterPcmSound.setFeedThreshold(8000); // feed when below 8000 queued frames
await FlutterPcmSound.setFeedCallback(onFeed);
await FlutterPcmSound.play();
```

## Other Useful Functions

```dart
// suspend playback but does *not* clear queued samples
await FlutterPcmSound.pause();

// clears all queued samples
await FlutterPcmSound.clear();

// suspend playback & clear queued samples
await FlutterPcmSound.stop();

// get the current number of queued frames
int samples = await FlutterPcmSound.remainingFrames();
```



