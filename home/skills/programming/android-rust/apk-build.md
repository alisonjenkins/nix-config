# Building an APK without gradle

Pharos's Android Auto spike built this way (`spikes/044-android-auto/build-apk.sh`,
now in git history only; the phone app uses dx). Use this path when there is
no Java source and no dx project. For dx, see [dx-dioxus.md](dx-dioxus.md).

Needs:

- build-tools (`aapt2`, `d8`, `zipalign`, `apksigner`) and an `android.jar`.
  Pharos used build-tools 35.0.0 and `platforms/android-34`.
- The Android NDK, for the linker. Point cargo at its clang, e.g.
  `CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/<host>/bin/aarch64-linux-android26-clang`,
  or use `cargo ndk`. A Nix Android dev shell can export both.
- The Rust target: `rustup target add aarch64-linux-android`.

## Steps

```bash
bt=$ANDROID_HOME/build-tools/35.0.0
platform=$ANDROID_HOME/platforms/android-34/android.jar
rm -rf out/dex stage    # a stale classes2.dex would ship in the new APK
mkdir -p out/dex out/res stage/lib/arm64-v8a   # d8 needs an existing output dir

# 1. classes -> dex  (see classgen.md)
"$bt/d8" --release --min-api 26 --lib "$platform" --output out/dex $(find out/classes -name '*.class')

# 2. native library for arm64
cargo build --release --target aarch64-linux-android
# the file name must match the classes' System.loadLibrary("main") (classgen --lib)
cp target/aarch64-linux-android/release/lib<crate>.so stage/lib/arm64-v8a/libmain.so
cp out/dex/classes*.dex stage/   # d8 may write classes2.dex and up

# 3. manifest + resources
"$bt/aapt2" compile --dir apk/res -o out/res/compiled.zip
"$bt/aapt2" link -o out/base.apk -I "$platform" \
  --manifest apk/AndroidManifest.xml \
  --min-sdk-version 26 --target-sdk-version 34 out/res/compiled.zip

# 4. add dex and lib to the APK aapt2 wrote (Pharos used a python zipfile script)
(cd stage && zip -q -r -0 ../out/base.apk .)   # -0: stored, so zipalign can page-align the .so

# 5. align, then sign (order matters: zipalign before apksigner)
"$bt/zipalign" -P 16 -f 4 out/base.apk out/aligned.apk   # -P 16: 16 KiB pages
"$bt/apksigner" sign --ks "$KEYSTORE" --ks-pass "file:$PASS_FILE" \
  --ks-key-alias "$ALIAS" --out out/app.apk out/aligned.apk
"$bt/apksigner" verify out/app.apk
```

Notes:

- `zipalign -P 16` aligns stored `.so` files to 16 KiB (`-p` is deprecated
  and gives 4 KiB). It only moves zip offsets: the `.so` itself also needs
  16 KiB load segments (NDK r28+ links that by default; older NDKs need
  `-C link-arg=-Wl,-z,max-page-size=16384`). Only stored entries align,
  hence `zip -0`. With
  `android:extractNativeLibs="false"` a compressed `.so` fails install with
  `INSTALL_FAILED_INVALID_APK`. Pharos manifests set it to `"true"`.
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
- Compare the exports with every native method the generated classes
  declare, not one per class: a class with two natives can keep one export
  and still throw on the other. Pharos's check names a specific one
  (`PharosMediaService_nativeOnCreate`); jvm-check compares the full set.
- An APK whose library lost its exports installs, loads, then throws
  `UnsatisfiedLinkError` in the car. This check catches it before the device.

## Install

```bash
adb -s <serial> install -r app.apk
```

If a signature mismatch blocks the install, uninstall the old build first
(`adb -s <serial> uninstall <package>`). That wipes app data.
