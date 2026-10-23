# Validation — 23 October 2026

- Native debug build succeeded with Apple's Command Line Tools.
- Eight local check groups passed: playlist/category parsing, stable IDs and duplicate filtering, invalid input, M3U series grouping, cross-season episode order, Continue watching and persisted favorites/history, invalid progress, and credential/stream URL encoding.
- Live integration checks passed against the supplied account: authentication, catalog/category integrity and episode retrieval. The account's catalog contained 15,962 live entries, 69,672 movies and 7,492 series at the time of testing.
- The real VLC decoder played a provider movie and a live stream, decoded video frames and advanced its playback clock. Some initially sampled provider entries were unavailable; later candidates played successfully.
- The running native application loaded 93,126 titles across 710 categories (including fallback groups), opened the VLC player and saved live playback progress.
- Native AppKit renders of the connection screen, library and player controls were generated and inspected.
- A generated two-episode M3U fixture played through the first episode, completed the eight-second countdown, crossed from season 1 to season 2, and persisted both episodes as completed. This check caught and verified a fix for completed progress being overwritten while closing a finished player.
- A generated 30-second fixture resumed from a saved 12-second position and saved progress at 17.535 seconds after leaving playback.

Development QA renders and reports are generated under `build/qa/` and are not bundled with the application. Test clips are temporary generated files, not supplied content. Test credentials are not committed or included in the app, and development QA does not save a login to Keychain.

## Luma 1.1 improvements

- Twelve local check groups pass, including provider release dates/descriptions, Discover grouping by media kind, legacy favorites/history decoding, and the five-second control deadline.
- Live provider authentication, catalog integrity, movie detail and series/episode retrieval checks pass.
- An isolated native QA app verified all four Discover sections, release-year filtering, View all retaining its section/year, independent category search, and movie/episode descriptions.
- Light-mode Discover and category browser renders were inspected. Dark mode remains available, with System appearance and persisted preference selection.
- Native keyboard interaction confirmed Up changes volume from 85 to 90 and Down restores 85; bounds are 0–100. Clicking the native video surface changed Pause to Play and back.
- The native player hides its controls after five idle seconds, reveals them on activity, and keeps paused/loading/info states visible.
- Testing exposed a pre-existing VLC/Cocoa plugin unload crash. The bridge now owns one process-wide VLC engine and pins Cocoa callback modules; individual media players still release normally. Repeated player open/close checks pass with this lifecycle.

The QA app and generated media remain development artifacts under `build/` and `/tmp/`; release builds exclude the QA probes and credentials.
- Native fullscreen verification confirmed the title/controls leave the accessibility tree and screen while video continues; Up reveals them again and changes volume. Escape returns safely to the library after the lifecycle fix.
- Native category search, category selection, release-year menu selection and the light-theme toolbar switch were exercised together successfully.
- Saved-login reads and writes now run off the main actor, so a pending macOS Keychain approval cannot freeze the interface. The final signed 1.1 release was reopened and its login interface verified responsive.

## Luma 1.2 playback and window controls

- Thirteen local check groups pass, including the three-mode time cycle, hour-long media, missing durations, invalid times, and bounds at the end of playback.
- Native QA confirmed F enters and exits fullscreen; the button icon follows the actual window state. Modified shortcuts remain available, and holding F does not repeatedly toggle during a transition.
- Window QA confirmed maximizing uses the screen's visible frame and restores the previous window size. Native title-bar double-clicks were exercised, as was the noninteractive custom library header.
- Native clicking verified Remaining time → Current time → Current / total time → Remaining time. The timeline has only one right-side time button and no left-side elapsed text. The format is saved as a preference.

## Luma 1.3 Discover customization — 24 October 2026

- Fifteen local check groups pass, including migration of existing Discover category choices, explicitly empty category selections, an intentionally empty layout, mixed categories/individual titles, favorite media-type filters, and Codable persistence of section settings/order.
- An isolated eight-item M3U QA catalog verified custom Series category selection, one section combining Live TV/Movies/Series, View all retaining section/year and live entries, live-only dynamic favorites, section reordering, persisted renaming/selections, and section removal preserving favorites. All nine Discover-specific assertions passed.
- Native accessibility inspection confirmed the section manager exposes saved sections, editable names, separate Live TV/Movies/Series tabs, category selection/search, individual-title selection, and ordering controls.
- Native interaction created and renamed a new section, selected one category each from Live TV, Movies, and Series, added an individual series, and verified all four expected items appeared together on Discover. A second Series category was added to the existing Bollywood row and appeared immediately.
- Native AppKit renders of the section editor in light/dark appearances and the live-favorites editor were inspected.
- Release 1.3 built successfully; the application signature and Info.plist were verified before packaging.

## Luma 1.3.1 saved-session startup — 24 October 2026

- Fifteen core check groups continue to pass. Eleven isolated startup assertions passed: no login before Keychain returns; dashboard before a deliberately delayed catalog completes; successful saved-account load; initial login with no saved account; Keychain failure/retry; offline launch/retry; expired-credential recovery on the dashboard; cancellation preventing late account restoration; and the visible restored dashboard.
- Startup and dashboard AppKit renders were inspected. Credentials remain in Keychain, and tests inject an isolated fixture account rather than reading or changing the real saved login.
- Keychain errors are distinguished from a missing login. Library loading and provider errors no longer leave returning users on the connection form.
- Signed release 1.3.1 passed signature/Info.plist checks, reopened successfully, and restored the real saved provider account and catalog without entering credentials.

## Android TV companion and marketing — 24 October 2026

- The original macOS source was committed and pushed with GitHub CLI to the private `mosiddiquithedev/luma-iptv` repository. The owner confirmed using the signed-in account. All 15 existing Swift core check groups passed; optional live provider integration was not rerun in this task.
- A native Android TV companion, signed universal APK, source, tests and build/signing instructions were added. See `android/VALIDATION.md` for eight unit tests, five Android TV instrumentation groups and physical-device limitations.
- Actual macOS fixture captures and Android TV emulator screenshots are used on a responsive marketing page. Platform tabs, screenshot enlargement, FAQ disclosure, desktop/narrow layouts and local assets were verified; the Android and Mac downloads are included with SHA-256 checksums.
- The owner requested that the marketing page remain private for review. GitHub also remains private.
