# Known issues and qualification limits

## Intermittent Linux shutdown abort

BusyBooks can exit abnormally during window close with `SIGABRT` / `g_mutex_clear`
in Flutter 3.47.5's `FlCompositorOpenGL` teardown. The same stack was observed in
the BusyBooks baseline before workspace remediation and after it. The application
releases native reader/popover ownership before GTK destroys the main view; the
compositor abort remains unresolved.

The October 2026 followup reproduced the abort on ordinary release-window close
from Welcome without an open book or secondary engine. Deeper GDB stacks showed
GTK child destruction reaching `FlViewRenderer` finalization and
`FlCompositorOpenGL` disposal while the compositor mutex was still in use. A
separate baseline run also stopped at a Flutter idle callback with `SIGSEGV`
after GLib reported a reference to an already-finalized object. Debug-only clean
closes do not qualify the intermittent release failure.

Application-owned retention/close sequencing candidates were tested and rejected:
retaining children through view retirement could avoid a sampled abort, but an
independent engine-shutdown hold exposed an engine reference that did not drain.
Allowing a zero exit while retained objects remain is not cleanup verification;
no such candidate or forced engine disposal is shipped. The remaining reference
owner and safe teardown ordering still need diagnosis.

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

## Intermittent focus-test transition timeout

The serial widget suite can time out in `reader_workspace_test.dart`'s
"native focus mirroring repairs confirmed loss once and rejects a later Notebook
handoff" case while waiting for its second native-focus query. The unchanged
case passed alone, with its neighboring focus cases, and after the preceding
workspace cases; the failed transition's state and cause remain unidentified.
No focus behavior, assertion or deadline was changed to hide that failure.
A targeted pass or an earlier complete suite does not replace the failed final
suite in release qualification.

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
