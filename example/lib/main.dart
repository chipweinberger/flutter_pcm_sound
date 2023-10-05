import 'dart:typed_data'; // for Uint8List
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:raw_sound/raw_sound_player.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Buffer size of the underlying audio track (Android only)
  static int bufferSize = 4096 << 4;
  // Number of channels, either 1 or 2
  static int nChannels = 1;
  // Sample rate for playback in Hz
  static int sampleRate = 16000;

  // Frequency of the desired tone in Hz
  static double freq = 440.0;
  // Period of the desired tone in sec
  static double period = 1.0 / freq;
  // Volume of the desired tone in the range of 0.0 (min) to 1.0 (max)
  static double volume = 0.5;

  // Player instance to play raw PCM (16-bit integer) audio data
  final _playerPCMI16 = RawSoundPlayer();
  // Player instance to play raw PCM (32-bit float) audio data
  final _playerPCMF32 = RawSoundPlayer();

  @override
  void initState() {
    super.initState();
    //  release any initialized player instances
    _playerPCMI16
        .initialize(
      bufferSize: bufferSize,
      nChannels: nChannels,
      sampleRate: sampleRate,
      pcmType: RawSoundPCMType.PCMI16,
    )
        .then((value) {
      setState(() {
        // Trigger rebuild to update UI
      });
    });
    _playerPCMF32
        .initialize(
      bufferSize: bufferSize,
      nChannels: nChannels,
      sampleRate: sampleRate,
      pcmType: RawSoundPCMType.PCMF32,
    )
        .then((value) {
      setState(() {
        // Trigger rebuild to update UI
      });
    });
  }

  @override
  void dispose() {
    // Finally release any initialized player instances
    _playerPCMI16.release();
    _playerPCMF32.release();
    super.dispose();
  }

  Future<void> _playPCMI16() async {
    if (_playerPCMI16.isPlaying) {
      return;
    }
    await _playerPCMI16.play();
    setState(() {
      // Trigger rebuild to update UI
    });
    // Continuously feed the player until the playback is paused/stopped
    final dataBlock = _genPCMI16DataBlock(nPeriods: 20);
    while (_playerPCMI16.isPlaying) {
      await _playerPCMI16.feed(dataBlock);
    }
  }

  Future<void> _pausePCMI16() async {
    await _playerPCMI16.pause();
    setState(() {
      // Trigger rebuild to update UI
    });
  }

  Future<void> _playPCMF32() async {
    if (_playerPCMF32.isPlaying) {
      return;
    }
    await _playerPCMF32.play();
    setState(() {
      // Trigger rebuild to update UI
    });
    // Continuously feed the player until the playback is paused/stopped
    final dataBlock = _genPCMF32DataBlock(nPeriods: 20);
    while (_playerPCMF32.isPlaying) {
      await _playerPCMF32.feed(dataBlock);
    }
  }

  Future<void> _pausePCMF32() async {
    await _playerPCMF32.pause();
    setState(() {
      // Trigger rebuild to update UI
    });
  }

  // Generate PCM (16-bit integer) audio data
  Uint8List _genPCMI16DataBlock({int nPeriods = 1}) {
    final nFramesPerPeriod = (period * sampleRate).toInt();
    debugPrint('nFrames / period: $nFramesPerPeriod');
    final step = math.pi * 2 / nFramesPerPeriod;
    // Fill the dataBlockPerPeriod with one period of the sine wave
    final dataBlockPerPeriod =
        ByteData(nFramesPerPeriod << 1 /* one int16 is made of 2 bytes */);
    for (int i = 0; i < nFramesPerPeriod; i++) {
      // amplitude is in the range of -32767 to 32767
      final value = (math.sin(step * i) * volume * 32767).toInt();
      dataBlockPerPeriod.setInt16(
          i << 1, value, Endian.host /* native endianness */);
    }
    // Repeat dataBlockPerPeriod nPeriods times
    final dataBlock = <int>[];
    for (int i = 0; i < nPeriods; i++) {
      dataBlock.addAll(dataBlockPerPeriod.buffer.asUint8List());
    }
    debugPrint('dataBlock nBytes: ${dataBlock.length}');
    return Uint8List.fromList(dataBlock);
  }

  // Generate PCM (32-bit float) audio data
  Uint8List _genPCMF32DataBlock({int nPeriods = 1}) {
    final nFramesPerPeriod = (period * sampleRate).toInt();
    debugPrint('nFrames / period: $nFramesPerPeriod');
    final step = math.pi * 2 / nFramesPerPeriod;
    // Fill the dataBlockPerPeriod with one period of the sine wave
    final dataBlockPerPeriod =
        ByteData(nFramesPerPeriod << 2 /* one float32 is made of 4 bytes */);
    for (int i = 0; i < nFramesPerPeriod; i++) {
      // amplitude is in the range of -1.0 to 1.0
      final value = math.sin(step * i) * volume;
      dataBlockPerPeriod.setFloat32(
          i << 2, value, Endian.host /* native endianness */);
    }
    // Repeat dataBlockPerPeriod nPeriods times
    final dataBlock = <int>[];
    for (int i = 0; i < nPeriods; i++) {
      dataBlock.addAll(dataBlockPerPeriod.buffer.asUint8List());
    }
    debugPrint('dataBlock nBytes: ${dataBlock.length}');
    return Uint8List.fromList(dataBlock);
  }

  Widget build(BuildContext context) {
    debugPrint('PlayerPCMI16 is inited? ${_playerPCMI16.isInited}');
    debugPrint('PlayerPCMF32 is inited? ${_playerPCMF32.isInited}');

    if (!_playerPCMI16.isInited || !_playerPCMF32.isInited) {
      return Container();
    }

    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.grey,
      ),
      home: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text('Raw Sound Plugin Example App'),
        ),
        body: Column(
          children: [
            Card(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(_playerPCMI16.isPlaying
                        ? Icons.stop
                        : Icons.play_arrow),
                    onPressed: () {
                      _playerPCMI16.isPlaying ? _pausePCMI16() : _playPCMI16();
                    },
                  ),
                  Text('Test PCMI16 (16-bit Integer)'),
                ],
              ),
            ),
            Card(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(_playerPCMF32.isPlaying
                        ? Icons.stop
                        : Icons.play_arrow),
                    onPressed: () {
                      _playerPCMF32.isPlaying ? _pausePCMF32() : _playPCMF32();
                    },
                  ),
                  Text('Test PCMF32 (32-bit Float)'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}