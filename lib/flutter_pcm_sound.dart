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

  static Function(int)? onFeedSamplesCallback;

  static LogLevel _logLevel = LogLevel.standard;

  static Future<void> setLogLevel(int level) async {
    return await _invokeMethod('setLogLevel', {'log_level': level});
  }

  static Future<void> setup(int sampleRate, int numChannels) async {
    return await _invokeMethod('setup', {
      'sample_rate': sampleRate,
      'num_channels': numChannels,
    });
  }

  static Future<void> play() async {
    return await _invokeMethod('play');
  }

  static Future<void> pause() async {
    return await _invokeMethod('pause');
  }

  static Future<void> stop() async {
    return await _invokeMethod('stop');
  }

  static Future<void> clear() async {
    return await _invokeMethod('clear');
  }

  static Future<void> feed(Uint8List buffer) async {
    return await _invokeMethod('feed', {'buffer': buffer});
  }

  static Future<void> setFeedThreshold(int threshold) async {
    return await _invokeMethod('setFeedThreshold', {'feed_threshold': threshold});
  }

  static Future<void> release() async {
    return await _invokeMethod('release');
  }

  static Future<T?> _invokeMethod<T>(String method, [dynamic arguments]) async {
    if (_logLevel.index >= LogLevel.standard.index) {
      String args = '';
      if (method == 'feed') {
        Uint8List data = arguments['buffer'];
        if (data.lengthInBytes > 6) {
          args = '(${data.lengthInBytes~/2} samples) ${data.sublist(0, 6)} ...';
        } else {
          args = '(${data.lengthInBytes~/2} samples) $data';
        }
      } else if (arguments != null) {
        args = arguments.toString();
      }
      print("[PCM] invoke: $method $args");
    }
    return await _channel.invokeMethod(method, arguments);
  }

  static Future<dynamic> _methodCallHandler(MethodCall call) async {
    if (_logLevel.index >= LogLevel.standard.index) {
      String func = '[[ ${call.method} ]]';
      String args = call.arguments.toString();
      print("[PCM] $func $args");
    }
    switch (call.method) {
      case 'OnFeedSamples':
        int remainingSamples = call.arguments["remaining_samples"];
        if (onFeedSamplesCallback != null) {
          onFeedSamplesCallback!(remainingSamples);
        }
        break;
      default:
        print('Method not implemented');
    }
  }

  // This listens to the 'OnFeedSamples' event from the native side and triggers a callback
  static void setFeedCallback(Function(int) callback) {
    onFeedSamplesCallback = callback;
    _channel.setMethodCallHandler(_methodCallHandler);
  }
}
