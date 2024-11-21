package com.lib.flutter_pcm_sound;

import android.util.Log;
import android.os.Build;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.AudioAttributes;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import androidx.annotation.NonNull;

import java.util.List;
import java.util.ArrayList;
import java.util.LinkedList;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;
import java.nio.ByteBuffer;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class FlutterPcmSoundPlugin implements
    FlutterPlugin,
    MethodChannel.MethodCallHandler
{
    private final int MAX_FRAMES_PER_BUFFER = 500;

    private static final String TAG = "[PCM-Android]";
    private static final String CHANNEL_NAME = "flutter_pcm_sound/methods";
    private MethodChannel mMethodChannel;

    private Handler mainThreadHandler = new Handler(Looper.getMainLooper());
    private Thread playbackThread;
    private boolean shouldPlaybackThreadSuspend = true;
    private boolean shouldPlaybackThreadLoop = true;
    private final Object suspensionLock = new Object();
    
    private AudioTrack mAudioTrack;
    private int mNumChannels;
    private int mMinBufferSize;
    private int mPlayState;
    private boolean mIsPlaying;

    private long mFeedThreshold = 8000;
    private boolean mDidInvokeFeedCallback = false;

    private LinkedList<ByteBuffer> mSamples = new LinkedList<>();
    private final Lock samplesLock = new ReentrantLock();

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
    @SuppressWarnings("deprecation") // needed for compatability with android < 23
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {

        // ensure setup
        switch (call.method) {
            case "play":
            case "pause":
            case "stop":
            case "clear":
            case "feed": {
                if (mAudioTrack == null) {
                    result.error("mAudioTrackNull", "you must call setup()", null);
                    return;
                }
            }
        }

        switch (call.method) {
            case "setLogLevel":
                // Handle setLogLevel
                result.success(true);
                break;
            case "setup":
                int sampleRate = call.argument("sample_rate");
                mNumChannels = call.argument("num_channels");

                // cleanup
                if (mAudioTrack != null) {
                    cleanup();
                }

                int channelConfig = (mNumChannels == 2) ? 
                    AudioFormat.CHANNEL_OUT_STEREO :
                    AudioFormat.CHANNEL_OUT_MONO;

                mMinBufferSize = AudioTrack.getMinBufferSize(
                    sampleRate, channelConfig, AudioFormat.ENCODING_PCM_16BIT);

                Log.d(TAG, "minBufferSize: " + (mMinBufferSize/(2*mNumChannels)) + " frames");

                if (Build.VERSION.SDK_INT >= 23) { // Android 6 (August 2015)
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
                shouldPlaybackThreadSuspend = true;
                shouldPlaybackThreadLoop = true;
                mDidInvokeFeedCallback =false;
                startPlaybackThread();

                result.success(true);
                break;
            case "play":
                if (mIsPlaying == false) {
                    mDidInvokeFeedCallback = false;
                    invokeFeedCallback();
                    mAudioTrack.play();
                    resumePlaybackThread();
                }
                mIsPlaying = true;
                result.success(true);
                break;
            case "pause":
                if (mIsPlaying == true) {
                    mAudioTrack.pause();
                    suspendPlaybackThread();
                }
                mIsPlaying = false;
                result.success(true);
                break;
            case "stop":
                if (mIsPlaying == true) {
                    mAudioTrack.pause();
                    suspendPlaybackThread();
                }
                mIsPlaying = false;
                mSamplesClear();
                result.success(true);
                break;
            case "clear":
                mSamplesClear();
                result.success(true);
                break;
            case "feed":
                byte[] buffer = call.argument("buffer");

                // Split into smaller buffers
                List<ByteBuffer> got = split(buffer, MAX_FRAMES_PER_BUFFER);
                for (ByteBuffer chunk : got) {
                    mSamplesPush(chunk);
                }

                // reset
                mDidInvokeFeedCallback = false;

                result.success(true);
                break;
            case "setFeedThreshold":
                mFeedThreshold = (int) call.argument("feed_threshold");
                result.success(true);
                break;
            case "remainingFrames":
                result.success(mSamplesRemainingFrames());
                break;
            case "release":
                cleanup();
                result.success(true);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void mSamplesClear() {
        samplesLock.lock();
        mSamples.clear();
        samplesLock.unlock();
    }

    private void mSamplesPush(ByteBuffer samples) {
        samplesLock.lock();
        mSamples.add(samples);
        samplesLock.unlock();
    }

    private ByteBuffer mSamplesPop() {
        samplesLock.lock();
        ByteBuffer out =  mSamples.poll();
        samplesLock.unlock();
        return out;
    }

    private boolean mSamplesIsEmpty() {
        samplesLock.lock();
        boolean out =  mSamples.isEmpty();
        samplesLock.unlock();
        return out;
    }

    private long mSamplesRemainingFrames() {
        samplesLock.lock();
        long totalBytes = 0;
        for (ByteBuffer sampleBuffer : mSamples) {
            totalBytes += sampleBuffer.remaining();
        }
        samplesLock.unlock();
        return totalBytes / (2 * mNumChannels);
    }

    private void cleanup() {
        stopPlaybackThread();
        if (mAudioTrack != null) {
            mAudioTrack.flush();
            mAudioTrack.release();
            mAudioTrack = null;
        }
    }

    private void invokeFeedCallback() {
        Map<String, Object> response = new HashMap<>();
        response.put("remaining_frames", mSamplesRemainingFrames());
        mMethodChannel.invokeMethod("OnFeedSamples", response);
    }

    private void startPlaybackThread() {
        playbackThread = new Thread(() -> {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO);
            long prevFeedTime = 0;
            while (shouldPlaybackThreadLoop) {
                // suspend / resume
                synchronized (suspensionLock) {
                    while (shouldPlaybackThreadSuspend) {
                        try {
                            suspensionLock.wait(); 
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                    }
                }
                // this var can change anytime, so we 
                // recheck it after the above suspension
                if (shouldPlaybackThreadLoop) { 
                    try {
                        if (mIsPlaying) {
                            while (mSamplesIsEmpty() == false) {
                                ByteBuffer data = mSamplesPop();
                                if(data != null) {
                                    data = data.duplicate();
                                }
                                if (data != null && mAudioTrack != null) {
                                    mAudioTrack.write(data, data.remaining(), AudioTrack.WRITE_BLOCKING);
                                }

                                long now = SystemClock.elapsedRealtime();

                                // should request more frames?
                                boolean shouldRequestMore = false;
                                if (mFeedThreshold == -1) {
                                    shouldRequestMore = now - prevFeedTime >= 4; // ~250htz max (30htz typical)
                                } else {
                                    shouldRequestMore = mSamplesRemainingFrames() <= mFeedThreshold && !mDidInvokeFeedCallback;
                                }

                                // request feed
                                if (shouldRequestMore) {
                                    prevFeedTime = now;
                                    mDidInvokeFeedCallback = true;
                                    mainThreadHandler.post(() -> invokeFeedCallback());
                                }
                            }
                        }
                        // avoid excessive CPU usage
                        Thread.sleep(5);
                    } catch (InterruptedException e) {
                    }
                }
            }
        });

        playbackThread.setPriority(Thread.MAX_PRIORITY);
        playbackThread.start();
    }

    private void stopPlaybackThread() {
        if (playbackThread != null) {
            shouldPlaybackThreadSuspend = false;
            shouldPlaybackThreadLoop = false;
            playbackThread.interrupt();
            try {
                playbackThread.join();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            playbackThread = null;
        }
    }

    public void suspendPlaybackThread() {
        synchronized (suspensionLock) {
            shouldPlaybackThreadSuspend = true;
        }
    }

    public void resumePlaybackThread() {
        synchronized (suspensionLock) {
            shouldPlaybackThreadSuspend = false;
            suspensionLock.notify();
        }
    }

    private String audioTrackErrorString(int code) {
        switch (code) {
            case AudioTrack.ERROR_INVALID_OPERATION:
                return "ERROR_INVALID_OPERATION";
            case AudioTrack.ERROR_BAD_VALUE:
                return "ERROR_BAD_VALUE";
            case AudioTrack.ERROR_DEAD_OBJECT:
                return "ERROR_DEAD_OBJECT";
            case AudioTrack.ERROR:
                return "GENERIC ERROR";
            default:
                return "unknownError(" + code + ")";
        }
    }

    // split large array into smaller ones, for better perf
    private List<ByteBuffer> split(byte[] buffer, int maxSize) {
        List<ByteBuffer> chunks = new ArrayList<>();
        int offset = 0;
        while (offset < buffer.length) {
            int length = Math.min(buffer.length - offset, maxSize);
            ByteBuffer b = ByteBuffer.allocate(length);
            b.put(buffer, offset, length);
            b.rewind();
            chunks.add(b);
            offset += length;
        }
        return chunks;
    }
}
