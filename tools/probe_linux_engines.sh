#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
profile=$(mktemp -d /tmp/busybooks-engine-proof-XXXXXX)
binary=$(mktemp /tmp/busybooks-engine-probe-XXXXXX)
trap 'rm -rf "$profile"; rm -f "$binary" "$profile-input.json"' EXIT
dart run tools/prepare_engine_probe.dart "$profile" > "$profile-input.json"
mv "$profile-input.json" "$profile/input.json"
g++ -std=c++17 tools/native_engine_probe.cc -o "$binary" $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1)
while IFS=$'\t' read -r publication format cache_directory; do
  "$binary" "$publication" "$format" "$PWD/assets/reader" "$cache_directory"
done < <(python3 -c 'import json,sys; [print(b["path"]+"\t"+b["format"]+"\t"+b["cacheDirectory"]) for b in json.load(open(sys.argv[1]))]' "$profile/input.json")
