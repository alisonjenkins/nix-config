# Generating Java classes from Rust

Pharos: `crates/pharos-classgen/` (`src/lib.rs` is the generator,
`src/main.rs` the CLI). No dependencies. About 620 lines.

## The four shapes

The generator writes class version 52 with branch-free code, so no
`StackMapTable` is needed. Every generated member is one of:

| Shape | What it does |
|---|---|
| Constructor | Passes its arguments to the superclass constructor with the same descriptor. |
| Static initialiser | `System.loadLibrary(lib)`, only when the class sets `load_library`. |
| `Method::Native { name, descriptor }` | `public native` method. Rust implements it. |
| `Method::SuperThenNative { name, descriptor, hook }` | Public method calls `super.name(args)`, then a `private native` `hook` with the same descriptor. Void only. |

Use `SuperThenNative` for lifecycle methods whose framework code must still
run (`Service.onCreate`, `onDestroy`, `Activity.onCreate`).

A shape outside these four (for example a non-void super call) means
extending the generator.

## ClassSpec

```rust
pub struct ClassSpec {
    pub name: String,          // JVM internal form: a/b/C or a/b/C$D
    pub superclass: String,
    pub init: String,          // constructor descriptor, e.g. "()V"; must exist on the superclass
    pub load_library: Option<String>, // "main" loads libmain.so in <clinit>
    pub interfaces: Vec<String>,
    pub methods: Vec<Method>,
}
```

- **Constructor arguments.** `init` is the descriptor and is forwarded
  verbatim. Example: `(Landroid/media/MediaDescription;I)V` for a
  `MediaItem` subclass. It must be a `...V` descriptor.
- **Interfaces.** Put them in `interfaces`. Implement the interface methods
  as `Native`. Pharos has one `PharosPlayerListener` extending
  `java/lang/Object` that implements `OnPreparedListener`, `OnErrorListener`,
  `OnCompletionListener` and `OnAudioFocusChangeListener`. Every callback is
  then a direct native call, with no `Proxy` and no reflection.
- **Which classes load the library.** Set `load_library` on classes the
  platform instantiates first (service, activity, provider). A provider is
  created before the service, so it must load the library itself. Helper
  classes created later from Rust can skip it.
- **Descriptors.** Parsed for argument kinds (int, long, float, double,
  reference, arrays). Bad descriptors return `GenError::BadDescriptor`.
- **Native name.** `Java_<pkg_with_underscores>_<Class>_<method>` in Rust,
  `#[no_mangle] pub extern "system"`. Apply JNI escaping inside each part:
  `_` becomes `_1`, `$` (nested class) becomes `_00024`. So `a/b/C.on_event`
  exports `Java_a_b_C_on_1event`. Name natives in camelCase to avoid it.
  Overloaded natives (same name twice in a class) need the long form: `__`
  then the escaped argument descriptor, so `f(I)V` exports `..._f__I` and
  `f(Ljava/lang/String;)V` exports `..._f__Ljava_lang_String_2`
  (`;` becomes `_2`, `[` becomes `_3`). Hook natives use the hook name,
  e.g. `..._PharosMediaService_nativeOnCreate`.

## Classes Pharos generates

| Class | Superclass | Why |
|---|---|---|
| `PharosMediaService` | `MediaBrowserService` | car and assistant bind it |
| `PharosSessionCallback` | `MediaSession.Callback` | transport and play-from-X |
| `PharosArtProvider` | `ContentProvider` | artwork as `content://` |
| `PharosPlayerListener` | `Object` + 4 listener interfaces | player and focus callbacks |
| `PharosCompatHandler` | `Handler` | androidx search Messenger |
| `PharosNetworkCallback` | `ConnectivityManager.NetworkCallback` | offline detection |
| `PharosDebugReceiver`, `PharosNoisyReceiver` | `BroadcastReceiver` | debug action, becoming-noisy |
| `android/support/v4/media/MediaBrowserCompat$MediaItem` | framework `MediaBrowser.MediaItem` | search results parcel under androidx's name |
| `PharosSearchActivity` | `Activity` | `MEDIA_PLAY_FROM_SEARCH` entry |

## CLI

```
cargo run -q -p pharos-classgen -- --lib main <out-dir>
```

Writes `<out-dir>/<internal/name>.class`. `--lib` names the native library
the classes load. Default is `main`, dx's `libmain.so`.

## d8

```
d8 --release --min-api 26 --lib "$ANDROID_HOME/platforms/android-34/android.jar" \
   --output <dex-dir> $(find <out-dir> -name '*.class')
```

- `--lib` is required: the classes reference framework types.
- Output is `<dex-dir>/classes.dex`. Rename it when adding to an APK
  ([dx-dioxus.md](dx-dioxus.md)).
- d8 lives in `build-tools/<ver>/`. Find it with `command -v d8` or under
  `$ANDROID_HOME`.

## Pitfalls

- **Wrong `max_stack`/`max_locals`.** Patched to 0, the JVM fails with
  `VerifyError: Operand stack overflow`. Run jvm-check with `-Xverify:all`.
- **Missing library export.** The JVM resolves a native on its first call,
  so a dropped `Java_` symbol passes verification and fails later with
  `UnsatisfiedLinkError`. See [dx-dioxus.md](dx-dioxus.md).
- **Non-void `SuperThenNative`.** Returns `GenError::NotVoid`.
- **`init` not on the superclass.** The generator requires it to exist there. Check the
  superclass actually has that constructor.
- **Class must be named exactly in the manifest**, with the same package.
- **Signature typos** in JNI calls only show at run time. Cover them with
  jvm-check.
