# Known issues and qualification limits

## Intermittent Linux shutdown abort

BusyBooks can exit abnormally during window close with `SIGABRT` / `g_mutex_clear`
in Flutter 3.47.5's `FlCompositorOpenGL` teardown. The same stack was observed in
the BusyBooks baseline before workspace remediation and after it. The application
releases native reader/popover ownership before GTK destroys the main view; the
compositor abort remains unresolved.

The stack points into Flutter's teardown, but definitive attribution to Flutter
alone, rather than its interaction with BusyBooks, has not been established.
Untouched Flutter counter and independent two-view controls did not reproduce
the intermittent abort, and no exact matching released fix has been verified.

Tested reading-data hashes remained unchanged and SQLite integrity checks passed
after affected closes, including a saved large note. Those observations did not
demonstrate data corruption; they do not establish durability for every crash or
successful clean shutdown. Release decisions must account for the abnormal exit.
The pinned SDK and normal shutdown behavior remain unchanged. Reproduction uses
[the guarded-close driver](../../tools/README.md#linux-workspace-and-shutdown-diagnostics).

## Distribution and desktop coverage

Installed strict-Snap behavior remains unqualified. Build and install the actual
recipe, verify interfaces and offline WebKit/SQLite/speech/decoder resources, and
exercise formats, notes, cancellation and file opening in Home and permitted
removable-media paths. Portable Linux execution does not establish confinement.

Windows executable/native checks do not qualify runtime installer execution or
file associations; test those through the actual package described in
[windows.md](windows.md#packaging-and-installation). Native functional checks in
a VM do not establish physical GPU/driver performance. Complex/CJK IME,
audible narration quality, full screen-reader/high-contrast coverage and physical
Wayland/fractional-monitor behavior require explicit platform acceptance.

Supported format exclusions and rejection limits are documented in
[readers.md](readers.md) and [storage.md](storage.md#publication-resource-budgets).
