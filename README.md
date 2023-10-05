[![pub package](https://img.shields.io/pub/v/flutter_pcm_sound.svg)](https://pub.dartlang.org/packages/flutter_pcm_sound)

<p align="center">
    <img alt="Logo" src="https://github.com/chipweinberger/flutter_pcm_sound/blob/master/site/logo.png?raw=true" style="height: 300px;" />
</p>

FlutterPcmSound is a [Flutter](https://flutter.dev) plugin for playing raw PCM audio (16-bit integer) in your Flutter app.

## No Dependencies

FlutterPcmSound has zero dependencies besides Flutter, Android, iOS, and MacOS themselves.

## ⭐ Stars ⭐

Please star this repo & on [pub.dev](https://pub.dev/packages/flutter_pcm_sound). We all benefit from having a larger community.

## Callback Based

FlutterPcmSound uses a callback `setFeedCallback` so you know when to feed more samples.

You can also manually `feed` whenever or use `remainingSamples`.

## Example App

```
# enable platforms you need
cd ./example
flutter config --enable-web                           
flutter config --enable-macos-desktop                                                      
flutter config --enable-android 
flutter config --enable-ios 
flutter create .
flutter run
```

<p align="center">
<img alt="example" src="https://github.com/chipweinberger/flutter_pcm_sound/blob/master/site/example.png?raw=true" />
</p>

## Usage

```dart
// for testing purposes
List<int> sineWave({int periods = 1, int sampleRate = 44100, int freq = 440, double volume = 0.5}) {
    final period = 1.0 / freq;
    final nFramesPerPeriod = (period * sampleRate).toInt();
    final totalFrames = nFramesPerPeriod * periods;
    final step = math.pi * 2 / nFramesPerPeriod;
    List<int> data = List<int>.filled(totalFrames * 2, 0);
    for (int i = 0; i < totalFrames; i++) {
        final value = (math.sin(step * (i % nFramesPerPeriod)) * volume * 32767).toInt();
        data[i * 2 + 1] = (value & 0xFF00) >> 8;
        data[i * 2 + 0] = value & 0x00FF;
    }
    return data;
}

// invoked whenever we need to feed more samples to the platform
void onFeed(int remainingSamples) async {
    int step = (DateTime.now().millisecondsSinceEpoch ~/ 500) % 14;
    int freq = 200 + (step < 7 ? 50 * step : 300 - (step - 7) * 50);
    final frame = sineWave(periods: 20, sampleRate: sampleRate, freq: freq);
    await FlutterPcmSound.feed(Uint8List.fromList(frame));
}

await FlutterPcmSound.setup(sampleRate: 44100, channelCount: 1);
await FlutterPcmSound.setFeedThreshold(8000); // feed when below 8000 queued samples
await FlutterPcmSound.setFeedCallback(onFeed);
await FlutterPcmSound.play();
```

## Other Useful Functions

```
// suspend playback but does *not* clear queued samples
await FlutterPcmSound.pause();

// clears all queued samples
await FlutterPcmSound.clear();

// suspend playback & clear queued samples
await FlutterPcmSound.stop();

// get the current number of queued samples
int samples = await FlutterPcmSound.remainingSamples();
```



