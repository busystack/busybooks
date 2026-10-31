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

## Focus-test transition sequencing

The retained-reader focus test now waits for the mounted reader's asynchronous
reopen to finish its initial `focusBook` handoff. The fixture's existing
`interactive` state alone did not establish that boundary. A controlled delayed
reopen reproduced the missing second native-focus query: the initial handoff
focused and marked the new revision as already mirrored before the test's next
native event. Skipping reconciliation in that state is correct application
behavior. The test now finishes initialization before exercising its later
focus-loss and Notebook-handoff assertions; production focus behavior, deadlines,
assertions and skips are unchanged. Release qualification still requires a
completed passing full suite on the final source.

## GTK accessibility/input crash blocks Linux qualification

The corrected installed release encountered a new `SIGSEGV` during AT-SPI
inspection and keyboard input on physical GNOME X11, without a shutdown request.
The fault is in GTK's accessibility keyboard-listener traversal. A controlled
trace on the unchanged release measured AT-SPI client disconnection reentering
that callback, deleting its exact live `GSList` node, and returning to GTK with
the iterator pointing to freed storage. This establishes an unsafe runtime
interval in the same faulting loop; the original uncontrolled crash has no
same-execution debugger stack linking its node identity to that trace.

The installed official Ubuntu GTK package is `3.24.41-4ubuntu1.3`, also the
available candidate at qualification. The
[upstream listener implementation](https://github.com/GNOME/gtk/blob/3.24.41/gtk/a11y/gtkaccessibilityutil.c)
iterates the mutable list across callbacks. No GTK/ATK, Flutter, WebKit or vendor
change, accessibility-disable setting, vtable interception or input workaround
has been adopted. Installed desktop qualification remains blocked pending a
permitted runtime correction and renewed acceptance. This is separate from the
accepted renderer/compositor shutdown correction. Raw logs and matching-node
observations are retained under ignored `evidence/release-final-20261030/`.

## Selection controls and reported freeze

Automatic text and region selection now use the primary window's existing
native menu service. Selection actions retain their captured source and reject
retired ownership independently of secondary popovers. Add Note and Edit Note
use the existing protected Notebook editor, including in Split.

Physical Ubuntu diagnostics reproduced the former Material selection popup and
its dismissal on resize, but did not reproduce the reported freeze. Removing
that automatic secondary-engine presentation does not establish the freeze's
original cause or resolve the separate GTK accessibility/input blocker above.
See the [selection ownership contract](reading-workspace.md#selected-text-actions).

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
