#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
format_probe_root=$(mktemp -d /tmp/busybooks-format-native-XXXXXX)
trap 'rm -rf "$format_probe_root"' EXIT
g++ -std=c++17 tools/native_engine_probe.cc -o "$format_probe_root/probe" $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1)
export BUSYBOOKS_COMIC_DECODER="${BUSYBOOKS_COMIC_DECODER:-$PWD/build/linux/x64/release/bundle/busybooks_comic_archive}"
default_fixtures=(epub2.epub epub2-utf16.epub epub2-dtbook.epub epub2-mime-aliases.epub epub2-xml-island.epub representative.kepub.epub reflowable.kepub.epub fiction-utf8.fb2 fiction-utf16.fb2 fiction-cp1251.fb2 fiction.fb2.zip fiction.fbz comic-deflated.cbz comic-stored.cbz comic-codecs.cbz comic-rar4-stored.cbr comic-rar4-compressed.cbr comic-rar4-solid.cbr comic-rar5-stored.cbr comic-rar5-compressed.cbr comic-rar5-solid.cbr comic-long.cbz)
format_fixtures=("${default_fixtures[@]}")
if (($#)); then format_fixtures=("$@"); fi
for fixture in "${format_fixtures[@]}"; do
  descriptor="$format_probe_root/$fixture.json"
  dart run tools/prepare_format_acceptance.dart "$format_probe_root/$fixture-profile" "$PWD/test/fixtures/formats/$fixture" > "$descriptor"
  readarray -t fields < <(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["format"]);print(d["cacheDirectory"])' "$descriptor")
  printf 'FORMAT_NATIVE %s\n' "$fixture"
  python3 -c 'import json,sys;print("FORMAT_PREPARATION_MS",json.load(open(sys.argv[1]))["preparationMs"])' "$descriptor"
  "$format_probe_root/probe" "$PWD/test/fixtures/formats/$fixture" "${fields[0]}" "$PWD/assets/reader" "${fields[1]}" "$PWD/tools/formats_native_proof.js" | tee "$format_probe_root/$fixture.log"
  dart run tools/validate_native_locations.dart "${fields[0]}" "$format_probe_root/$fixture.log"
  if [[ "${fields[0]}" = epub || "${fields[0]}" = fb2 ]]; then
    python3 -c 'import json,sys;d=[json.loads(s) for s in open(sys.argv[1]) if s.startswith("{\"type\":\"formatSaved\"")];json.dump(d[-1],open(sys.argv[2],"w"))' "$format_probe_root/$fixture.log" "$format_probe_root/saved.json"
    dart run tools/prepare_format_acceptance.dart "$format_probe_root/$fixture-profile" "$PWD/test/fixtures/formats/$fixture" "$format_probe_root/saved.json" > "$descriptor"
    printf 'FORMAT_NATIVE_RESTART %s\n' "$fixture"
    "$format_probe_root/probe" "$PWD/test/fixtures/formats/$fixture" "${fields[0]}" "$PWD/assets/reader" "${fields[1]}" "$PWD/tools/formats_native_proof.js" "$format_probe_root/saved.json" | tee "$format_probe_root/$fixture-restart.log"
    dart run tools/validate_native_locations.dart "${fields[0]}" "$format_probe_root/$fixture-restart.log"
  fi
done

for fallback in cycle missing; do
  fixture="epub2-fallback-$fallback.epub"
  dart run tools/prepare_format_acceptance.dart "$format_probe_root/$fixture-profile" "$PWD/test/fixtures/formats/$fixture" > "$format_probe_root/fallback.json"
  cache=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["cacheDirectory"])' "$format_probe_root/fallback.json")
  if [ "$fallback" = cycle ]; then expected="Cyclic EPUB manifest fallback"; else expected="Missing EPUB manifest fallback"; fi
  "$format_probe_root/probe" "$PWD/test/fixtures/formats/$fixture" epub "$PWD/assets/reader" "$cache" "reject:$expected"
done
