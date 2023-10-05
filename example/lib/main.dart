import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

const int sampleRate = 44100;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PcmSoundApp();
  }
}

class PcmSoundApp extends StatefulWidget {
  @override
  _PcmSoundAppState createState() => _PcmSoundAppState();
}

class _PcmSoundAppState extends State<PcmSoundApp> {
  @override
  void initState() {
    super.initState();
    FlutterPcmSound.setup(sampleRate, 1);
    FlutterPcmSound.setOnFeedSamplesCallback(onFeedSamples);
  }

  @override
  void dispose() {
    FlutterPcmSound.release();
    super.dispose();
  }

  void onFeedSamples(int remainingSamples) async {
    final frame = sineWave(periods: 20, sampleRate: sampleRate);
    await FlutterPcmSound.feed(Uint8List.fromList(frame));
  }

  Future<void> _play() async {
    await FlutterPcmSound.play();
  }

  Future<void> _pause() async {
    await FlutterPcmSound.pause();
  }

  List<int> sineWave({int periods = 1, int sampleRate = 44100, double freq = 440, double volume = 0.5}) {
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

  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.grey,
      ),
      home: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text('Flutter PCM Sound'),
        ),
        body: Column(
          children: [
            Card(
              child: Row(
                children: [
                  TextButton(
                    onPressed: _play,
                    child: Text('Play'),
                  ),
                  TextButton(
                    onPressed: _pause,
                    child: Text('Pause'),
                  ),
                  Text('Test PCM Playback'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
