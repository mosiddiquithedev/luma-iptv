#!/bin/zsh
# Run instrumentation directly so Gradle teardown does not delete screenshots.
set -euo pipefail
cd "$(dirname "$0")/.."
./gradlew assembleDebug assembleDebugAndroidTest
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w -e class 'dev.luma.tv.TvExperienceTest#remoteLibraryAndMarketingCaptures' dev.luma.tv.debug.test/androidx.test.runner.AndroidJUnitRunner
mkdir -p ../build/tv-screenshots
adb pull /sdcard/Android/data/dev.luma.tv.debug/files/screenshots/. ../build/tv-screenshots/
