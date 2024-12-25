import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_pcm_sound/flutter_pcm_sound_platform_interface.dart';
import 'package:flutter_pcm_sound/pcm_array_int16.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart';

// JS interop types
@JS('AudioContext')
external JSFunction get _audioContextConstructor;

@JS('AudioWorkletNode')
external JSFunction get _audioWorkletNodeConstructor;

@JS('Blob')
external JSFunction get _blobConstructor;

@JS('URL.createObjectURL')
external String _createObjectURL(JSObject blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(String url);

// Extension types
extension type AudioContext._(JSObject _) implements JSObject {
  external factory AudioContext({int? sampleRate});
  external AudioWorklet get audioWorklet;
  external JSAny get destination;
  external JSString get state;
  external JSPromise get resume;
  external JSPromise get close;
}

extension type AudioWorklet._(JSObject _) implements JSObject {
  external JSPromise addModule(String moduleURL);
}

extension type AudioWorkletNode._(JSObject _) implements JSObject {
  external factory AudioWorkletNode(AudioContext context, String name, JSObject options);
  external MessagePort get port;
  external void connect(JSAny destination);
  external void disconnect();
}

extension type MessagePort._(JSObject _) implements JSObject {
  external void postMessage(JSAny message, [JSArray? transfer]);
  external set onmessage(JSFunction? callback);
}

/// Web implementation of the flutter_pcm_sound plugin.
class FlutterPcmSoundWeb extends FlutterPcmSoundPlatform {
  static void registerWith(Registrar registrar) {
    FlutterPcmSoundPlatform.instance = FlutterPcmSoundWeb();
  }

  AudioContext? _audioContext;
  AudioWorkletNode? _workletNode;
  Function(int)? _onFeedCallback;
  LogLevel _logLevel = LogLevel.standard;

  @override
  Future<void> setLogLevel(LogLevel level) async {
    _logLevel = level;
    _log('Log level set to: $level');
  }

  @override
  Future<void> setup({
    required int sampleRate,
    required int channelCount,
    IosAudioCategory iosAudioCategory = IosAudioCategory.playback
  }) async {
    try {
      print('Setting up PCM Sound with sample rate: $sampleRate, channel count: $channelCount');
      // Create AudioContext
      if (_audioContext == null) {
        final ctx = _audioContextConstructor.callAsConstructor({
          'sampleRate': sampleRate
        }.jsify());
        if (ctx == null) throw Exception('Failed to create AudioContext');
        _audioContext = ctx as AudioContext;
      }

      // Get state as string and compare
      final state = _audioContext!.state.toDart as String;
      if (state == 'suspended') {
        await _audioContext!.resume.toDart;
      }
      print('AudioContext state: $state');

      // Create worklet processor code
      final processorCode = _generateProcessorCode();
      final blob = _createBlob(processorCode);
      final url = _createObjectURL(blob);
      if (url.isEmpty) throw Exception('Failed to create object URL');

      try {
        // Load the worklet module
        await _audioContext!.audioWorklet.addModule(url).toDart;
      } finally {
        // Always cleanup URL
        _revokeObjectURL(url);
      }

      // Create worklet node
      final options = _createWorkletOptions(channelCount);
      final node = _audioWorkletNodeConstructor.callAsConstructor(
          _audioContext,
          'pcm-player'.toJS,
          options
      );

      if (node == null) throw Exception('Failed to create AudioWorkletNode');
      print('Worklet node created: $node');
      _workletNode = node as AudioWorkletNode;

      // Setup message handling
      _setupMessageHandling();

      // Connect to destination
      _workletNode!.connect(_audioContext!.destination);

      // Send initial configuration
      final configMessage = _createMessageData('config', {
        'channelCount': channelCount,
      });
      _workletNode!.port.postMessage(configMessage);

      _log('PCM Sound initialized');
    } catch (e) {
      _log('Failed to initialize PCM Sound: $e', LogLevel.error);
      await release();
      rethrow;
    }
  }

  @override
  Future<void> feed(PcmArrayInt16 buffer) async {
    if (_workletNode == null) {
      throw Exception('PCM Sound not initialized');
    }

    final bufferLength = buffer.bytes.lengthInBytes;
    _log('Feeding $bufferLength bytes');

    if (bufferLength > 0) {
      try {
        // Get the raw buffer data
        final rawBuffer = buffer.bytes.buffer.asUint8List(
            buffer.bytes.offsetInBytes,
            buffer.bytes.lengthInBytes
        );
        _log('Raw buffer created with ${rawBuffer.length} bytes');

        // Create ArrayBuffer for transfer
        final jsArray = Uint8List.fromList(rawBuffer);
        _log('Created transferable array with ${jsArray.length} bytes');

        // Debug: Log first few samples
        final sampleDebug = StringBuffer('First few samples: ');
        for (var i = 0; i < min(5, bufferLength ~/ 2); i++) {
          if (i > 0) sampleDebug.write(', ');
          sampleDebug.write(buffer.bytes.getInt16(i * 2, Endian.little));
        }
        _log(sampleDebug.toString());

        // Create message with buffer
        final message = _createMessageData('feed', {
          'buffer': jsArray.buffer
        });

        // Post message to worklet node
        _workletNode!.port.postMessage(message);

      } catch (e, stack) {
        _log('Error in feed: $e\n$stack', LogLevel.error);
        rethrow;
      }
    } else {
      _log('Warning: Received empty buffer', LogLevel.error);
    }
  }

  @override
  Future<void> setFeedThreshold(int threshold) async {
    if (_workletNode == null) return;

    final message = _createMessageData('config', {
      'feedThreshold': threshold
    });

    _workletNode!.port.postMessage(message);
  }

  @override
  void setFeedCallback(Function(int)? callback) {
    _onFeedCallback = callback;
  }

  @override
  Future<void> release() async {
    if (_workletNode != null) {
      _workletNode!.disconnect();
      _workletNode = null;
    }

    if (_audioContext != null) {
      try {
        await _audioContext!.close.toDart;
      } catch (e) {
        _log('Error closing AudioContext: $e', LogLevel.error);
      }
      _audioContext = null;
    }

    _onFeedCallback = null;
    _log('PCM Sound released');
  }

  // Private helper methods
  JSObject _createWorkletOptions(int channelCount) {
    return {
      'numberOfInputs': 0,
      'numberOfOutputs': 1,
      'outputChannelCount': [channelCount]
    }.jsify() as JSObject;
  }

  JSObject _createMessageData(String type, Map<String, dynamic> data) {
    return {
      'type': type,
      'data': data
    }.jsify() as JSObject;
  }

  void _setupMessageHandling() {
    _workletNode!.port.onmessage = ((JSAny messageEvent) {
      try {
        final event = messageEvent as MessageEvent;
        // First convert to Map<Object?, Object?>
        final rawData = event.data.dartify() as Map<Object?, Object?>;

        // Then safely convert to Map<String, dynamic>
        final data = Map<String, dynamic>.fromEntries(
            rawData.entries.map((entry) => MapEntry(
                entry.key?.toString() ?? '',
                entry.value
            ))
        );

        //print('Received message: $data');

        if (data['type'] == 'needMore' && _onFeedCallback != null) {
          // Safely cast the remaining value
          final remaining = (data['remaining'] as num).toInt();
          _onFeedCallback!(remaining);
        }
      } catch (e, stack) {
        _log('Error processing message: $e\n$stack', LogLevel.error);
      }
    }).toJS;
  }

  JSObject _createBlob(String content) {
    final array = JSArray<JSString>.withLength(1);
    array[0] = content.toJS;
    final options = {'type': 'text/javascript'}.jsify() as JSObject;
    return _blobConstructor.callAsConstructor(array, options);
  }

  String _generateProcessorCode() {
    return '''
    class PCMPlayer extends AudioWorkletProcessor {
      constructor() {
        super();
        console.log('PCMPlayer: Initialized from _generateProcessorCode');
        
        this.buffer = new Float32Array(0);
        this.channelCount = 1;
        this.feedThreshold = 4096;
        this.sampleCount = 0;
        
        this.port.onmessage = (event) => {
          const {type, data} = event.data;
          console.log(`PCMPlayer: Received event of type: \${type}`);
          
          if (type === 'config') {
            console.log('PCMPlayer: Received config:', data);
            if (data.channelCount != null) {
              this.channelCount = data.channelCount;
            }
            if (data.feedThreshold != null) {
              this.feedThreshold = data.feedThreshold;
            }
          } else if (type === 'feed') {
            console.log('PCMPlayer: Received feed data of length:', data.buffer.byteLength);
            
            // Create DataView for proper byte handling
            const dataView = new DataView(data.buffer);
            const float32Data = new Float32Array(data.buffer.byteLength / 2);
            
            // Convert Int16 to Float32 with proper endianness
            for (let i = 0; i < float32Data.length; i++) {
              const int16Sample = dataView.getInt16(i * 2, true); // true = little-endian
              float32Data[i] = int16Sample / 32768.0;
            }
            
            // Create new buffer with combined data
            const newBuffer = new Float32Array(this.buffer.length + float32Data.length);
            newBuffer.set(this.buffer);
            newBuffer.set(float32Data, this.buffer.length);
            this.buffer = newBuffer;
            
            console.log('PCMPlayer: Buffer state after feed:', {
              totalSamples: this.buffer.length,
              nonZeroSamples: this.buffer.reduce((count, sample) => count + (sample !== 0 ? 1 : 0), 0)
            });
          }
        };
      }

      process(inputs, outputs) {
        const output = outputs[0];
        const channelCount = Math.min(output.length, this.channelCount);
        const samplesPerChannel = output[0].length;
        
        this.sampleCount += samplesPerChannel;
        
        // Log processing state periodically
        if (this.sampleCount % (sampleRate / 2) === 0) { // Log every 0.5 seconds
          console.log('PCMPlayer: Processing state:', {
            bufferLength: this.buffer.length,
            channelCount,
            samplesPerChannel,
            totalProcessed: this.sampleCount
          });
        }

        if (this.buffer.length < this.feedThreshold) {
          this.port.postMessage({
            type: 'needMore',
            remaining: this.buffer.length
          });
        }

        if (this.buffer.length === 0) {
          for (let channel = 0; channel < channelCount; channel++) {
            output[channel].fill(0);
          }
          return true;
        }

        let didOutput = false;
        for (let channel = 0; channel < channelCount; channel++) {
          const outputChannel = output[channel];
          
          if (this.buffer.length >= outputChannel.length) {
            outputChannel.set(this.buffer.subarray(0, outputChannel.length));
            this.buffer = this.buffer.subarray(outputChannel.length);
            didOutput = true;
          } else {
            outputChannel.set(this.buffer);
            outputChannel.fill(0, this.buffer.length);
            this.buffer = new Float32Array(0);
            didOutput = true;
          }
        }

        if (didOutput && this.sampleCount % (sampleRate / 10) === 0) {
          console.log('PCMPlayer: Audio output active:', {
            remainingBuffer: this.buffer.length,
            didOutput,
            timestamp: currentTime
          });
        }

        return true;
      }
    }

    registerProcessor('pcm-player', PCMPlayer);
  ''';
  }

  void _log(String message, [LogLevel level = LogLevel.standard]) {
    if (level.index <= _logLevel.index) {
      print('[PCM${level == LogLevel.error ? ' ERROR' : ''}] $message');
    }
  }
}