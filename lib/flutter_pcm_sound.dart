import 'dart:math' as math;
import 'package:flutter_pcm_sound/flutter_pcm_sound_platform_interface.dart';
import 'package:flutter_pcm_sound/pcm_array_int16.dart';

export 'package:flutter_pcm_sound/pcm_array_int16.dart';
export 'flutter_pcm_sound_platform_interface.dart';

class FlutterPcmSound {
  static Future<void> setLogLevel(LogLevel level) {
    return FlutterPcmSoundPlatform.instance.setLogLevel(level);
  }

  static Future<void> setup({
    required int sampleRate,
    required int channelCount,
    IosAudioCategory iosAudioCategory = IosAudioCategory.playback
  }) {
    return FlutterPcmSoundPlatform.instance.setup(
      sampleRate: sampleRate,
      channelCount: channelCount,
      iosAudioCategory: iosAudioCategory,
    );
  }

  static Future<void> feed(PcmArrayInt16 buffer) {
    return FlutterPcmSoundPlatform.instance.feed(buffer);
  }

  static Future<void> setFeedThreshold(int threshold) {
    return FlutterPcmSoundPlatform.instance.setFeedThreshold(threshold);
  }

  static void setFeedCallback(Function(int)? callback) {
    FlutterPcmSoundPlatform.instance.setFeedCallback(callback);
  }

  static void start() {
    assert(FlutterPcmSoundPlatform.instance != null);
    FlutterPcmSoundPlatform.instance.setFeedCallback((remainingFrames) {
      onFeedSamplesCallback?.call(remainingFrames);
    });
  }

  static Future<void> release() {
    return FlutterPcmSoundPlatform.instance.release();
  }

  static Function(int)? onFeedSamplesCallback;
}

// for testing
class MajorScale {
  int _periodCount = 0;
  int sampleRate = 44100;
  double noteDuration = 0.25;

  MajorScale({required this.sampleRate, required this.noteDuration});

  // C Major Scale (Just Intonation)
  List<double> get scale {
    List<double> c = [261.63, 294.33, 327.03, 348.83, 392.44, 436.05, 490.55, 523.25];
    return [c[0]] + c + c.reversed.toList().sublist(0, c.length - 1);
  }

  // total periods needed to play the entire note
  int _periodsForNote(double freq) {
    int nFramesPerPeriod = (sampleRate / freq).round();
    int totalFramesForDuration = (noteDuration * sampleRate).round();
    return totalFramesForDuration ~/ nFramesPerPeriod;
  }

  // total periods needed to play the whole scale
  int get _periodsForScale {
    int total = 0;
    for (double freq in scale) {
      total += _periodsForNote(freq);
    }
    return total;
  }

  // what note are we currently playing
  int get noteIdx {
    int accum = 0;
    for (int n = 0; n < scale.length; n++) {
      accum += _periodsForNote(scale[n]);
      if (_periodCount < accum) {
        return n;
      }
    }
    return scale.length - 1;
  }

  // generate a sine wave
  List<int> cosineWave({int periods = 1, int sampleRate = 44100, double freq = 440, double volume = 0.5}) {
    final period = 1.0 / freq;
    final nFramesPerPeriod = (period * sampleRate).toInt();
    final totalFrames = nFramesPerPeriod * periods;
    final step = math.pi * 2 / nFramesPerPeriod;
    List<int> data = List.filled(totalFrames, 0);
    for (int i = 0; i < totalFrames; i++) {
      data[i] = (math.cos(step * (i % nFramesPerPeriod)) * volume * 32768).toInt() - 16384;
    }
    return data;
  }

  void reset() {
    _periodCount = 0;
  }

  // generate the next X periods of the major scale
  List<int> generate({required int periods, double volume = 0.5}) {
    List<int> frames = [];
    for (int i = 0; i < periods; i++) {
      _periodCount %= _periodsForScale;
      frames += cosineWave(periods: 1, sampleRate: sampleRate, freq: scale[noteIdx], volume: volume);
      _periodCount++;
    }
    return frames;
  }
}
