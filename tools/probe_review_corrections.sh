#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
review_root=$(mktemp -d /tmp/busybooks-review-corrections-XXXXXX)
trap 'rm -rf "$review_root"' EXIT
review_dart="${BUSYBOOKS_DART_BIN:-dart}"
export BUSYBOOKS_COMIC_DECODER="${BUSYBOOKS_COMIC_DECODER:-$PWD/build/linux/x64/release/bundle/busybooks_comic_archive}"
python3 tools/make_review_fixtures.py "$review_root/fixtures"
g++ -std=c++17 tools/native_engine_probe.cc -o "$review_root/probe" $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1)
fixtures=("$review_root/fixtures/reader-review.epub" "$review_root/fixtures/reader-review-epub2.epub" "$review_root/fixtures/reader-review.kepub.epub" "$review_root/fixtures/reader-review.fb2" "$review_root/fixtures/reader-review.fbz" "$review_root/fixtures/comic-review.cbz" "$PWD/test/fixtures/text.pdf")
for fixture in "${fixtures[@]}"; do
  descriptor="$review_root/descriptor.json"
  "$review_dart" run tools/prepare_format_acceptance.dart "$review_root/profile-$(basename "$fixture")" "$fixture" > "$descriptor"
  readarray -t fields < <(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["format"]);print(d["cacheDirectory"])' "$descriptor")
  "$review_root/probe" "$fixture" "${fields[0]}" "$PWD/assets/reader" "${fields[1]}" "$PWD/tools/review_native_proof.js"
done
fixture="$review_root/fixtures/missing-first.epub"
"$review_dart" run tools/prepare_format_acceptance.dart "$review_root/missing-profile" "$fixture" > "$review_root/descriptor.json"
cache_directory=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["cacheDirectory"])' "$review_root/descriptor.json")
"$review_root/probe" "$fixture" epub "$PWD/assets/reader" "$cache_directory" 'reject:Publication did not produce a readable first document'
