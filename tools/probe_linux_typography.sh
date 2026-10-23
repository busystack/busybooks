#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_root=$(mktemp -d /tmp/busybooks-typography-XXXXXX)
trap 'rm -rf "$probe_root"' EXIT
python3 tools/make_typography_fixtures.py "$probe_root"
dart run tools/prepare_typography_probe.dart "$probe_root" "$probe_root/typography.epub" --saved-typography > "$probe_root/descriptor.json"
g++ -std=c++17 -Wall -Werror tools/native_typography_probe.cc linux/runner/reading_fonts.cc -o "$probe_root/probe" $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1 pangocairo pangoft2 fontconfig)
probe_cache=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["cacheDirectory"])' "$probe_root/descriptor.json")
FONTCONFIG_FILE="$probe_root/fonts.conf" "$probe_root/probe" "$probe_root/typography.epub" "$probe_cache" "$PWD/assets/reader" "$PWD/tools/typography_native_proof.js" "$probe_root" renderer
for probe_mode in weights specialist specialist-cold cancellation; do
  FONTCONFIG_FILE="$probe_root/fonts.conf" "$probe_root/probe" "$probe_root/typography.epub" "$probe_cache" "$PWD/assets/reader" "$PWD/tools/typography_regressions_proof.js" "$probe_root" "$probe_mode"
done
if [ -x "${BUSYBOOKS_CHROMIUM_BIN:-/usr/bin/google-chrome}" ]; then
  FONTCONFIG_FILE="$probe_root/fonts.conf" node tools/probe_chromium_typography.mjs "$probe_root/native-fonts.json"
fi

for probe_mode in fixed pdf; do
  if [ "$probe_mode" = fixed ]; then probe_publication="$PWD/test/fixtures/fixed-layout.epub"; else probe_publication="$PWD/test/fixtures/text.pdf"; fi
  dart run tools/prepare_typography_probe.dart "$probe_root" "$probe_publication" > "$probe_root/$probe_mode.json"
  probe_cache=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["cacheDirectory"])' "$probe_root/$probe_mode.json")
  FONTCONFIG_FILE="$probe_root/fonts.conf" "$probe_root/probe" "$probe_publication" "$probe_cache" "$PWD/assets/reader" "$PWD/tools/typography_fixed_proof.js" "$probe_root" "$probe_mode"
done
