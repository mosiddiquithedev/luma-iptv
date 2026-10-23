# Luma for macOS

A native SwiftUI IPTV player with charcoal and sage Dark mode, a soft green Light mode, and System appearance. Luma supplies **no content**: everything comes from the account or playlist the user connects.

## Run

Requires macOS 14 or later and Swift 6 / Apple Command Line Tools. Xcode is optional.

```sh
./scripts/build-app.sh
open build/Luma.app
```

The build produces a locally signed application at `build/Luma.app`. You can copy it to your Applications folder. Distribution to other Macs requires your own Developer ID signing and notarization.

Install VLC in `/Applications/VLC.app` for integrated playback of MPEG-TS, MKV, HLS and other IPTV formats. Luma loads the local VLC runtime; it does not bundle or download VLC. If VLC is unavailable or incompatible with the machine architecture, Luma falls back to Apple's AVPlayer for supported formats. The player displays which engine is in use.

## Connect your library

- **Provider login:** enter the server URL, username, and password for an Xtream Codes-compatible account.
- **M3U playlist:** paste an HTTP/HTTPS playlist URL or choose a local `.m3u` or `.m3u8` file.
- Categories are imported verbatim from your provider or playlist, including Bollywood, Hollywood, regional, and other groups when present.
- M3U items named `Show S01E02`, `Show S01 E02`, or `Show 1x02` are grouped into series and seasons. Other video files appear under Movies; remaining entries appear under Live TV. An M3U file without episode information cannot supply a reliable episode order.

## Features

- Customizable Discover sections: rename, reorder, remove, or add as many sections as you want. Each section can combine categories and individual titles from Live TV, Movies, and Series. Category/title search and a Selected only filter make large libraries easier to manage.
- Favorite TV Channels, Favorite Movies, and Favorite Series presets update automatically as you favorite content. Favorites sections can include any combination of content types.
- Bollywood/Hollywood sections start with name-based category suggestions; existing category selections migrate automatically. Once saved, sections use your chosen category IDs, with settings kept separately for each source.
- Release-year filters on Discover, Movies and Series use available release metadata and explicitly bracketed title years. Undated titles remain available under All years. Live channels remain visible when filtering a mixed-content section by year.
- Movie details, series overviews, expandable episode descriptions, and a player info panel fetch provider descriptions when available.
- A separate category search field filters provider categories independently of title search.
- Live TV, Movies and Series libraries with scrollable provider categories, search and alphabetical sorting.
- Favorites for channels, films and series.
- Watch history, last-watched episode, individual history removal and history clearing.
- Movie/episode resume positions, saved every five seconds and when leaving the player.
- Continue watching shows one unfinished episode per series, plus unfinished films.
- Numerically sorted seasons and episodes, next-episode controls and an eight-second autoplay countdown with cancellation.
- Seek, volume, speed, fullscreen and VLC audio/subtitle selection when tracks are available.
- Double-click the native title bar or the empty library header to maximize to the current screen; double-click again to restore the previous frame.
- The single right-hand playback clock starts with remaining time. Click it to cycle through current time, current/total time, and remaining time; the preference is remembered. The old left-hand elapsed clock has been removed.
- Player title and controls fade after five idle seconds during playback, return with pointer/keyboard activity, and stay visible while paused, loading or interacting with the info panel. Click the video to play/pause; Up/Down changes volume in five-point steps.
- Light, Dark, and System appearance in Settings, plus a quick theme switch in the library toolbar.
- Saved accounts open the dashboard before the catalog finishes loading. Startup shows a brief library-opening state while reading Keychain, with no login-form flash. Offline/provider errors keep the saved account on the dashboard and offer Retry or Update connection. Keychain access errors have a separate retry screen; only a missing saved account opens the initial login form.
- Loading, empty and error states, cancellation, retry, refresh and source switching.

Login details and playlist URLs are saved in macOS Keychain. Favorites, history and settings are scoped to each source in `~/Library/Application Support/Luma`, with private file permissions. Disconnect removes the current Keychain login and keeps local watch progress for reconnection. No credentials, content or provider catalog are embedded in the application or repository.

## Shortcuts

| Key | Action |
| --- | --- |
| ⌘O | Connect a source |
| ⌘F | Search |
| ⌘R | Refresh library |
| ⌘1–⌘7 | Navigate library sections |
| ⌘, | Settings |
| Space or click video | Play / pause |
| ↑ / ↓ | Volume up / down (5%) |
| ← / → | Seek ten seconds |
| F | Toggle video fullscreen |
| Esc | Close player |

## Checks

```sh
./scripts/test.sh
```

The dependency-free Swift runner works with Command Line Tools, which do not include XCTest. It checks M3U parsing, category fidelity, duplicate filtering, stable identifiers, relative URLs, series grouping, numeric episode ordering, Continue watching, persisted history/favorites stream URL encoding, provider release metadata, Discover category matching, backward compatibility of saved user data, three-mode playback time, five-second player controls, Discover migration (including deliberately empty selections), mixed-content sections, favorite-type filters, and saved section order.

Optional provider integration checks use environment variables, never source-code credentials:

```sh
export LUMA_TEST_SERVER='https://your-provider.example'
export LUMA_TEST_USER='your-user'
export LUMA_TEST_PASSWORD='your-password'
./scripts/test.sh
python3 scripts/check-playback.py
```

The integration runner checks authentication, catalog integrity and episode retrieval. The Python playback check uses the installed VLC decoder with dummy output and requires decoded video frames and an advancing playback clock. It tries up to three entries each for movies and live TV because providers may list offline streams. Provider availability and codec support still determine whether a particular item plays.

Development builds also include opt-in render checks in `DebugQA.swift`; these are excluded from release builds. No test login is saved to Keychain.

## Structure

- `Sources/LumaCore`: catalog models, Xtream API, M3U parser and watch-state logic.
- `Sources/Luma`: SwiftUI application, native video surface, playback controller, Keychain and persistence.
- `Sources/CVLC`: a dynamically loaded VLC bridge, with no third-party build dependencies.
- `Tests/LumaCoreTests`: executable core and optional integration checks.
