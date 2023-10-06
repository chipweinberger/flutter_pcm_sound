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
  int remainingFrames = 0;
  bool stopFeeding = false;
  MajorScale scale = MajorScale(sampleRate: sampleRate, noteDuration: 0.20);

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

  void onFeed(int remainingFrames) async {
    this.remainingFrames = remainingFrames;
    setState(() {});
    if (stopFeeding == false) {
      List<int> frames = scale.generate(periods: 100);
      await FlutterPcmSound.feed(PcmArrayInt16.fromList(frames));
    }
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
                    scale.reset();
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
