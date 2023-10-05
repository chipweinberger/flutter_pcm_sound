import 'dart:async';
import 'package:flutter/services.dart';

enum LogLevel {
  none,
  error,
  standard,
  verbose,
}

class FlutterPcmSound {
  static const MethodChannel _channel = const MethodChannel('flutter_pcm_sound/methods');

  static LogLevel _logLevel = LogLevel.standard;

  static Future<void> setLogLevel(int level) async {
    return await _channel.invokeMethod('setLogLevel', {'log_level': level});
  }

  static Future<void> setup(int sampleRate, int numChannels) async {
    return await _channel.invokeMethod('setup', {
      'sample_rate': sampleRate,
      'num_channels': numChannels,
    });
  }

  static Future<void> play() async {
    return await _channel.invokeMethod('play');
  }

  static Future<void> pause() async {
    return await _channel.invokeMethod('pause');
  }

  static Future<void> stop() async {
    return await _channel.invokeMethod('stop');
  }

  static Future<void> clear() async {
    return await _channel.invokeMethod('clear');
  }

  static Future<void> feed(Uint8List buffer) async {
    return await _channel.invokeMethod('feed', {'buffer': buffer});
  }

  static Future<void> setFeedThreshold(int threshold) async {
    return await _channel.invokeMethod('setFeedThreshold', {'feed_threshold': threshold});
  }

  static Future<void> getPendingSamplesCount() async {
    return await _channel.invokeMethod('getPendingSamplesCount');
  }

  static Future<void> release() async {
    return await _channel.invokeMethod('release');
  }
  

  // This listens to the 'OnFeedSamples' event from the native side and triggers a callback
  static void setOnFeedSamplesCallback(Function(int) callback) {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (_logLevel.index >= LogLevel.standard.index) {
        String func = '[[ ${call.method} ]]';
        String result = call.arguments.toString();
        print("[PCM] $func result: $result");
      }
      switch (call.method) {
        case 'OnFeedSamples':
          int remainingSamples = call.arguments["remaining_samples"];
          callback(remainingSamples);
          break;
        default:
          print('Method not implemented');
      }
    });
  }
}
