package io.flutter.plugins;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import io.flutter.Log;
import io.flutter.embedding.engine.FlutterEngine;

@Keep
public final class GeneratedPluginRegistrant {
  private static final String TAG = "GeneratedPluginRegistrant";
  public static void registerWith(@NonNull FlutterEngine flutterEngine) {
    try {
      flutterEngine.getPlugins().add(new com.tradesignal.ai.StoragePlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin StoragePlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.tradesignal.ai.ChimePlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin ChimePlugin", e);
    }
  }
}
