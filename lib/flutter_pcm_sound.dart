import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_pcm_sound/flutter_pcm_sound_platform_interface.dart';

export 'flutter_pcm_sound_platform_interface.dart' show LogLevel, IosAudioCategory;

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
    return FlutterPcmSoundPlatform.instance.feed(buffer.bytes.buffer.asUint8List());
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

class PcmArrayInt16 {
  final ByteData bytes;

  PcmArrayInt16({required this.bytes});

  factory PcmArrayInt16.zeros({required int count}) {
    Uint8List list = Uint8List(count * 2);
    return PcmArrayInt16(bytes: list.buffer.asByteData());
  }

  factory PcmArrayInt16.empty() {
    return PcmArrayInt16.zeros(count: 0);
  }

  factory PcmArrayInt16.fromList(List<int> list) {
    var byteData = ByteData(list.length * 2);
    for (int i = 0; i < list.length; i++) {
      byteData.setInt16(i * 2, list[i], Endian.host);
    }
    return PcmArrayInt16(bytes: byteData);
  }

  operator [](int idx) {
    int vv = bytes.getInt16(idx * 2, Endian.host);
    return vv;
  }

  operator []=(int idx, int value) {
    return bytes.setInt16(idx * 2, value, Endian.host);
  }
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
