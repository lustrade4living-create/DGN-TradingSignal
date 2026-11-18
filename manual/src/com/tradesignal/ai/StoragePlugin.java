package com.tradesignal.ai;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

// Plugin tu viet: luu tru ben (JSON) vao thu muc rieng cua app
// (/data/data/com.tradesignal.ai/files/<file>), khong can plugin Flutter.
// Dung cho: cai dat chi bao (dgnIndSettingsV1), lua chon chien luoc AI
// (dgnStratV1), phuong phap backtest (dgnBtMethodV1) — luu duoi dang 1 file
// JSON duy nhat "settings.json" (hoac file rieng neu Dart truyen "file").
//
// CHINH SACH BAO MAT: KHONG dung plugin nay de luu API key/secret Exness
// hay bat ky credential nao. Key Exness chi giu trong bo nho phien
// (nhu connectExness() hien tai) va khong bao gio ghi ra file/log.
public class StoragePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private MethodChannel channel;
  private Context context;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    channel = new MethodChannel(binding.getBinaryMessenger(), "tradesignal/storage");
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
  }

  private File storageFile(String fileName) {
    if (fileName == null || fileName.isEmpty()) {
      fileName = "settings.json";
    }
    return new File(context.getFilesDir(), fileName);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    try {
      if (call.method.equals("load")) {
        String fileName = call.argument("file");
        File f = storageFile(fileName);
        if (!f.exists()) {
          result.success(null);
          return;
        }
        FileInputStream in = new FileInputStream(f);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) != -1) {
          out.write(buf, 0, n);
        }
        in.close();
        result.success(new String(out.toByteArray(), StandardCharsets.UTF_8));
      } else if (call.method.equals("save")) {
        String fileName = call.argument("file");
        String json = call.argument("json");
        if (json == null) {
          json = "";
        }
        FileOutputStream out = new FileOutputStream(storageFile(fileName));
        out.write(json.getBytes(StandardCharsets.UTF_8));
        out.close();
        result.success(null);
      } else {
        result.notImplemented();
      }
    } catch (Exception e) {
      result.error("ERR", e.getMessage(), null);
    }
  }
}
