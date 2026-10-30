# Known issues and qualification limits

## Intermittent Linux shutdown abort

Linux release-window close has produced both `SIGABRT` / `g_mutex_clear` in
Flutter 3.47.5's compositor teardown and a separate queued-redraw `SIGSEGV`.
The `SIGSEGV` cause is measured: GTK destroys a child renderer while raster
presentation still owns its parent view; the renderer's later reference fails
and the queued redraw receives null. On the actual GNOME X11 desktop, both the
normal application and a diagnostic build excluding reader-host construction
had 29 normal closes and one `SIGSEGV` in 30 trials each. Reader-host
initialization is therefore unnecessary for that failure.

The adopted application correction retains GTK descendants during view
retirement, drains existing parent references, and releases ownership on the GTK
thread with an actual-finalization barrier and balanced application holds. It
also removes the embedded view's unintended main-window quit callback and
initializes the official GTK settings notification consumer in primary Linux
bootstrap. The previously surviving engine owner was an unanswered
`gtk/settings` notification task. Subsequent native traces verified its release,
actual primary and secondary engine finalization, zero retirement counters and
normal process exits. The SDK, bundled engine and vendored dependencies are
unchanged; no forced exit, forced engine disposal or timing delay implements
this correction.

The original terminal `SIGABRT` remains unverified. The 30 October follow-up did
capture GLib's already-taken failure branch: it tested `1` for the exact
initialized compositor mutex still held by raster presentation. The same-stop
GTK/raster stacks, saved compositor and mutex pointers now establish disposal
during active presentation. A competing framebuffer `SIGSEGV` terminated that
process before `SIGABRT`; it is distinct from the earlier queued-redraw crash.
The existing descendant-retirement correction protects the measured interval;
no further lifecycle change was made. See the
[mutex follow-up and precise signal limits](linux-shutdown-mutex-followup.md).

Focused tests, the native input gate and the production release build pass.
The final executable completed 50 ordinary closes each from Welcome, the exact
user PDF and PDF with Go To opened/dismissed: 150 normal exits with no surviving
owned processes. Separate production tracing verified both views, renderers,
compositors and engines finalized on GTK's thread. A disposable blocked-note-write
case retained the window until unlock, saved the exact 64-character note and
exited normally. Its original and copied profiles reopened with that note,
unchanged settings and SQLite integrity `ok`. Earlier failed diagnostics remain failed.
Earlier physical GPU acceptance was unavailable after repeated NVIDIA kernel
failures. On a healthy 30 October boot, the corrected installed release completed
five Welcome closes and five exact-PDF/Go To closes on physical GNOME X11/NVIDIA,
all with natural status zero and no new kernel GPU fault. These bounded physical
checks are separate from the private Mesa/Xvfb OpenGL comparison and do not prove
permanent abort elimination or physical Wayland acceptance.
See [shutdown causality and verification limits](linux-shutdown-causality.md)
and [the guarded-close driver](../../tools/README.md#linux-workspace-and-shutdown-diagnostics).

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
