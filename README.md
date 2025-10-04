[![pub package](https://img.shields.io/pub/v/flutter_pcm_sound.svg)](https://pub.dartlang.org/packages/flutter_pcm_sound)

<p align="center">
    <img alt="Logo" src="https://github.com/chipweinberger/flutter_pcm_sound/blob/master/site/logo.png?raw=true" style="height: 300px;" />
</p>

Send real-time PCM audio (16-bit integer) to your device speakers, from your Flutter app!

## No Dependencies

FlutterPcmSound has zero dependencies besides Flutter, Android, iOS, and MacOS themselves.

## *Not* for Audio Files

Unlike other plugins, `flutter_pcm_sound` does *not* use audio files (For example: [sound_pool](https://pub.dev/packages/soundpool)).

Instead, `flutter_pcm_sound` is for apps that generate audio in realtime a few milliseconds before you hear it. For example, using [dart_melty_soundfont](https://pub.dev/packages/dart_melty_soundfont).


## Callback Based, For Real-Time Audio

In contrast to [raw_sound](https://pub.dev/packages/raw_sound), FlutterPcmSound uses a callback `setFeedCallback` to signal when to feed more samples.

You can lower the feed threshold using `setFeedThreshold` to achieve real time audio, or increase it to have a cushy buffer.

## Event Based Feeding

Unlike traditional audio libraries which use a high-frequency timer-based audio callback, `flutter_pcm_sound` uses a low-frequency event-based callback. This integrates more seamlessly in the existing Flutter event loop, without necessitating an Isolate to ensure precise timing.

Your feed callback is invoked _once_ for each of these events:
- **Low-buffer event** – when the number of buffered frames falls **below** the threshold set with `setFeedThreshold`.
- **Zero event** – when the buffer is fully drained (`remainingFrames == 0`).

**Note:** _once_ means once per `feed()` — every time you feed new data, the plugin will trigger another low-buffer or zero event when necessary.

> 💡 **Tip:**  By altering how many extra samples you `feed` beyond your threshold, you can control how often `flutter_pcm_sound` invokes your feed callback.

> 💡 **Tip:** If you prefer, it's easy to wrap `flutter_pcm_sound` to simulate traditional timer-based feeding. 1) set a large feed threshold so that `flutter_pcm_sound` regularly tells you its `remainingFrames` 2) start a Dart-side `Timer.periodic(...)` or `Ticker` 3) use that timer to invoke a new feed callback and pass it the `remainingFrames` minus the elapsed time since the original callback. See [this example](https://github.com/chipweinberger/flutter_pcm_sound/issues/43#issuecomment-3368369457)

> 💡 **Tip:** You should still consider running your sound code in a Dart `Isolate`, so that it is decoupled from UI framedrops.

## One-Pedal Driving

To play audio, just keep calling `feed`. 

To stop audio, just stop calling `feed`.

> 💡 **Tip:** If you prefer a traditional timer-based API with `start()` and `stop()`, I recommend wrapping `flutter_pcm_sound` as described in the [Event Based Feeding](#event-based-feeding) tips.

## Is Playing?

When your feed callback hits `remainingFrames=0` you know playing stopped.

## Usage

```dart
// for testing purposes, a C-Major scale 
MajorScale scale = MajorScale(sampleRate: 44100, noteDuration: 0.25);

// invoked whenever we need to feed more samples to the platform
void onFeed(int remainingFrames) async {
    // you could use 'remainingFrames' to feed very precisely.
    // But here we just load a few thousand samples everytime we run low.
    List<int> frame = scale.generate(periods: 20);
    await FlutterPcmSound.feed(PcmArrayInt16.fromList(frame));
}

await FlutterPcmSound.setup(sampleRate: 44100, channelCount: 1);
await FlutterPcmSound.setFeedThreshold(8000); 
FlutterPcmSound.setFeedCallback(onFeed);
FlutterPcmSound.start(); // for convenience. Equivalent to calling onFeed(0);
```

## ⭐ Stars ⭐

Please star this repo & on [pub.dev](https://pub.dev/packages/flutter_pcm_sound). We all benefit from having a larger community.

## Example App

Enable the platforms you need.

```
cd ./example                      
flutter config --enable-macos-desktop                                                      
flutter config --enable-android 
flutter config --enable-ios 
flutter create .
flutter run
```



