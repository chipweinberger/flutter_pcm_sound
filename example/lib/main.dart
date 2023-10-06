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
  int periodIdx = 0;
  int remainingFrames = 0;
  bool stopFeeding = false;

  @override
  void initState() {
    super.initState();
    FlutterPcmSound.setLogLevel(LogLevel.none);
    FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
    FlutterPcmSound.setFeedThreshold(8000);
    FlutterPcmSound.setFeedCallback(onFeed);
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<double> get scale {
    List<double> c = [261.63, 294.33, 327.03, 348.83, 392.44, 436.05, 490.55, 523.25];
    return c + c.reversed.toList();
  }

  int periodsForNote(double freq, double noteDuration) {
    int nFramesPerPeriod = (sampleRate / freq).round();
    int totalFramesForDuration = (noteDuration * sampleRate).round();
    return totalFramesForDuration ~/ nFramesPerPeriod;
  }

  int periodsForScale(double noteDuration) {
    int total = 0;
    for (double freq in scale) {
      total += periodsForNote(freq, noteDuration);
    }
    return total;
  }

  double note(int periodIdx, double noteDuration) {
    int accum = 0;
    for (int n = 0; n < scale.length; n++) {
      accum += periodsForNote(scale[n], noteDuration);
      if (periodIdx < accum) {
        return scale[n];
      }
    }
    return scale.last;
  }

  void onFeed(int remainingFrames) async {
    this.remainingFrames = remainingFrames;
    setState(() {});
    if (stopFeeding == false) {
      List<int> frames = [];
      // feed 100 more periods
      for (int i = 0; i < 100; i++) {
        double noteDuration = 0.20;
        periodIdx %= periodsForScale(noteDuration);
        double freq = note(periodIdx, noteDuration);
        frames += sineWave(periods: 1, sampleRate: sampleRate, freq: freq);
        periodIdx++;
      }
      await FlutterPcmSound.feed(PcmArrayInt16.fromList(frames));
    }
  }

  List<int> sineWave({int periods = 1, int sampleRate = 44100, double freq = 440, double volume = 0.5}) {
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
                  stopFeeding = false;
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
                  stopFeeding = true;
                },
                child: Text('Stop Feeding'),
              ),
              ElevatedButton(
                onPressed: () {
                  FlutterPcmSound.stop();
                  setState(() {
                    periodIdx = 0;
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
