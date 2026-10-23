# Luma marketing page

Responsive, buildless HTML/CSS/JS with real macOS and Android TV screenshots. This Site is **private for owner review**, as requested. Do not change access without the owner's instruction. The GitHub source repository also remains private.

```sh
python3 -m http.server 8765 --directory dist
```

The page includes working platform tabs, an accessible screenshot lightbox, FAQs, installation guidance, and signed Android APK / locally signed Mac ZIP downloads. The native Android screenshots use a fictional debug sample library. macOS captures came from the isolated eight-item Discover QA fixture; no real provider catalog or login is pictured. `tv-player.png`, when retained, shows an original generated playback test clip.

The static Site is configured in `.openai/hosting.json`. The live download files are copied into `dist/downloads/` after a release build. Keep the APK signing key outside this repository and preserve it for updates. The Mac binary is locally signed and not Apple notarized. No store publication, public page access, or live-provider hardware certification is claimed.

After updates, validate all local assets/links and preview at desktop and narrow widths. Publish the exact pushed source and matching `dist` archive through Sites. Publishing a private version does not grant the audience access; the owner must explicitly request public access when ready.
