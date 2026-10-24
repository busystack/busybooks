#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
hardening_root=$(mktemp -d /tmp/busybooks-format-hardening-XXXXXX)
trap 'rm -rf "$hardening_root"' EXIT
hardening_dart="${BUSYBOOKS_DART_BIN:-dart}"
g++ -std=c++17 tools/native_engine_probe.cc -o "$hardening_root/probe" $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1)
fixtures=("$PWD/test/fixtures/reflowable.epub" "$PWD/test/fixtures/formats/fiction-utf8.fb2" "$PWD/test/fixtures/text.pdf" "$PWD/test/fixtures/formats/orientation6-fill.cbz")
for fixture in "${fixtures[@]}"; do
  source="$hardening_root/$(basename "$fixture")"
  cp "$fixture" "$source"
  descriptor="$hardening_root/descriptor.json"
  "$hardening_dart" run tools/prepare_format_acceptance.dart "$hardening_root/profile-$(basename "$fixture")" "$source" > "$descriptor"
  readarray -t fields < <(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["format"]);print(d["cacheDirectory"]);print(d["publicationPath"])' "$descriptor")
  if [[ "${fields[0]}" == pdf ]]; then
    # Replace the pathname after verification, before the native resource fetch.
    python3 - "$source" <<'PYTHON'
import os,sys
from pathlib import Path
source=Path(sys.argv[1]);before=source.stat()
replacement=source.with_suffix('.replacement.pdf')
replacement.write_bytes(bytes(before.st_size))
os.utime(replacement,ns=(before.st_atime_ns,before.st_mtime_ns))
os.replace(replacement,source)
PYTHON
  fi
  "$hardening_root/probe" "${fields[2]}" "${fields[0]}" "$PWD/assets/reader" "${fields[1]}" "$PWD/tools/hardening_native_proof.js"
done
