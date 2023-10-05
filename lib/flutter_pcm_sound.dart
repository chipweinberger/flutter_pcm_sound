
import 'dart:async';
import 'package:flutter/services.dart';

class FlutterPcmSound {
  static const MethodChannel _channel = const MethodChannel('flutter_pcm_sound/methods');

  Future<bool> setLogLevel(int level) async {
    return await _channel.invokeMethod('setLogLevel', {'log_level': level});
  }

  Future<bool> setup(int sampleRate, int numChannels) async {
    return await _channel.invokeMethod('setup', {
      'sample_rate': sampleRate,
      'num_channels': numChannels,
    });
  }

  Future<bool> play() async {
    return await _channel.invokeMethod('play');
  }

  Future<bool> pause() async {
    return await _channel.invokeMethod('pause');
  }

  Future<bool> stop() async {
    return await _channel.invokeMethod('stop');
  }

  Future<bool> clear() async {
    return await _channel.invokeMethod('clear');
  }

  Future<bool> feed(List<int> buffer) async {
    return await _channel.invokeMethod('feed', {'buffer': buffer});
  }

  Future<bool> setFeedThreshold(int threshold) async {
    return await _channel.invokeMethod('setFeedThreshold', {'feed_threshold': threshold});
  }

  Future<int> getPendingSamplesCount() async {
    return await _channel.invokeMethod('getPendingSamplesCount');
  }

  Future<bool> release() async {
    return await _channel.invokeMethod('release');
  }

  // This listens to the 'OnFeedSamples' event from the native side and triggers a callback
  void setOnFeedSamplesCallback(Function(dynamic response) callback) {
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'OnFeedSamples':
          callback(call.arguments);
          break;
        default:
          print('Method not implemented');
      }
    });
  }
}
