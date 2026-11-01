#!/usr/bin/env bash
# Inspect and install the actual strict Snap. Full desktop acceptance is separate.
set -euo pipefail
cd "$(dirname "$0")/.."
package=$(realpath "${1:?Supply the Snapcraft output}")
mkdir -p build/release/snap build/distributions
exec > >(tee build/release/snap/verification.log) 2>&1
version=$(python3 tools/release_metadata.py | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')
expected="busybooks_${version}_amd64.snap"
test "$(basename "$package")" = "$expected"
root="$PWD/build/release/snap/unpacked"
unsquashfs -no-progress -d "$root" "$package"
# Parse the generated Snap metadata, not just its source configuration.
/usr/bin/python3 - "$root/meta/snap.yaml" "$version" <<'PY'
import pathlib, sys, yaml
metadata = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())
for key, expected in dict(name='busybooks', version=sys.argv[2], base='core24', grade='devel', confinement='strict', architectures=['amd64']).items():
    if metadata.get(key) != expected:
        raise SystemExit(f'Snap metadata {key}: expected {expected!r}, got {metadata.get(key)!r}')
app = metadata['apps']['busybooks']
if app.get('common-id') != 'io.busystack.busybooks' or app['command'] != 'busybooks':
    raise SystemExit('Snap application identity differs')
required = {'home', 'removable-media', 'x11', 'wayland', 'desktop', 'browser-support'}
if not required <= set(app['plugs']):
    raise SystemExit('Snap filesystem/desktop interfaces differ')
PY
python3 tools/verify_distribution.py --platform linux --bundle "$root" --output build/release/snap/distribution.json
cp "$root/share/busybooks/flutter-toolchain.json" build/release/snap/flutter-toolchain.json
python3 tools/probe_linux_mime.py "$root/share/mime"
test -f "$root/meta/gui/io.busystack.busybooks.desktop"
rg '^Exec=.*busybooks' "$root/meta/gui/io.busystack.busybooks.desktop"
find "$root/usr/lib" -name 'libwebkit2gtk-4.1.so*' -print -quit | rg .
find "$root/usr/lib" -name 'libhandy-1.so*' -print -quit | rg .
find "$root" -name 'WebKitWebProcess' -print -quit | rg .
snapcraft --version > build/release/snap/snapcraft-version.txt
# --dangerous bypasses the absent Store assertion only; confinement stays strict.
confinement=$(timeout 30s snap debug confinement)
printf '%s\n' "$confinement" > build/release/snap/host-confinement.txt
test "$confinement" = strict
sudo snap install --dangerous "$package"
snap list busybooks | tee build/release/snap/installed.txt
snap connections busybooks | tee build/release/snap/connections.txt
# Verify the installed mounted bytes. Never execute the unpacked binary as proof
# that strict confinement works.
python3 tools/verify_distribution.py --platform linux --bundle /snap/busybooks/current --output build/release/snap/installed-distribution.json
xvfb-run -a dbus-run-session -- python3 tools/probe_linux_opening.py --snap
sudo snap remove --purge busybooks
cp "$package" "build/distributions/$expected"
python3 tools/release_metadata.py --check-event --evidence build/release/snap --package "build/distributions/$expected"
printf '%s\n' '{"status":"passed","checks":["metadata","architecture","vendor bytes","runtime inventory","desktop identity","strict installation","mounted inventory","Xvfb installed application launch and 19 rendered/saved fixtures through home interface","removal"],"manualAcceptance":"Real desktop portals/chooser, Wayland, removable-media, GPU, speech and complete GUI acceptance remain required"}' > build/release/snap/package-results.json
rm -rf "$root"
