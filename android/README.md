# Luma for Android TV

Native Android TV companion to the macOS player. This is a TV adaptation of Luma's library and playback features: charcoal/sage styling, landscape layout, visible D-pad focus, and a TV launcher entry. It is not a SwiftUI binary running on Android.

## Build and install

Requires JDK 17 or later (validated with JDK 25), Android SDK platform 35, and an SDK path in `local.properties` (`sdk.dir=/absolute/path/to/sdk`) or `ANDROID_HOME`. The wrapper pins Gradle 9.5.1; Android Gradle Plugin 9.3.0 and Media3 1.8.1 are pinned.

```sh
cd android
./gradlew assembleDebug testDebugUnitTest lintRelease
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

For a signed release:

```sh
./scripts/create-signing-key.sh
./gradlew assembleRelease
adb install -r app/build/outputs/apk/release/app-release.apk
```

The signing helper creates `~/.config/luma/release.jks` and private signing properties outside the repository. Back up that directory securely. Subsequent APK updates must use that key; losing it prevents in-place updates. A build without release signing properties produces an unsigned release artifact. The debug package is `dev.luma.tv.debug`; the signed release is `dev.luma.tv`.

The delivered APK is universal Java bytecode, without architecture-specific bundled native codecs. It supports API 23+ (Android 6.0+) and delegates hardware decoding to the device. Install via a TV file manager or `adb install`; no Google Play listing or paid service is required.

## Features carried over

- Xtream-compatible provider login with account validation; remote M3U and local M3U through Android's document picker when available.
- Live TV, Movies and Series with exact provider category names, separate category search, title search, year filtering, and A–Z/Z–A ordering.
- M3U episode grouping for `S01E02`, `S01 E02` and `1x02`, numeric seasons and episodes, and deduplication with stable identifiers.
- Discover section creation, rename, reorder and removal; mix categories and individual titles across media types. Dynamic favorite sections with media type filters. Individual title picker shows up to 500 matches at a time; search narrows larger catalogs.
- Favorites, history, individual history removal, history clearing, movie/episode resume, and Continue watching. Saved positions every five seconds and when playback stops.
- Provider descriptions, movie details, series overviews, seasons and episode descriptions.
- Fullscreen Media3 playback with remote play/pause, ten-second seeking, playback speed, available audio/subtitle tracks, and remaining/current/current-total clock modes.
- Next episode and cancellable eight-second autoplay countdown across season boundaries.
- Dark, Light and System appearance; per-source favorites, history and layout.
- Saved connection restoration with a dashboard while the catalog loads. Refresh and connection editing after provider failures.

Use D-pad arrows and OK to navigate. Hold OK on a title to toggle its favorite state; details also expose Favorite. The player supports standard media remote keys. Back hides visible playback controls while playing, then returns to the library. Volume keys use Android's system volume.

## TV performance and storage

- RecyclerView recycles visible cards. Catalog loading, parsing, filtering and sorting run on background executors; search is debounced.
- Artwork downloads use two workers, a bounded queue, sampled RGB565 bitmaps, a 10 MB LRU cache and response limits.
- A single ExoPlayer uses hardware decoding, a 24 MB target buffer and a default 1080p video selection cap to reduce pressure on older TV boxes. This cap selects suitable adaptive tracks; it cannot transcode a provider's single 4K stream.
- Playback pauses/releases on leaving the foreground; there is no background streaming service.
- Source details, playback handoff data and watch state are encrypted using AES-GCM and a non-exportable Android Keystore key. OS backups and device transfers exclude app files. Catalogs are reloaded on launch; they are not cached offline.
- No provider, credentials, content, analytics, advertisements or cloud sync are bundled. HTTP sources are supported for provider compatibility; HTTPS is preferable when supplied.

## Validation

```sh
./gradlew testDebugUnitTest lintRelease
# Start the API fixture from repository root:
postman simulation run postman/simulations/iptv.sim.yaml --port 4900 --output ndjson
# In another terminal, serve an original generated MP4 fixture:
python3 -m http.server 4901 --bind 127.0.0.1 --directory ../build/android-fixture
adb reverse tcp:4900 tcp:4900
adb reverse tcp:4901 tcp:4901
./gradlew connectedDebugAndroidTest
```

`TvExperienceTest` expects `fixture.mp4` on the local media server. Generate a 30-second original clip using the existing macOS `scripts/make-test-video.swift` helper, or supply your own authorized H.264 test clip. The fixture provider uses only `fixture` / `fixture`; those are dummy credentials, never a real account. Postman fixture responses follow the existing macOS Xtream client contract; the provider-owner search was unavailable because Postman CLI is signed out. These tests establish behavior against a local stand-in, not certification against every IPTV provider.

Marketing screenshots are actual Android TV emulator captures with fictional metadata and original procedural placeholder artwork. The sample-library action is only present in debug builds. Physical Mi Box hardware has not been connected in this workspace; test its firmware, codecs, remote behavior and provider streams before describing hardware compatibility as verified. DRM/Widevine account flows, EPG schedules, catch-up, recording, multi-account switching and cross-device sync are outside this build.
