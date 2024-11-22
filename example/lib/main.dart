import 'dart:io';

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
  int _remainingFrames = 0;
  MajorScale scale = MajorScale(sampleRate: sampleRate, noteDuration: 0.20);

  @override
  void initState() {
    super.initState();
    FlutterPcmSound.setLogLevel(LogLevel.verbose);
    FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
    if (Platform.isAndroid) {
      FlutterPcmSound.setFeedThreshold(sampleRate ~/ 15);
    } else {
      FlutterPcmSound.setFeedThreshold(sampleRate ~/ 30);
    }
    FlutterPcmSound.setFeedCallback(_onFeed);
  }

  @override
  void dispose() {
    super.dispose();
    FlutterPcmSound.release();
  }

  void _onFeed(int remainingFrames) async {
    setState(() {
      _remainingFrames = remainingFrames;
    });
    List<int> frames = scale.generate(periods: 20);
    await FlutterPcmSound.feed(PcmArrayInt16.fromList(frames));
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
                  FlutterPcmSound.setFeedCallback(_onFeed);
                  _onFeed(0); // start feeding
                },
                child: Text('Play'),
              ),
              ElevatedButton(
                onPressed: () {
                  FlutterPcmSound.setFeedCallback(null); // stop
                  setState(() {
                    _remainingFrames = 0;
                  });
                },
                child: Text('Stop'),
              ),
              Text('$_remainingFrames Remaining Frames')
            ],
          ),
        ),
      ),
    );
  }
}
