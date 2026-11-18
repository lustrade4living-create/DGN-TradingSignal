package com.tradesignal.ai;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.concurrent.atomic.AtomicBoolean;

// Plugin tu viet: phat am chime intro bang AudioTrack (tong hop song sine
// bang code, khong can file asset am thanh, khong can quyen moi).
//
// Chuoi 8 not giong ban web (spec-web.md §16.2, Web Audio API):
//   not don:  987.77 Hz @+0.10s (0.16s), 1174.66 @+0.27s (0.16s),
//             1318.51 @+0.44s (0.16s), 1567.98 @+0.61s (0.20s)
//   hop am:   1567.98 @+1.12s (0.50s), 1975.53 @+1.24s (0.50s),
//             2349.32 @+1.36s (0.50s), 3135.96 @+1.50s (0.85s)
//   volume web 0.03-0.06 -> bien do PCM ~0.3 cho not don; cac not hop am
//   dung bien do 0.15 moi not (cong song dong thoi, tranh vo tieng).
// Envelope moi not: attack 0.02s + decay exponential de tieng "tinh"
// khong bi cut. Tong thoi luong ~2.35s.
//
// Dung CONSTRUCTOR CU cua AudioTrack (API 3+) thay cho AudioTrack.Builder
// (yeu cau API 23) vi minSdk cua app la 21. Phat tren luong nen
// (new Thread), khong block main thread. Loi nao cung tra success(false),
// khong bao gio crash app.
public class ChimePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final int SAMPLE_RATE = 44100;
  private MethodChannel channel;
  private final AtomicBoolean playing = new AtomicBoolean(false);

  // Mot not: tan so (Hz), thoi diem bat dau (giay), thoi luong (giay), bien do.
  private static final class Note {
    final double freq;
    final double startSec;
    final double durSec;
    final double amp;

    Note(double freq, double startSec, double durSec, double amp) {
      this.freq = freq;
      this.startSec = startSec;
      this.durSec = durSec;
      this.amp = amp;
    }
  }

  // 8 not day du cua intro.
  private static final Note[] FULL_CHIME = new Note[] {
    new Note(987.77, 0.10, 0.16, 0.30),
    new Note(1174.66, 0.27, 0.16, 0.30),
    new Note(1318.51, 0.44, 0.16, 0.30),
    new Note(1567.98, 0.61, 0.20, 0.30),
    new Note(1567.98, 1.12, 0.50, 0.15),
    new Note(1975.53, 1.24, 0.50, 0.15),
    new Note(2349.32, 1.36, 0.50, 0.15),
    new Note(3135.96, 1.50, 0.85, 0.15),
  };

  // 4 not cuoi (hop am) de phat thu khi bat lai am thanh — giu nguyen
  // khoang cach tuong doi giua cac not (0s / 0.12s / 0.24s / 0.38s).
  private static final Note[] TEST_CHIME = new Note[] {
    new Note(1567.98, 0.00, 0.50, 0.15),
    new Note(1975.53, 0.12, 0.50, 0.15),
    new Note(2349.32, 0.24, 0.50, 0.15),
    new Note(3135.96, 0.38, 0.85, 0.15),
  };

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    channel = new MethodChannel(binding.getBinaryMessenger(), "tradesignal/chime");
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    if (call.method.equals("playChime")) {
      playAsync(FULL_CHIME, result);
    } else if (call.method.equals("playTestChime")) {
      playAsync(TEST_CHIME, result);
    } else {
      result.notImplemented();
    }
  }

  // Tra ket qua ve main thread (MethodChannel.Result cua Flutter).
  private static void replyOnMain(final MethodChannel.Result result, final boolean ok) {
    new Handler(Looper.getMainLooper()).post(new Runnable() {
      @Override
      public void run() {
        result.success(ok);
      }
    });
  }

  private void playAsync(final Note[] notes, final MethodChannel.Result result) {
    // Dang phat roi thi khong chong them 1 AudioTrack nua.
    if (!playing.compareAndSet(false, true)) {
      replyOnMain(result, true);
      return;
    }
    new Thread(new Runnable() {
      @Override
      public void run() {
        boolean ok = false;
        AudioTrack track = null;
        try {
          short[] pcm = renderPcm(notes);
          int minBuf = AudioTrack.getMinBufferSize(
              SAMPLE_RATE,
              AudioFormat.CHANNEL_OUT_MONO,
              AudioFormat.ENCODING_PCM_16BIT);
          int bufSize = Math.max(minBuf, pcm.length * 2);
          track = new AudioTrack(
              AudioManager.STREAM_MUSIC,
              SAMPLE_RATE,
              AudioFormat.CHANNEL_OUT_MONO,
              AudioFormat.ENCODING_PCM_16BIT,
              bufSize,
              AudioTrack.MODE_STREAM);
          if (track.getState() != AudioTrack.STATE_INITIALIZED) {
            track.release();
            track = null;
            replyOnMain(result, false);
            return;
          }
          track.play();
          track.write(pcm, 0, pcm.length);
          track.stop();
          ok = true;
        } catch (Exception e) {
          ok = false;
        } finally {
          if (track != null) {
            try {
              track.release();
            } catch (Exception ignored) {
            }
          }
          playing.set(false);
        }
        replyOnMain(result, ok);
      }
    }).start();
  }

  // Tron tat ca not vao 1 buffer PCM 16-bit mono 44100Hz. Cac not hop am
  // phat dong thoi bang cach cong song. Envelope: attack 0.02s, sau do
  // decay exponential (ve ~5% o cuoi not) de tieng khong bi cut dot ngot.
  private static short[] renderPcm(Note[] notes) {
    double endSec = 0;
    for (Note n : notes) {
      endSec = Math.max(endSec, n.startSec + n.durSec);
    }
    int total = (int) Math.ceil(endSec * SAMPLE_RATE);
    double[] mix = new double[total];
    for (Note n : notes) {
      int start = (int) Math.round(n.startSec * SAMPLE_RATE);
      int len = (int) Math.round(n.durSec * SAMPLE_RATE);
      for (int i = 0; i < len; i++) {
        int idx = start + i;
        if (idx >= total) {
          break;
        }
        double t = (double) i / SAMPLE_RATE;
        double attack = Math.min(1.0, t / 0.02);
        double decay = Math.exp(-3.0 * t / n.durSec);
        double env = attack * decay;
        mix[idx] += n.amp * Math.sin(2.0 * Math.PI * n.freq * t) * env;
      }
    }
    short[] pcm = new short[total];
    for (int i = 0; i < total; i++) {
      double v = Math.max(-1.0, Math.min(1.0, mix[i]));
      pcm[i] = (short) Math.round(v * Short.MAX_VALUE);
    }
    return pcm;
  }
}
