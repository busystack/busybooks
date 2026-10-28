#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_bin=${BUSYBOOKS_FLUTTER_BIN:-flutter}
version=$("$flutter_bin" --version --machine | python3 -c 'import json,sys;print(json.load(sys.stdin)["frameworkVersion"])')
if [[ "$version" != 3.47.5 ]]; then echo 'Flutter 3.47.5 is required' >&2; exit 1; fi
python3 tools/verify_vendor.py
python3 -m unittest discover -s test/tools -p '*_test.py'
"$flutter_bin" clean
"$flutter_bin" pub get --enforce-lockfile
"$flutter_bin" gen-l10n
"$flutter_bin" analyze
"$flutter_bin" test
"$flutter_bin" build linux --release
python3 tools/verify_vendor.py --platform linux --bundle build/linux/x64/release/bundle --build-tree build/linux/x64/release
mkdir -p build/distributions
artifact="build/distributions/busybooks-0.1.0-linux-x64.tar.gz"
package_epoch=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}
tar --sort=name --mtime="@${package_epoch}" --owner=0 --group=0 --numeric-owner -C build/linux/x64/release/bundle -cf - . | gzip -n > "$artifact"
sha256sum "$artifact" > "$artifact.sha256"
printf '%s\n' "$artifact"
