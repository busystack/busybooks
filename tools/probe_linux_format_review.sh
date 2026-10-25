#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
review_root=$(mktemp -d /tmp/busybooks-format-review-XXXXXX)
trap 'rm -rf "$review_root"' EXIT
g++ -std=c++17 tools/native_engine_probe.cc -o "$review_root/probe" $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1)
export BUSYBOOKS_COMIC_DECODER="${BUSYBOOKS_COMIC_DECODER:-$PWD/build/linux/x64/release/bundle/busybooks_comic_archive}"
fixtures=(comic-deflated.cbz comic-rar5-solid.cbr epub2-raster-fallback.epub fiction-idless.fb2)
if (($#)); then fixtures=("$@"); fi
for fixture in "${fixtures[@]}"; do
  descriptor="$review_root/$fixture.json"
  saved="$review_root/$fixture-saved.json"
  for phase in initial restart; do
    args=("$review_root/$fixture-profile" "$PWD/test/fixtures/formats/$fixture")
    if [ "$phase" = restart ]; then args+=("$saved"); fi
    dart run tools/prepare_format_acceptance.dart "${args[@]}" > "$descriptor"
    readarray -t fields < <(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["format"]);print(d["cacheDirectory"])' "$descriptor")
    printf 'FORMAT_REVIEW %s %s\n' "$fixture" "$phase"
    probe_args=("$PWD/test/fixtures/formats/$fixture" "${fields[0]}" "$PWD/assets/reader" "${fields[1]}" "$PWD/tools/format_review_native_proof.js")
    if [ "$phase" = restart ]; then probe_args+=("$saved"); fi
    "$review_root/probe" "${probe_args[@]}" | tee "$review_root/$fixture-$phase.log"
    dart run tools/validate_native_locations.dart "${fields[0]}" "$review_root/$fixture-$phase.log"
    if [ "$phase" = initial ]; then
      python3 -c 'import json,sys;rows=[json.loads(line) for line in open(sys.argv[1]) if line.startswith("{\"type\":\"formatSaved\"")];json.dump(rows[-1],open(sys.argv[2],"w"))' "$review_root/$fixture-$phase.log" "$saved"
    fi
  done
done
