[![pub package](https://img.shields.io/pub/v/flutter_pcm_sound.svg)](https://pub.dartlang.org/packages/flutter_pcm_sound)

<p align="center">
    <img alt="Logo" src="https://github.com/chipweinberger/flutter_pcm_sound/blob/master/site/logo.png?raw=true" style="height: 300px;" />
</p>

FlutterPcmSound is a [Flutter](https://flutter.dev) plugin for playing raw PCM audio (16-bit integer) in your Flutter app.

## No Dependencies

FlutterPcmSound has zero dependencies besides Flutter, Android, iOS, and MacOS themselves.

## ⭐ Stars ⭐

Please star this repo & on [pub.dev](https://pub.dev/packages/flutter_pcm_sound). We all benefit from having a larger community.

## Example App

```
# enable the platforms you need
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

### Set Log Level

```dart
// if your terminal doesn't support color you'll see annoying logs like `\x1B[1;35m`
FlutterPcmSound.setLogLevel(LogLevel.verbose, color:false)
```

**Verbose Logs:**

⚫ = function name

🟣 = args to platform

🟡 = data from platform


