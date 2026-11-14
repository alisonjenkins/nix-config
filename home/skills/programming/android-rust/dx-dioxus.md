# dx / Dioxus on Android

Pharos: `scripts/android-phone-apk.sh` (phone) and `scripts/android-apk.sh`
(TV). Dioxus `dx` builds the cdylib and writes a gradle project. The extra
classes ride along as a second dex in the same APK.

## One library for UI and services

- dx builds one `libmain.so`. The Dioxus activity and the generated service
  classes all load it (`--lib main` in classgen).
- The phone app (UI) and the car's media service run in the same process
  and the same library.

## Keep the `Java_` exports alive

The generated classes call into the library by name. Nothing in Rust calls
those `extern "system"` functions, so the linker drops them.

1. Collect pointers to every export in one function, e.g.
   `pub fn exports() -> [*const (); N]`.
2. Expose `pub fn link() { std::hint::black_box(exports()); }`.
3. Call `link()` once from the app's `main` (Pharos:
   `crates/pharos-phone/src/main.rs`, with a comment saying why).
4. Add a unit test that the list has no duplicates or nulls.
5. Verify the built `.so` with `llvm-nm` ([apk-build.md](apk-build.md)).

Symptom without it: the app installs and starts, then
`UnsatisfiedLinkError` when the car binds the service.

## Add the extra dex at the next free classesN.dex

ART loads `classes.dex`, `classes2.dex`, ... and stops at the first gap.
Gradle may already write several (a debug build at minSdk 26 does). Find
the highest index and add one:

```bash
last=$(unzip -Z1 unsigned.apk | sed -n 's/^classes\([0-9]*\)\.dex$/\1/p' | sed 's/^$/1/' | sort -n | tail -n 1)
car_dex=classes$((${last:-1} + 1)).dex
mv dex/classes.dex "$car_dex"
zip -q -0 unsigned.apk "$car_dex"
```

(`classes.dex` has no number, so the second `sed` maps empty to 1.)
Then run the checks, then `zipalign`, then `apksigner`. The signature is
over the final bytes, so add the dex first.

## dx's gradle step fails once, on purpose

If the manifest names resources only your overlay adds (for example
`@xml/automotive_app_desc`), dx's own gradle run fails at resource linking.
By then dx has built `libmain.so` and written the project. Pharos' recipe:

1. `rm -rf <gradle>/app/src/main/jniLibs` first, so a library found
   afterwards came from this build.
2. Run `dx build --platform android --package <pkg> --bin <bin> --features mobile --target aarch64-linux-android`, record the exit status, do not abort.
3. Continue only if `jniLibs/arm64-v8a/libmain.so` and `gradlew` both exist.
   Otherwise fail and print dx's status.
4. Lay the resource overlay (below).
5. Run `./gradlew --quiet assembleDebug` in the generated project.

The gradle project lives at `target/dx/<package>/<profile>/android/app` in
Pharos.

## Resource overlay

dx 0.7 always writes its default launcher icon (the Android robot) and an
`app_name` of the bin name in Pascal case. It has no setting for either.
After `dx build`, copy your `res/` tree over the generated one:

```bash
cp -r crates/pharos-ui/android/res/. "$main_dir/res/"
cp -r crates/pharos-phone/android/res/. "$main_dir/res/"   # per-app overrides
rm -f "$main_dir/res/README.md"
```

Pharos also rewrites the TV manifest's `android:banner` with `sed` and
greps to confirm. Icon files: [android-auto.md](android-auto.md).

## dx's native thread cannot see app classes

dx runs the Rust UI on a thread attached from native code. That thread
finds classes through the system loader, which does not see the app's
classes (including generated ones).

- Do app-class lookups (`FindClass` for generated classes) on the thread
  the framework calls, i.e. from the service's `onCreate`.
- Cache the result as a `GlobalRef` in a `OnceLock`.
- Pharos: `cache_classes` in `crates/pharos-android/src/runtime.rs`, doc on
  `Classes` in `lib.rs`.
- The UI side reaches the service through a `Player` handle that queues
  commands to one thread attached to the JVM.

## Related

- Notification permission: ask from an Activity ([android-auto.md](android-auto.md)).
- Pharos targets arm64 phones only (`--target aarch64-linux-android`). An
  x86_64 emulator or a 32-bit device needs its own target
  (`x86_64-linux-android`, `armv7-linux-androideabi`) and its own
  `lib/<abi>/` directory in the APK.
