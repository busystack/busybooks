#!/usr/bin/env bash
# Complete Linux verification. Snap packaging follows this gate in CI.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/release/linux
exec > >(tee build/release/linux/verification.log) 2>&1
trap 'code=$?; printf "{\"exitCode\":%s,\"sourceRevision\":\"%s\"}\n" "$code" "$(git rev-parse HEAD)" > build/release/linux/automated-results.json' EXIT
python3 tools/release_metadata.py --toolchain --evidence build/release/linux
python3 tools/verify_vendor.py
python3 -m unittest discover -v -s test/tools -p '*_test.py'
# Both native desktop integration tests are mandatory on the CI Linux host.
command -v gio
command -v gtk-update-icon-cache
flutter pub get --enforce-lockfile
git diff --exit-code -- pubspec.lock
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test tools
flutter analyze
flutter test
curl --fail --location --retry 3 https://github.com/w3c/epubcheck/releases/download/v5.4.0/epubcheck-5.4.0.zip --output "$RUNNER_TEMP/epubcheck.zip"
printf '%s  %s\n' 33350c61038e71dfb3d45a76aed04bf5481e6d5500cb780f6e98db8bbd15a28c "$RUNNER_TEMP/epubcheck.zip" | sha256sum --check -
unzip -q "$RUNNER_TEMP/epubcheck.zip" -d "$RUNNER_TEMP/epubcheck"
python3 tools/check_epub2_fixtures.py "$RUNNER_TEMP/epubcheck/epubcheck-5.4.0/epubcheck.jar"
dart run tools/storage_probe.dart
dart run tools/move_volume_probe.dart /tmp /dev/shm
dart run tools/cache_probe.dart
dart run tools/annotation_order_probe.dart
flutter build linux --release
python3 tools/verify_vendor.py --platform linux --bundle build/linux/x64/release/bundle --build-tree build/linux/x64/release
python3 tools/verify_distribution.py --platform linux --bundle build/linux/x64/release/bundle --output build/release/linux/distribution.json
python3 tools/probe_linux_mime.py build/linux/x64/release/bundle/share/mime
export BUSYBOOKS_COMIC_DECODER="$PWD/build/linux/x64/release/bundle/busybooks_comic_archive"
python3 tools/qualify_rar.py "$BUSYBOOKS_COMIC_DECODER"
dart run tools/format_probe.dart
dart run tools/format_resources_probe.dart
node tools/reader_logic_probe.mjs
xvfb-run -a dbus-run-session -- bash tools/probe_linux_input.sh
xvfb-run -a dbus-run-session -- bash tools/probe_linux_engines.sh
xvfb-run -a dbus-run-session -- bash tools/probe_linux_typography.sh
xvfb-run -a dbus-run-session -- bash tools/probe_linux_formats.sh
xvfb-run -a dbus-run-session -- bash tools/probe_linux_format_review.sh
# A missing browser must fail instead of silently skipping this existing check.
test -x /usr/bin/google-chrome
node --experimental-websocket tools/probe_chromium_format_review.mjs
xvfb-run -a dbus-run-session -- python3 tools/probe_linux_opening.py
git diff --exit-code -- pubspec.lock
