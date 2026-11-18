#!/bin/bash
# TradeSignal AI: build APK thu cong, khong dung Gradle.
# Buoc 0: flutter assemble (android_aot) -> app.so 3 ABI + flutter_assets
# Buoc 1-6: aapt2 + javac + R8 8.13.25 + zipalign + apksigner (nhu SheepMath).
set -e
export JAVA_HOME=~/jdk17
export ANDROID_HOME=~/Android/sdk
export PATH=~/jdk17/bin:~/flutter/bin:$PATH
PROJ=~/workspace/TradeSignalApp
WORK=$PROJ/build/manual
STAGE=$WORK/stage
BT=$ANDROID_HOME/build-tools/34.0.0
ANDROID_JAR=$ANDROID_HOME/platforms/android-34/android.jar
INTER=$WORK/intermediate

# 0. flutter assemble (rieng tung ABI vi -dTargetPlatform khong nhan
# danh sach cach nhau bang dau phay), roi gop app.so + flutter_assets.
cd "$PROJ"
flutter pub get --offline
mkdir -p "$INTER"
for ABI in android-arm android-arm64 android-x64; do
  case "$ABI" in
    android-arm) DIR=armeabi-v7a ;;
    android-arm64) DIR=arm64-v8a ;;
    android-x64) DIR=x86_64 ;;
  esac
  flutter assemble --output="$WORK/assemble-$DIR" \
    -dTargetPlatform=$ABI \
    -dTargetFile=lib/main.dart -dBuildMode=release \
    -dTreeShakeIcons=true -dDartObfuscation=false -dTrackWidgetCreation=false \
    android_aot_bundle_release_$ABI
  mkdir -p "$INTER/$DIR"
  cp "$WORK/assemble-$DIR/$DIR/app.so" "$INTER/$DIR/app.so"
done
rm -rf "$INTER/flutter_assets"
cp -r "$WORK/assemble-arm64-v8a/flutter_assets" "$INTER/flutter_assets"
ls -R "$INTER" | head -40

rm -rf "$STAGE"
mkdir -p "$STAGE/assets" "$STAGE/gen" "$WORK/classes" "$WORK/dex"

# 1. Manifest: them package + version, thay ${applicationName}
mkdir -p "$STAGE/manifest"
sed -e 's|<manifest xmlns:android="http://schemas.android.com/apk/res/android">|<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.tradesignal.ai" android:versionCode="6" android:versionName="1.2.3">|' \
    -e 's|android:name="${applicationName}"|android:name="io.flutter.app.FlutterApplication" android:extractNativeLibs="true"|' \
    "$PROJ/android/app/src/main/AndroidManifest.xml" > "$STAGE/manifest/AndroidManifest.xml"
cp -r "$PROJ/android/app/src/main/res" "$STAGE/res"
cp -r "$INTER/flutter_assets" "$STAGE/assets/flutter_assets"

# 2. aapt2 compile + link
"$BT/aapt2" compile --dir "$STAGE/res" -o "$WORK/compiled_res.zip"
"$BT/aapt2" link -o "$WORK/unsigned.apk" \
  --manifest "$STAGE/manifest/AndroidManifest.xml" \
  -I "$ANDROID_JAR" \
  --min-sdk-version 21 --target-sdk-version 34 \
  --version-code 6 --version-name 1.2.3 \
  --java "$STAGE/gen" \
  -A "$STAGE/assets" \
  -R "$WORK/compiled_res.zip" \
  --auto-add-overlay
find "$STAGE/gen" -name "*.java"

# 3. javac: MainActivity + GeneratedPluginRegistrant + R.java
# (don sach classes/dex cu de khong sot class stub cua lan chay truoc)
rm -rf "$WORK/classes" "$WORK/dex"
mkdir -p "$WORK/classes" "$WORK/dex"
FLUTTER_JAR=~/flutter/bin/cache/artifacts/engine/android-arm64-release/flutter.jar
LIBS_CP=$(ls "$PROJ/manual/libs"/*.jar | paste -sd: -)
# Khong bien dich stub androidx/annotation (Keep/NonNull/Nullable) nua:
# annotation.jar trong libs da co san cac class nay, bien dich ca hai
# se khien R8 bao "defined multiple times".
find "$PROJ/manual/src/com" "$PROJ/manual/src/io" "$STAGE/gen" -name "*.java" > "$WORK/sources.txt"
javac -nowarn -encoding UTF-8 -source 8 -target 8 \
  -cp "$FLUTTER_JAR:$ANDROID_JAR:$LIBS_CP" \
  -d "$WORK/classes" \
  @"$WORK/sources.txt"

# 4. R8 D8: dex app classes + flutter.jar + androidx libs
LIBS_FILES=$(ls "$PROJ/manual/libs"/*.jar)
(cd "$WORK/classes" && jar cf "$WORK/app-classes.jar" .)
java -cp "$PROJ/manual/r8.jar" com.android.tools.r8.D8 --release --min-api 21 --output "$WORK/dex" \
  --lib "$ANDROID_JAR" \
  "$WORK/app-classes.jar" "$FLUTTER_JAR" $LIBS_FILES
ls -lh "$WORK/dex"

# 5. Them dex + native lib vao APK
python3 - "$WORK/unsigned.apk" "$INTER" "$WORK/dex" << 'PY'
import sys, zipfile, os
apk, inter, dexdir = sys.argv[1], sys.argv[2], sys.argv[3]
abis = {"armeabi-v7a": "android-arm-release", "arm64-v8a": "android-arm64-release", "x86_64": "android-x64-release"}
with zipfile.ZipFile(apk, "a", zipfile.ZIP_STORED) as z:
    for f in sorted(os.listdir(dexdir)):
        if f.endswith(".dex"):
            z.write(os.path.join(dexdir, f), f)
    for abi, eng in abis.items():
        app_so = os.path.join(inter, abi, "app.so")
        z.write(app_so, f"lib/{abi}/libapp.so")
        jar = os.path.expanduser(f"~/flutter/bin/cache/artifacts/engine/{eng}/flutter.jar")
        with zipfile.ZipFile(jar) as jz:
            data = jz.read(f"lib/{abi}/libflutter.so")
        z.writestr(f"lib/{abi}/libflutter.so", data)
print("added dex + libs")
PY

# 6. zipalign + ky debug keystore
"$BT/zipalign" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
if [ ! -f "$WORK/debug.keystore" ]; then
  keytool -genkeypair -keystore "$WORK/debug.keystore" -alias androiddebugkey \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass android -keypass android \
    -dname "CN=Android Debug,O=Android,C=US" -noprompt
fi
"$BT/apksigner" sign --ks "$WORK/debug.keystore" --ks-pass pass:android \
  --key-pass pass:android --out "$WORK/TradeSignalAI-v1.2.3.apk" "$WORK/aligned.apk"

"$BT/apksigner" verify --verbose "$WORK/TradeSignalAI-v1.2.3.apk"
"$BT/aapt2" dump badging "$WORK/TradeSignalAI-v1.2.3.apk" | head -n 12
ls -lh "$WORK/TradeSignalAI-v1.2.3.apk"
echo MANUAL_BUILD_OK
