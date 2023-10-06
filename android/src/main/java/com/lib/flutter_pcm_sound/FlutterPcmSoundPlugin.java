package com.lib.flutter_pcm_sound;

import android.os.Build;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.AudioAttributes;

import androidx.annotation.NonNull;

import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class FlutterPcmSoundPlugin implements
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    AudioTrack.OnPlaybackPositionUpdateListener
{
    private static final String CHANNEL_NAME = "flutter_pcm_sound/methods";
    private MethodChannel mMethodChannel;
    private AudioTrack mAudioTrack;
    private long mNumChannels;
    private long mFeedThreshold = 8000;
    private long mFedSamples;
    private long mPreviousHeadPosition = 0;
    private long mOverflows = 0;

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

                int minBufferSize = AudioTrack.getMinBufferSize(
                    sampleRate, channelConfig, AudioFormat.ENCODING_PCM_16BIT);
                    
                int audioBufSize = minBufferSize + (sampleRate * 30);

                if (Build.VERSION.SDK_INT >= 33) { // Android 6 (August 2015)
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
                        .setBufferSizeInBytes(audioBufSize)
                        .build();
                } else {
                    mAudioTrack = new AudioTrack(
                        AudioManager.STREAM_MUSIC,
                        sampleRate, 
                        channelConfig,
                        AudioFormat.ENCODING_PCM_16BIT,
                        audioBufSize,
                        AudioTrack.MODE_STREAM);
                }

                mAudioTrack.setPlaybackPositionUpdateListener(this);

                result.success(true);
                break;
            case "play":
                mAudioTrack.play();
                result.success(true);
                break;
            case "pause":
                mAudioTrack.pause();
                result.success(true);
                break;
            case "stop":
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

                // write
                int wrote = mAudioTrack.write(buffer, 0, buffer.length);
                if (wrote < 0) {
                    result.error("mAudioTrackWriteFailed", "error: " + audioTrackErrorString(wrote), null);
                    return;
                }

                mFedSamples += wrote;

                // setup feed callback
                if (remainingSamples() < mFeedThreshold) {
                    invokeFeedCallback();
                } else {
                    // calculate marker position while accounting for wrap around
                    int marker = (int) (mFedSamples - mFeedThreshold);
                    int rv = mAudioTrack.setNotificationMarkerPosition(marker);
                    if (rv < 0) {
                        result.error("setNotificationMarkerPositionFailed", "error: " + audioTrackErrorString(rv), null);
                        return;
                    }
                }

                result.success(true);
                break;
            case "setFeedThreshold":
                mFeedThreshold = call.argument("feed_threshold");
                result.success(true);
                break;
            case "remainingSamples":
                result.success(remainingSamples());
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

    private long remainingSamples() {
        return mFedSamples - realPlaybackHeadPosition();
    }

    private void cleanup() {
        mFedSamples = 0;
        mPreviousHeadPosition = 0;
        mOverflows = 0;
        mAudioTrack.release();
        mAudioTrack = null;
    }

    private void invokeFeedCallback() {
        Map<String, Object> response = new HashMap<>();
        response.put("remaining_samples", remainingSamples());
        mMethodChannel.invokeMethod("OnFeedSamples", response);
    }

    @Override
    public void onMarkerReached(AudioTrack track) {
        invokeFeedCallback();
    }

    @Override
    public void onPeriodicNotification(AudioTrack track) {
        // unused
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
}
