# Android TV validation — 24 October 2026

## Verified

- Gradle debug and signed release APK assembly succeed with Android Gradle Plugin 9.3.0, Gradle 9.5.1, SDK 35 and JDK 25.
- All eight JVM parser/model tests pass: quoted metadata and relative URLs; deduplication/stable IDs; live/movie classification; M3U series grouping and numeric season ordering; credential path encoding; episode JSON persistence; invalid input/protocol rejection; release-year interpretation.
- Release lint passes with zero errors. Remaining warnings concern platform modernization, translation/localization, broad RecyclerView updates and small artwork drawing allocations; the fixed landscape layout is intentional for TV.
- APK signature verification passes for v1 and v2, covering older Android versions. Signing material is stored outside Git under `~/.config/luma/`.
- Five instrumentation test groups pass on an Android 12 / API 31 ARM64 Android TV emulator at 1920×1080:
  1. D-pad focus moves between sidebar destinations; sample catalog, movie details, seasons, favorites and light appearance render successfully.
  2. AES-GCM watch-state round trip retains favorites and resume data, excludes plaintext item metadata from disk, and marks completed playback correctly.
  3. The actual Media3 player decodes an original generated H.264 fixture, resumes from 12 seconds, advances past 13.5 seconds and persists progress after closing.
  4. The actual Java HTTP client authenticates against a local Postman simulation, retrieves all three catalogs/categories, enriches movie descriptions, sorts episodes across seasons and rejects invalid dummy credentials. Request events were inspected in the simulation log.
  5. The real player reaches the end of an episode, executes the eight-second countdown, advances to a second-season episode and keeps the previous episode completed in encrypted storage.
- Actual emulator screenshots were captured by Android instrumentation. Marketing captures use fictional sample titles and procedural placeholder artwork. The sample library is a debug-only UI action. No provider login or real provider catalog is included.
- The final Java source was formatted; release assembly, JVM tests and lint were rerun after formatting. The packaged APK is copied from that release build.

## Limits

No physical Mi Box is connected. These checks establish emulator behavior and compatibility against the local Xtream fixture, not verified playback on every provider, firmware, codec or TV. Validate the signed APK on the target Mi Box with authorized streams before describing that device as certified. The app caps adaptive video selection to 1080p by default; it cannot convert a single 4K provider stream into 1080p.

The Postman CLI was signed out, so the owning-provider mock search could not run. The committed read-only fixture mirrors Luma's existing macOS Xtream contract and uses fictional metadata plus dummy credentials. No Postman cloud resources were pushed or deployed.
