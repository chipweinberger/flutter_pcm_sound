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
  int remainingSamples = 0;

  @override
  void initState() {
    super.initState();
    FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
    FlutterPcmSound.setFeedThreshold(8000);
    FlutterPcmSound.setFeedCallback(onFeed);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void onFeed(int remainingSamples) async {
    this.remainingSamples = remainingSamples;
    setState(() {});
    int step = (DateTime.now().millisecondsSinceEpoch ~/ 500) % 14;
    int freq = 200 + (step < 7 ? 50 * step : 300 - (step - 7) * 50);
    final frame = sineWave(periods: 20, sampleRate: sampleRate, freq: freq);
    await FlutterPcmSound.feed(Uint8List.fromList(frame));
  }

  List<int> sineWave({int periods = 1, int sampleRate = 44100, int freq = 440, double volume = 0.5}) {
    final period = 1.0 / freq;
    final nFramesPerPeriod = (period * sampleRate).toInt();
    final totalFrames = nFramesPerPeriod * periods;
    final step = math.pi * 2 / nFramesPerPeriod;

    List<int> data = List<int>.filled(totalFrames * 2, 0);

    for (int i = 0; i < totalFrames; i++) {
      final value = (math.sin(step * (i % nFramesPerPeriod)) * volume * 32767).toInt();
      data[i * 2 + 0] = value & 0x00FF; // little endian
      data[i * 2 + 1] = (value & 0xFF00) >> 8;
    }

    return data;
  }

  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text('Flutter PCM Sound'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () {
                  FlutterPcmSound.play();
                },
                child: Text('Play'),
              ),
              ElevatedButton(
                onPressed: () {
                  FlutterPcmSound.pause();
                },
                child: Text('Pause'),
              ),
              ElevatedButton(
                onPressed: () {
                  FlutterPcmSound.stop();
                  setState(() {
                    remainingSamples = 0;
                  });
                },
                child: Text('Stop'),
              ),
              ElevatedButton(
                onPressed: () {
                  FlutterPcmSound.clear();
                  setState(() {
                    remainingSamples = 0;
                  });
                },
                child: Text('Clear'),
              ),
              Text('$remainingSamples Remaining Samples')
            ],
          ),
        ),
      ),
    );
  }
}
