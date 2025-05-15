package com.lib.flutter_pcm_sound;

import android.os.Build;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.AudioAttributes;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import androidx.annotation.NonNull;

import java.util.Map;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.io.StringWriter;
import java.io.PrintWriter;
import java.nio.ByteBuffer;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * FlutterPcmSoundPlugin implements a "one pedal" PCM sound playback mechanism.
 * Playback starts automatically when samples are fed and stops when no more samples are available.
 */
public class FlutterPcmSoundPlugin implements
    FlutterPlugin,
    MethodChannel.MethodCallHandler
{
    private static final String CHANNEL_NAME = "flutter_pcm_sound/methods";
    private static final int MAX_FRAMES_PER_BUFFER = 200;

    private MethodChannel mMethodChannel;
    private Handler mainThreadHandler = new Handler(Looper.getMainLooper());
    private Thread playbackThread;
    private volatile boolean mShouldCleanup = false;

    private AudioTrack mAudioTrack;
    private int mNumChannels;
    private int mMinBufferSize;
    private boolean mDidSetup = false;

    private long mFeedThreshold = 8000;
    private volatile boolean mDidInvokeFeedCallback = false;
    private volatile boolean mDidSendZero = false;

    // Thread-safe queue for storing audio samples
    private final LinkedBlockingQueue<ByteBuffer> mSamples = new LinkedBlockingQueue<>();

    // Log level enum (kept for potential future use)
    private enum LogLevel {
        NONE,
        ERROR,
        STANDARD,
        VERBOSE
    }

    private LogLevel mLogLevel = LogLevel.VERBOSE;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        BinaryMessenger messenger = binding.getBinaryMessenger();
        mMethodChannel = new MethodChannel(messenger, CHANNEL_NAME);
        mMethodChannel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        mMethodChannel.setMethodCallHandler(null);
        cleanup();
    }

    @Override
    @SuppressWarnings("deprecation") // Needed for compatibility with Android < 23
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "setLogLevel": {
                    result.success(true);
                    break;
                }
                case "setup": {
                    int sampleRate = call.argument("sample_rate");
                    mNumChannels = call.argument("num_channels");

                    // Cleanup existing resources if any
                    if (mAudioTrack != null) {
                        cleanup();
                    }

                    int channelConfig = (mNumChannels == 2) ?
                        AudioFormat.CHANNEL_OUT_STEREO :
                        AudioFormat.CHANNEL_OUT_MONO;

                    mMinBufferSize = AudioTrack.getMinBufferSize(
                        sampleRate, channelConfig, AudioFormat.ENCODING_PCM_16BIT);

                    if (mMinBufferSize == AudioTrack.ERROR || mMinBufferSize == AudioTrack.ERROR_BAD_VALUE) {
                        result.error("AudioTrackError", "Invalid buffer size.", null);
                        return;
                    }

                    if (Build.VERSION.SDK_INT >= 23) { // Android 6 (Marshmallow) and above
                        mAudioTrack = new AudioTrack.Builder()
                            .setAudioAttributes(new AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_MEDIA)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                    .build())
                            .setAudioFormat(new AudioFormat.Builder()
                                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                    .setSampleRate(sampleRate)
                                    .setChannelMask(channelConfig)
                                    .build())
                            .setBufferSizeInBytes(mMinBufferSize)
                            .setTransferMode(AudioTrack.MODE_STREAM)
                            .build();
                    } else {
                        mAudioTrack = new AudioTrack(
                            AudioManager.STREAM_MUSIC,
                            sampleRate,
                            channelConfig,
                            AudioFormat.ENCODING_PCM_16BIT,
                            mMinBufferSize,
                            AudioTrack.MODE_STREAM);
                    }

                    if (mAudioTrack.getState() != AudioTrack.STATE_INITIALIZED) {
                        result.error("AudioTrackError", "AudioTrack initialization failed.", null);
                        mAudioTrack.release();
                        mAudioTrack = null;
                        return;
                    }

                    // reset
                    mSamples.clear();
                    mDidInvokeFeedCallback = false;
                    mDidSendZero = false;
                    mShouldCleanup = false;

                    // start playback thread
                    playbackThread = new Thread(this::playbackThreadLoop, "PCMPlaybackThread");
                    playbackThread.setPriority(Thread.MAX_PRIORITY);
                    playbackThread.start();

                    mDidSetup = true;

                    result.success(true);
                    break;
                }
                case "feed": {

                    // check setup (to match iOS behavior)
                    if (mDidSetup == false) {
                        result.error("Setup", "must call setup first", null);
                        return;
                    }

                    byte[] buffer = call.argument("buffer");

                    // reset flags
                    mDidInvokeFeedCallback = false;
                    mDidSendZero = false;

                    // Split for better performance
                    List<ByteBuffer> chunks = split(buffer, MAX_FRAMES_PER_BUFFER);

                    // Push to mSamples
                    for (ByteBuffer chunk : chunks) {
                        mSamples.put(chunk);
                    }

                    result.success(true);
                    break;
                }
                case "setFeedThreshold": {
                    mFeedThreshold = ((Number) call.argument("feed_threshold")).longValue();
                    result.success(true);
                    break;
                }
                case "release": {
                    cleanup();
                    result.success(true);
                    break;
                }
                default:
                    result.notImplemented();
                    break;
            }


        } catch (Exception e) {
            StringWriter sw = new StringWriter();
            PrintWriter pw = new PrintWriter(sw);
            e.printStackTrace(pw);
            String stackTrace = sw.toString();
            result.error("androidException", e.toString(), stackTrace);
            return;
        }
    }


    /**
     * Cleans up resources by stopping the playback thread and releasing AudioTrack.
     */
    private void cleanup() {
        // stop playback thread
        if (playbackThread != null) {
            mShouldCleanup = true;
            playbackThread.interrupt();
            try {
                playbackThread.join();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            playbackThread = null;
            mDidSetup = false;
        }
    }

    /**
     * Calculates the number of remaining frames in the sample buffer.
     */
    private long mRemainingFrames() {
        long totalBytes = 0;
        for (ByteBuffer sampleBuffer : mSamples) {
            totalBytes += sampleBuffer.remaining();
        }
        return totalBytes / (2 * mNumChannels); // 16-bit PCM
    }

    /**
     * Invokes the 'OnFeedSamples' callback with the number of remaining frames.
     */
    private void invokeFeedCallback() {
        long remainingFrames = mRemainingFrames();
        Map<String, Object> response = new HashMap<>();
        response.put("remaining_frames", remainingFrames);
        mMethodChannel.invokeMethod("OnFeedSamples", response);
    }


    /**
     * The main loop of the playback thread.
     */
    private void playbackThreadLoop() {
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO);

        mAudioTrack.play();

        while (!mShouldCleanup) {
            ByteBuffer data = null;
            try {
                // blocks indefinitely until new data
                data = mSamples.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                continue;
            }

            // write
            mAudioTrack.write(data, data.remaining(), AudioTrack.WRITE_BLOCKING);

            long remaining = mRemainingFrames();
            boolean isThresholdEvent = remaining <= mFeedThreshold && !mDidInvokeFeedCallback;
            boolean isZeroCrossingEvent = mDidSendZero == false && remaining == 0;
            if (isThresholdEvent || isZeroCrossingEvent) {
                mDidInvokeFeedCallback = true;
                mDidSendZero = remaining == 0;
                mainThreadHandler.post(this::invokeFeedCallback);
            }
        }

        mAudioTrack.stop();
        mAudioTrack.flush();
        mAudioTrack.release();
        mAudioTrack = null;
    }


    private List<ByteBuffer> split(byte[] buffer, int maxSize) {
        List<ByteBuffer> chunks = new ArrayList<>();
        int offset = 0;
        while (offset < buffer.length) {
            int length = Math.min(buffer.length - offset, maxSize);
            ByteBuffer b = ByteBuffer.wrap(buffer, offset, length);
            chunks.add(b);
            offset += length;
        }
        return chunks;
    }
}
