import 'dart:math' as math;

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
  int fed = 0;
  int remainingFrames = 0;

  @override
  void initState() {
    super.initState();
    FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1, androidBufferMultiply: 3);
    FlutterPcmSound.setFeedThreshold(3000);
    FlutterPcmSound.setFeedCallback(onFeed);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void onFeed(int remainingFrames) async {
    this.remainingFrames = remainingFrames;
    setState(() {});
    int step = (fed ~/ (sampleRate / 2)) % 14;
    int freq = 200 + (step < 7 ? 50 * step : 300 - (step - 7) * 50);
    List<int> frame = sineWave(periods: 40, sampleRate: sampleRate, freq: freq);
    await FlutterPcmSound.feed(PcmArrayInt16.fromList(frame));
    fed += frame.length;
  }

  List<int> sineWave({int periods = 1, int sampleRate = 44100, int freq = 440, double volume = 0.5}) {
    final period = 1.0 / freq;
    final nFramesPerPeriod = (period * sampleRate).toInt();
    final totalFrames = nFramesPerPeriod * periods;
    final step = math.pi * 2 / nFramesPerPeriod;

    List<int> data = List.filled(totalFrames, 0);

    for (int i = 0; i < totalFrames; i++) {
      data[i] = (math.sin(step * (i % nFramesPerPeriod)) * volume * 32767).toInt();
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
                    fed = 0;
                    remainingFrames = 0;
                  });
                },
                child: Text('Stop'),
              ),
              ElevatedButton(
                onPressed: () {
                  FlutterPcmSound.clear();
                  setState(() {
                    remainingFrames = 0;
                  });
                },
                child: Text('Clear'),
              ),
              Text('$remainingFrames Remaining Samples')
            ],
          ),
        ),
      ),
    );
  }
}
