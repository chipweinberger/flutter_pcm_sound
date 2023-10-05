package your.package.name;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;

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
    private ByteBuffer mSamples;
    private int mNumChannels;
    private int mFeedThreshold = 8000;

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
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "setLogLevel":
                // Handle setLogLevel
                break;
            case "setup":
                int sampleRate = call.argument("sample_rate");
                mNumChannels = call.argument("num_channels");

                // destroy
                if (mAudioTrack != null) {
                    mAudioTrack.release();
                }

                int channelConfig = (numChannels == 2) ? 
                    AudioFormat.CHANNEL_OUT_STEREO :
                    AudioFormat.CHANNEL_OUT_MONO;

                int minBufferSize = AudioTrack.getMinBufferSize(
                    sampleRate, 
                    channelConfig, 
                    AudioFormat.ENCODING_PCM_16BIT);
                    
                int extraSpace = sampleRate * 30;

                mAudioTrack = new AudioTrack(
                    AudioManager.STREAM_MUSIC,
                    sampleRate, 
                    channelConfig,
                    AudioFormat.ENCODING_PCM_16BIT,
                    minBufferSize * extraSpace,
                    AudioTrack.MODE_STREAM);

                audioTrack.setPlaybackPositionUpdateListener(this);

                mSamples = ByteBuffer.allocateDirect(minBufferSize);

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
                mSamples.clear();
                result.success(true);
                break;
            case "clear":
                mSamples.clear();
                result.success(true);
                break;
            case "feed":
                byte[] buffer = call.argument("buffer");

                mSamples.put(buffer);

                if (mSamples.position() >= mFeedThreshold * mNumChannels * 2) { // *2 because 16-bit samples
                    mAudioTrack.write(mSamples.array(), 0, mSamples.position());
                    mSamples.clear();
                    
                    // If needed, notify Flutter side to feed more samples
                    Map<String, Object> response = new HashMap<>();
                    response.put("remaining_samples", mSamples.remaining());
                    mMethodChannel.invokeMethod("OnFeedSamples", response);
                }
                int totalFrames = audioTrack.getBufferSizeInFrames();
                int notifyPosition = totalFrames - mFeedThreshold;
                audioTrack.setNotificationMarkerPosition(notifyPosition);

                result.success(true);
                break;
            case "setFeedThreshold":
                mFeedThreshold = call.argument("feed_threshold");
                result.success(true);
                break;
            case "remainingSamples":
                int remainingSamples = mSamples.remaining();
                result.success(remainingSamples);
                break;
            case "release":
                mAudioTrack.release();
                result.success(true);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    @Override
    public void onPeriodicNotification(AudioTrack track) {
        // Notify Flutter side to feed more data or perform other tasks
        channel.invokeMethod("OnFeedSamples", null);
    }

    @Override
    public void onMarkerReached(AudioTrack track) {
        // This is called when a previously set marker is reached in the playback. 
        // Notify Flutter side if needed or perform other tasks
        channel.invokeMethod("OnFeedSamples", null);
    }
}
