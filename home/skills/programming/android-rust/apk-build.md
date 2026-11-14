# Building an APK without gradle

Pharos: `spikes/044-android-auto/build-apk.sh`. Use this path when there is
no Java source and no dx project. For dx, see [dx-dioxus.md](dx-dioxus.md).

Needs build-tools (`aapt2`, `d8`, `zipalign`, `apksigner`), an
`android.jar`, and the Rust Android target. Pharos used build-tools 35.0.0
and `platforms/android-34`.

## Steps

```bash
bt=$ANDROID_HOME/build-tools/35.0.0
platform=$ANDROID_HOME/platforms/android-34/android.jar

# 1. classes -> dex  (see classgen.md)
"$bt/d8" --release --min-api 26 --lib "$platform" --output out/dex $(find out/classes -name '*.class')

# 2. native library for arm64
cargo build --release --target aarch64-linux-android
mkdir -p stage/lib/arm64-v8a
cp target/aarch64-linux-android/release/libapp.so stage/lib/arm64-v8a/
cp out/dex/classes.dex stage/

# 3. manifest + resources
"$bt/aapt2" compile --dir apk/res -o out/res/compiled.zip
"$bt/aapt2" link -o out/base.apk -I "$platform" \
  --manifest apk/AndroidManifest.xml \
  --min-sdk-version 26 --target-sdk-version 34 out/res/compiled.zip

# 4. add dex and lib to the zip (Pharos used a small python zipfile script;
#    `cd stage && zip -r ../out/base.apk .` also works)

# 5. align, then sign (order matters: zipalign before apksigner)
"$bt/zipalign" -p -f 4 out/base.apk out/aligned.apk
"$bt/apksigner" sign --ks "$KEYSTORE" --ks-pass "file:$PASS_FILE" \
  --ks-key-alias "$ALIAS" --out out/app.apk out/aligned.apk
"$bt/apksigner" verify out/app.apk
```

Notes:

- `zipalign -p 4` page-aligns stored `.so` files. Pharos manifests also set
  `android:extractNativeLibs="true"`.
- Signing after aligning is required: aligning invalidates a signature.
- Keystore, password file and alias come from env vars you provide
  (Pharos: `PHAROS_ANDROID_KEYSTORE`, `..._KEYSTORE_PASS_FILE`,
  `..._KEY_ALIAS`). Never print or commit them. Pass the password as
  `file:`, not on the command line.
- `zip -0` (store, no compression) is what Pharos used when appending a
  `classesN.dex` to an existing APK: `zip -q -0 unsigned.apk classes3.dex`.
- Check the manifest names every generated class by its full name.

## versionCode from time

Every build must install as newer. Count minutes since a fixed epoch:

```bash
version_code=$((($(date -u +%s) - 1767225600) / 60))   # minutes since 2026-01-01T00:00:00Z
```

dx writes `versionCode = 1` into `app/build.gradle.kts`. Pharos rewrites it
with `sed -i "s/versionCode = [0-9]*/versionCode = $version_code/"`, then
greps to confirm the change landed.

## Checks before signing

Pharos: `scripts/android-phone-apk-check.sh <apk>`. It prints `ok` or `FAIL`
per check and exits with the failure count. Do not sign an APK that fails.

| Check | Command |
|---|---|
| Label, package, minSdk | `aapt2 dump badging app.apk` (`application-label:`, `package: name=`, `minSdkVersion:`) |
| Manifest names the service, provider, activity, intent filters | `aapt2 dump xmltree --file AndroidManifest.xml app.apk` and grep for the full class names |
| Resources exist (notification icon, monochrome layer) | `aapt2 dump resources app.apk` and grep `resource 0x... drawable/<name>` |
| Which dex holds a class | `unzip -q -o app.apk 'classes*.dex' -d tmp; grep -alF 'Lcom/example/auto/MyService;' tmp/classes*.dex` |
| `.so` exports | see below |

Library exports. Extract `lib/arm64-v8a/libmain.so`, then:

```bash
llvm-nm -D --defined-only libmain.so | awk '$3 ~ /^Java_com_example_auto_/ {print $3}' | sort -u
```

- Use `llvm-nm` from the NDK (`$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/*/bin/llvm-nm`)
  because the file is an Android ELF. Plain `nm -D` worked for a host `.so`
  in jvm-check.
- Assert at least one export per generated class, and name a specific one
  (Pharos checks `PharosMediaService_nativeOnCreate`).
- An APK whose library lost its exports installs, loads, then throws
  `UnsatisfiedLinkError` in the car. This check catches it before the device.

## Install

```bash
adb -s <serial> install -r app.apk
```

If a signature mismatch blocks the install, uninstall the old build first
(`adb -s <serial> uninstall <package>`). That wipes app data.
