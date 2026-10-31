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
assertions and skips are unchanged. The accepted final Flutter suite passed
609 tests with zero failures and three existing skips. The subsequent Snap
correction changes packaging metadata only; its application binaries are
identical to the initial Snap's binaries.

## GTK accessibility/input risk after strict-Snap qualification

Earlier corrected portable-release acceptance encountered a new `SIGSEGV`
during AT-SPI inspection and keyboard input on physical GNOME X11, without a
shutdown request.
The fault is in GTK's accessibility keyboard-listener traversal. A controlled
trace on the unchanged release measured AT-SPI client disconnection reentering
that callback, deleting its exact live `GSList` node, and returning to GTK with
the iterator pointing to freed storage. This establishes an unsafe runtime
interval in the same faulting loop; the original uncontrolled crash has no
same-execution debugger stack linking its node identity to that trace.

The qualified strict Snap, local revision `x2`, actually loads its staged
`libgtk-3-0t64 3.24.41-4ubuntu1.3` at
`/snap/busybooks/x2/usr/lib/x86_64-linux-gnu/libgtk-3.so.0.2409.32`.
Loaded mappings, package provenance and the binary listener loop establish that
the [upstream correction](https://github.com/GNOME/gtk/commit/e6372d2923d04bb2bdc88fa526ca57704ca2664a)
is absent: the iterator advances after the callback. The GNOME content provider's
different GTK version is not the GTK loaded by BusyBooks.

Ordinary reading, editing and keyboard acceptance in the corrected Snap did not
reproduce this crash. Normal read-only AT-SPI inspection also did not crash, but
a Flutter accessibility-node query timed out and other queried nodes were stale;
full screen-reader workflows remain unqualified. No accessibility service was
deliberately interrupted during this acceptance. The earlier controlled
disconnection trace demonstrated node invalidation without a crash. The earlier
uncontrolled crash during accessibility inspection and keyboard input therefore
cannot be classified as occurring only under deliberate fault conditions.

The recommendation is **PRERELEASE ONLY**: ordinary functionality passed, while
the historical accessibility crash, uncorrected loaded GTK and incomplete
assistive-tool coverage remain material limitations. These bounded results
neither prove permanent crash elimination nor demonstrate a current ordinary-use
GTK failure. No third-party modification, accessibility-disable setting, vtable
interception or speculative input workaround was adopted. This remains separate
from the accepted renderer/compositor shutdown correction. Historical raw traces
remain under ignored `evidence/release-final-20261030/`; current package evidence
is under `evidence/selection-menu-20261030/snap-qualification/`.

## Selection controls and reported freeze

Automatic text and region selection now use the primary window's existing
native menu service. Selection actions retain their captured source and reject
retired ownership independently of secondary popovers. Add Note and Edit Note
use the existing protected Notebook editor, including in Split.

Physical Ubuntu diagnostics reproduced the former Material selection popup and
its dismissal on resize, but did not reproduce the reported freeze. Removing
that automatic secondary-engine presentation does not establish the freeze's
original cause or resolve the separate GTK accessibility/input risk above.
Strict-Snap acceptance verified five native selection-menu map/dismiss cycles,
Copy, selection Search and Look Up's consent/no-entry response, with continued
keyboard input and no disappearing Material popup, blocked input or freeze.
See the [selection ownership contract](reading-workspace.md#selected-text-actions).

## Distribution and desktop coverage

The actual `core24`/`amd64`, `strict`, `devel` Snap was built with official
Snapcraft 9.2.1 and unmodified official Flutter 3.47.5. Tested source is
`4cdf05128df63f5d85402baf4d9140711e6b5a2e`; the corrected artifact is
`busybooks_0.1.0_amd64-webkit-layout.snap`, SHA-256
`72f927ee96f15d554d03164281688cace92dd91689d7c12911f4f1bbdf015d05`.
It was installed locally as `x2` with `--dangerous`, without `--devmode`;
the running process label was `snap.busybooks.busybooks (enforce)`.

The initial Snap paired staged WebKit 2.52.6 with GNOME-provider 2.50.4 helpers
and injected bundle through the extension's generated layout. Both PDF and EPUB
reader processes terminated before rendering. A recipe-only layout override now
binds that directory to the staged WebKit tree. Actual helper hashes match the
staged runtime, and the installed corrected package renders the exact requested
Grokking Algorithms PDF, representative EPUB, CBZ and CBR fixtures. Application,
AOT, Flutter engine and comic-decoder binaries are unchanged by this correction.

Acceptance on physical GNOME X11/NVIDIA covered window identity and packaged
icon, native file chooser and menus, WebKit/SQLite initialization, Notebook note
creation/editing, Split, bookmarks and reading-position persistence, and live
System appearance changes. Home files and a CBZ under `/mnt/Media` worked with
the existing `home` and connected `removable-media` interfaces. Backup/restore
preserved annotations, book anchors and preferences with SQLite integrity `ok`;
generated cover caches are intentionally omitted from backups. With only the
Snap's `network` interface disconnected, the PDF rendered and a note edit saved.
The interface was restored afterward. Reopening retained page 25, one bookmark
and the exact 103-character note. The original portable profile and requested
PDF remained unchanged.

The initial package also crashed on ordinary close after failed reader startup;
a native capture located that failure in NVIDIA EGL during libc `exit`, outside
GTK's accessibility loop and the accepted Flutter teardown. The stack establishes
the failing component, not complete causality. The corrected package's two
bounded closes exited normally, once under GDB and once untraced. This does not
establish permanent elimination of the earlier driver-stack failure.

Confinement diagnostics include denied fallback library paths, hardware probes
and a nested portal call; none prevented the completed workflows. No interfaces
were added. Read Aloud reported Speech Dispatcher unavailable. Its packaged
executable and library load, but the environment provided no accessible speech
service, so audible narration remains unqualified. Physical removable-device
hotplug and full screen-reader workflows were not tested. No package was published.

Windows executable/native checks do not qualify runtime installer execution or
file associations; test those through the actual package described in
[windows.md](windows.md#packaging-and-installation). Native functional checks in
a VM do not establish physical GPU/driver performance. Complex/CJK IME,
audible narration quality, full screen-reader/high-contrast coverage and physical
Wayland/fractional-monitor behavior require explicit platform acceptance.

Supported format exclusions and rejection limits are documented in
[readers.md](readers.md) and [storage.md](storage.md#publication-resource-budgets).
