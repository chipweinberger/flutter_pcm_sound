import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound_platform_interface.dart';

/// Web implementation of the FlutterPcmSound plugin.
class FlutterPcmSoundWeb extends FlutterPcmSoundPlatform {
  FlutterPcmSoundWeb();

  static void registerWith(Registrar registrar) {
    FlutterPcmSoundPlatform.instance = FlutterPcmSoundWeb();
  }

  @override
  Future<void> setLogLevel(LogLevel level) async {
    throw UnimplementedError('setLogLevel() has not been implemented for web.');
  }

  @override
  Future<void> setup({
    required int sampleRate,
    required int channelCount,
    IosAudioCategory iosAudioCategory = IosAudioCategory.playback
  }) async {
    throw UnimplementedError('setup() has not been implemented for web.');
  }

  @override
  Future<void> feed(Uint8List buffer) async {
    throw UnimplementedError('feed() has not been implemented for web.');
  }

  @override
  Future<void> setFeedThreshold(int threshold) async {
    throw UnimplementedError('setFeedThreshold() has not been implemented for web.');
  }

  @override
  Future<void> release() async {
    throw UnimplementedError('release() has not been implemented for web.');
  }

  @override
  void setFeedCallback(Function(int)? callback) {
    throw UnimplementedError('setFeedCallback() has not been implemented for web.');
  }
}