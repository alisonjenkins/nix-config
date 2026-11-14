# Android Auto media apps

Pharos spec: `specs/044-android-auto/` (`spec.md`, `spike-0.md`,
`tasks.md`). Code: `crates/pharos-android/src/`. Android Auto never shows
the app's own UI. It binds the media browser service and draws its own
lists and now-playing screen.

## Manifest

- `<meta-data android:name="com.google.android.gms.car.application"
  android:resource="@xml/automotive_app_desc"/>` with
  `res/xml/automotive_app_desc.xml`:
  `<automotiveApp><uses name="media" /></automotiveApp>`.
- Service: exported, intent filter action
  `android.media.browse.MediaBrowserService`,
  `android:foregroundServiceType="mediaPlayback"`.
- Permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`,
  `INTERNET`, `ACCESS_NETWORK_STATE`, and `POST_NOTIFICATIONS` (below).
- Distribution as a sideloaded APK works because Android Auto's developer
  settings have "Unknown sources" on.

## Service and session

Framework classes only: `MediaBrowserService` and `MediaSession`
(`service.rs`, `session.rs`, `browse.rs`).

- `onCreate` (super, then native): create the session, set its token.
- `onGetRoot`: the car may call it with any package. Pharos logs
  `package`, `uid` and the verdict. Assistant also binds
  (`com.google.android.googlequicksearchbox`) and browses unprompted.
- Root extras **must** carry `android.media.browse.SEARCH_SUPPORTED=true`.
  Without it the car hides the search button (confirmed in the DHU).
- `onLoadChildren` gets a `Result`. Library calls block on the network, so
  call `detach()` and send from a worker thread attached to the JVM. Search
  does not come through here: see the Messenger section below.
- Session flags 3 (media buttons and transport controls). Advertise
  `PREPARE` actions. State is BUFFERING until `onPrepared`.
- Seek: advertised; the DHU console cannot drag, so it is not exercisable
  there.

## Search over the androidx compat Messenger

The framework `MediaBrowserService` has no search call. A compat client
(Android Auto) searches only when the root extras carry a Messenger binder.
Constants (`compat.rs`):

| Item | Value |
|---|---|
| Root extra: binder | `extra_messenger` |
| Root extra: version | `extra_service_version` = `1` (keeps browsing on the framework path; a compat client subscribes over the Messenger only from version 2) |
| Request `what` | `MSG_SEARCH` = `8` |
| Request bundle | `data_search_query` (string), `data_search_extras` (bundle), `data_result_receiver` (parcelable), `data_calling_pid` |
| Reply bundle key | `search_results` |
| Receiver descriptor | `android.support.v4.os.IResultReceiver` |
| Reply | `send` transaction code `1`, flag `FLAG_ONEWAY` = `1`, result code `RESULT_OK` = `0` |

How it works:

- A generated `Handler` subclass (`PharosCompatHandler.handleMessage`) sits
  behind a `Messenger`. Its binder goes in the root extras.
- The request bundle names androidx's receiver class, which the app does
  not have. Read it from the parcel rather than unparcelling it.
- Reply by writing a transaction to the receiver's binder: descriptor
  string, result code, then a bundle holding `search_results`.
- Each item must parcel under the class name
  `android.support.v4.media.MediaBrowserCompat$MediaItem`, because the car
  casts to androidx's type. Generate a subclass of the framework
  `MediaBrowser.MediaItem` under that name (its parcel is flags, then the
  description). See [classgen.md](classgen.md).

## Artwork provider

The car draws icons and album art from `content://` URIs it opens through
your `ContentProvider`, not from http URLs (`art.rs`).

- Authority: `<applicationId>.art`, so two build variants can co-install.
  Rust derives it from the package name; the manifest uses
  `${applicationId}.art`. Verify both with `aapt2 dump xmltree`.
- `openFile` downloads the image into the cache dir on first use and
  returns a read-only file. Refuse write modes and path tricks.
- Fetch only URLs registered through the URI builder in this process, so
  the exported provider cannot fetch arbitrary URLs. Serve files already in
  the cache by key after a restart.
- The provider is created before the service, so its class loads the
  library itself (`load_library`).
- Exported with no permission so the host can read it. `query`, `insert`,
  `delete`, `update` return null/0.

## Audio focus and attributes (`focus.rs`)

- `AudioAttributes`: usage `USAGE_MEDIA` (1), content type
  `CONTENT_TYPE_MUSIC` (2). Set on the player before its source, and on the
  session (`setPlaybackToLocal`-style attributes).
- Request `AUDIOFOCUS_GAIN` (1) with an `AudioFocusRequest` carrying those
  attributes.
- Handle changes through a generated `OnAudioFocusChangeListener`:
  - `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK` (-3): lower volume, keep playing.
  - `AUDIOFOCUS_LOSS_TRANSIENT` (-2): pause. Regain resumes.
  - `AUDIOFOCUS_LOSS` (-1): give focus back.
  - `AUDIOFOCUS_REQUEST_FAILED` (0) on request: do not start.

## Foreground service and notification (`foreground.rs`)

- Playing puts the service in the foreground, so playback survives a locked
  phone with no car bound. Pausing leaves the foreground but keeps the
  notification. Stopping removes it.
- `MediaStyle` notification tied to the session token, on channel
  `playback` with `IMPORTANCE_LOW` (2).
- A small icon is required. Pharos uses `drawable/ic_stat_pharos`
  (white mark on transparent) and logs `notify: small_icon=app`.
- A `MediaStyle` notification tied to the session is exempt from the
  `POST_NOTIFICATIONS` runtime permission (API 33). Still declare it, and
  ask from an Activity when SDK >= 33 and not granted (`app.rs`,
  `ask_notification_permission`): `checkSelfPermission`, then
  `requestPermissions`.

## Becoming noisy (`noisy.rs`)

- Register a receiver in code for `android.media.AUDIO_BECOMING_NOISY`
  when the service starts. Unregister on destroy.
- On API 33+ pass `Context.RECEIVER_NOT_EXPORTED` (4). System broadcasts
  still arrive.
- Pause when playing. Do nothing when already paused.
- Receivers registered in code, not in the manifest.

## Icons (`crates/pharos-ui/android/res/README.md`)

| File | Purpose |
|---|---|
| `mipmap-anydpi-v26/ic_launcher.xml` | Adaptive: background, foreground, monochrome layers |
| `drawable/ic_launcher_monochrome.xml` | One-colour layer for Android 13 themed icons |
| `drawable-v24/ic_launcher_foreground.xml`, `drawable/ic_launcher_background.xml` | Adaptive layers |
| `drawable/ic_stat_pharos.xml` | Notification small icon, white on transparent |
| `mipmap-*/ic_launcher.webp` | Bitmap fallback, **full dark circle** |
| `values/strings.xml` | `app_name` |

The car launcher draws the legacy mipmap inside a white disc. A rounded
square leaves a white ring. Ship full circle bitmaps (48/72/96/144/192 px
for m/h/xh/xxh/xxxhdpi). ImageMagick, per density:

```bash
magick icon-512.png -resize 96x96 \
  \( -size 96x96 xc:'#0E1116' \) +swap -gravity center -compose over -composite \
  \( -size 96x96 xc:black -fill white -draw 'circle 48,48 48,0' \) \
  -alpha off -compose copyopacity -composite \
  -define webp:lossless=true webp:mipmap-xhdpi/ic_launcher.webp
```

## Voice (spec "Voice findings", 2026-11-14)

- Works: transport commands to the active session ("next song", "pause").
- Works: dictation through the in-app search mic (the compat Messenger
  search above).
- Phone-side entry: an activity handling `android.media.action.MEDIA_PLAY_FROM_SEARCH`
  (Pharos: `PharosSearchActivity`, no UI, `Theme.NoDisplay`, also a
  launcher entry) reads the `query` extra, plays the best match, finishes.
  Test with `adb -s <serial> shell am start -a android.media.action.MEDIA_PLAY_FROM_SEARCH -e query "<text>"`.
- Does not work: Gemini "play X on <app>" went to YouTube Music. Gemini
  appears to route play-from-search only to a Google partner list. No
  documented app-side fix changed it (intent filter, launcher activity,
  installer id, session flags).
- Gemini also mis-transcribed the app name, so a spoken name can fail
  before routing is even a question.
- Future route in the spec: Android AppFunctions (private preview).
