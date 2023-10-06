package com.lib.flutter_pcm_sound;

import android.util.Log;
import android.os.Build;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.AudioAttributes;

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
    MethodChannel.MethodCallHandler,
    AudioTrack.OnPlaybackPositionUpdateListener
{
    private final int MAX_FRAMES_PER_BUFFER = 100;
    private final int FRAMES_PER_NOTIFICATION = 500;

    private static final String TAG = "[PCM-Android]";
    private static final String CHANNEL_NAME = "flutter_pcm_sound/methods";
    private MethodChannel mMethodChannel;
    
    private AudioTrack mAudioTrack;
    private int mNumChannels;
    private int mMinBufferSize;

    private long mFeedThreshold = 8000;
    private boolean mFedOnce = false;

    private long mFedFrames;
    private long mPreviousHeadPosition = 0;
    private long mOverflows = 0;

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
        if (mAudioTrack != null) {
            mAudioTrack.release();
        }
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

                mAudioTrack.setPlaybackPositionUpdateListener(this);

                result.success(true);
                break;
            case "play":
                mAudioTrack.setPositionNotificationPeriod(FRAMES_PER_NOTIFICATION);
                mAudioTrack.play();
                mFedOnce = false;
                invokeFeedCallback();
                result.success(true);
                break;
            case "pause":
                mAudioTrack.pause();
                result.success(true);
                break;
            case "stop":
                mFedFrames = 0;
                mPreviousHeadPosition = 0;
                mAudioTrack.stop();
                mAudioTrack.flush();
                result.success(true);
                break;
            case "clear":
                mAudioTrack.flush();
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
                mFedOnce = false;

                // still need more frames?
                if (remainingFrames() < mFeedThreshold){
                    invokeFeedCallback();
                }

                result.success(true);
                break;
            case "setFeedThreshold":
                mFeedThreshold = (int) call.argument("feed_threshold");
                result.success(true);
                break;
            case "remainingFrames":
                result.success(remainingFrames());
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

    // playback head is returned as an signed integer
    // but should be interpreted as unsigned
    private long getUnsignedPlaybackHeadPosition() {
        int playbackPos = mAudioTrack.getPlaybackHeadPosition();
        if (playbackPos < 0) {
            return 4294967296L + playbackPos; // 2^32 + playbackPos
        } else {
            return playbackPos;
        }
    }

    // get the actual playback head position
    // while accounting for overflow
    private long realPlaybackHeadPosition() {
        long cur = getUnsignedPlaybackHeadPosition();

        // overflowed?
        if (cur < mPreviousHeadPosition) {
            mOverflows++;
        }

        mPreviousHeadPosition = cur;

        return cur + mOverflows * 4294967296L; // 2^32
    }

    private long remainingFrames() {
        samplesLock.lock();
        long totalBytes = 0;
        for (ByteBuffer sampleBuffer : mSamples) {
            totalBytes += sampleBuffer.remaining();
        }
        samplesLock.unlock();
        return totalBytes / (2 * mNumChannels);
    }

    private void cleanup() {
        mFedFrames = 0;
        mPreviousHeadPosition = 0;
        mOverflows = 0;
        mAudioTrack.release();
        mAudioTrack = null;
    }

    private void invokeFeedCallback() {
        Map<String, Object> response = new HashMap<>();
        response.put("remaining_frames", remainingFrames());
        mMethodChannel.invokeMethod("OnFeedSamples", response);
    }

    @Override
    public void onMarkerReached(AudioTrack track) {
    }

    @Override
    public void onPeriodicNotification(AudioTrack track) {
        int occupancy = (int) (mFedFrames - realPlaybackHeadPosition());
        int space = mMinBufferSize - occupancy;

        // Write samples to the AudioTrack buffer as long as we
        // have space in the buffer and samples in the queue
        while (space >= MAX_FRAMES_PER_BUFFER && !mSamples.isEmpty()) {
            ByteBuffer data = mSamplesPop();
            int wrote = mAudioTrack.write(data, data.remaining(), AudioTrack.WRITE_BLOCKING);
            if (wrote > 0) {
                mFedFrames += wrote / (2 * mNumChannels);
                space -= wrote;
            }
        }

        // If nearing buffer underflow, feed
        if (remainingFrames() < mFeedThreshold && mFedOnce == false) {
            mFedOnce = true;
            invokeFeedCallback();
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

    // split large array into smaller ones
    private List<ByteBuffer> split(byte[] buffer, int maxSize) {
        List<ByteBuffer> chunks = new ArrayList<>();
        int offset = 0;
        while (offset < buffer.length) {
            // create
            int length = Math.min(buffer.length - offset, maxSize);
            ByteBuffer chunk = ByteBuffer.allocate(length);
            chunk.put(buffer, offset, length);
            
            // add
            chunks.add(chunk);
            offset += length;
        }
        return chunks;
    }
}
