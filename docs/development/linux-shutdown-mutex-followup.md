# Linux compositor mutex follow-up, 30 October 2026

The missing same-object evidence is captured. During an ordinary close of the
preserved pre-correction release, GTK reached GLib's failing `g_mutex_clear`
branch while raster presentation still held that exact compositor's initialized
frame mutex. No production lifecycle code was changed in this follow-up.

The captured process ultimately terminated with a competing raster `SIGSEGV`,
not `SIGABRT`. The original terminal `SIGABRT` has therefore not been reproduced
in this follow-up, and its elimination remains unverified. Reaching the actual
nonzero failure branch establishes the unsafe clear operation without relying
on an inference from later signal-time memory or successful repetitions.

The [structured report](../../evidence/mutex-followup-20261030/mutex-investigation-report.json)
contains validated identities, immutable build fingerprints, results and limits.
Raw evidence remains local under ignored `evidence/mutex-followup-20261030/`.
The earlier [shutdown investigation](linux-shutdown-causality.md) is preserved.

## Single-execution identity and state

[Identity comparison 01, control](../../evidence/mutex-followup-20261030/identity-01-control/mutex.jsonl)
records all of the following in process 109439:

| Observation | Recorded value |
| --- | --- |
| OpenGL compositor, validated GType and construction generation | `0x55555e2eee60`, generation 1 |
| Initial mutex word after construction | `0` |
| Associated renderer | `0x55555aad5800` |
| Exact `frame_mutex` address | `0x55555e2eeea8` = compositor + `0x48` |
| GTK thread | LWP 109439, GDB thread 1 |
| Raster thread | LWP 109540, GDB thread 87 |
| GLib value already loaded and tested in EAX | `1` |
| Mutex memory at the failure stop | `0100000000000000` |
| Compositor caller return address | `0x7ffff72fcf73`, official ELF VA `0x4fcf73` |
| Raster presentation return address | `0x7ffff72fc9f8`, official ELF VA `0x4fc9f8` |
| Raster's saved `self` and mutex stack slots | Both match the GTK compositor and mutex addresses above |
| Thread snapshot | 105 threads, no running-thread or inspection errors |
| Actual terminal status | `SIGSEGV`, conventional status 139; debugger confirmed exit |

The breakpoint is at `g_mutex_clear + 0xb`, after GLib has loaded the word,
tested it and taken the nonzero branch. The installed GLib instruction sequence
was validated before observation. The GTK stack shows compositor disposal called
from renderer finalization, with the same renderer address recorded at startup.

At that same stop, raster is inside `fl_framebuffer_get_id`, called by
`fl_compositor_opengl_present_layers`. Its R14 and saved stack slots identify the
exact same compositor and mutex. The unchanged pinned ELF saves `self` at
presentation RSP + `0x58` and the mutex at RSP + `0x60`; the recorder retained
those raw bytes as well as decoded values. This avoids treating unrelated
compositors or an ownerless GMutex word as proof of thread identity.

In official Flutter 3.47.5, `fl_compositor_opengl.cc:69` locks this mutex,
`:198` reads the framebuffer ID, and `:204` unlocks. Disposal clears the
framebuffer and pixels before `:319` clears the mutex. GTK has therefore released
renderer/compositor ownership while that presentation is still active. Raster's
framebuffer argument is already null in this capture; after continuation its
dereference wins the race to process termination. No `SIGABRT` terminal status
is claimed for this execution. Its [native backtrace and exit record](../../evidence/mutex-followup-20261030/identity-01-control/Control-001/gdb.log)
remain available.

The previous investigation captured destructive GTK ownership and a queued
redraw receiving null separately, but lacked an aborting mutex's exact identity and
tested word. This follow-up establishes the live-lock clear condition directly;
it does not relabel every historical `SIGSEGV` as a framebuffer dereference.

## Matched comparison

Both arms used the full reader host: the preserved original release A was the
failure control; the existing corrected production release was the comparison.
Reader-host exclusion was not repeated. Both used the same official, unchanged
Flutter 3.47.5 engine, fresh profiles, private X11/Openbox display and Mesa
llvmpipe graphics. Within each phase the observer and normal operations matched.

| Phase | Runs per build | Control outcomes | Corrected outcomes | GLib failure-branch captures |
| --- | --- | --- | --- | --- |
| Lock/clear observations; 10 idle and 10 resize closes | 20 | 5 normal, 14 confirmed `SIGSEGV`, 1 unconfirmed terminal status after `SIGSEGV` stop | 20 normal | 0 |
| Minimal failure predicate; 5 idle and 5 resize closes | 10 | 3 normal, 4 confirmed `SIGSEGV`, 3 unconfirmed terminal statuses after `SIGSEGV` stops | 10 normal | 3 control, 0 corrected |
| Predicate plus saved raster-frame identity; resize closes | 3 | 2 normal, 1 confirmed `SIGSEGV` | 3 normal | 1 control, 0 corrected |

The four unconfirmed terminal records contain debugger diagnostic failures and
remain failed/incomplete observations. They are not normal closes. The decisive
identity capture has no recorder errors and a confirmed OS signal exit. All 20
corrected clear-call observations recorded zero and returned successfully.

The first phase stopped at lock, unlock, disposal and clear sites. The later
phases removed close-path stops before the already-taken failure branch to reduce
interference with the vulnerable interval. Only normal window mapping, idle,
resize and owned EWMH close requests were used. GDB neither called inferior
functions nor changed registers, data, references or scheduling policy. No
objects were manually destroyed. Breakpoints still perturb scheduling, so these
results are not estimates of ordinary crash frequency.

Flutter's renderer and the graphics implementation are separate observations:
the application had `FlutterRendererType == 0` (OpenGL), validated
`FlCompositorOpenGL` objects, and Impeller OpenGLESSDF. Its ordinary GL version
query reported OpenGL ES 3.2 Mesa 25.2.8. A separate normal GDK context identified
Mesa llvmpipe and reported its own GL 4.5 version. Flutter's software renderer,
which would use a different compositor, was not enabled. The private session had
no GPU device nodes and has been stopped.

## Existing correction and physical installed check

The existing [`gtk_view_retirement.cc`](../../linux/runner/gtk_view_retirement.cc)
correction retains GTK descendants through the lifetime of raster's parent-view
ownership and releases them on GTK's thread. That protects the measured
renderer/compositor interval. It needs no further speculative lifecycle change.
The correction's earlier actual-finalization and pending-write evidence remains
in the original report; this follow-up did not repeat or replace those checks.

The corrected production bundle was installed at
`/home/albert/.local/opt/busybooks`, with the previous bundle preserved and the
existing desktop entry unchanged. On this boot's healthy physical Ubuntu
24.04.5 GNOME X11 session, direct launches of the installed executable completed:

- [Five Welcome closes](../../evidence/mutex-followup-20261030/installed-physical-welcome/outcomes.json).
- [Five exact-user-PDF closes with Go To presented and dismissed](../../evidence/mutex-followup-20261030/installed-physical-pdf-popup/outcomes.json).

All ten natural OS exits were zero, with no forced cleanup, surviving owned
processes or new kernel GPU fault. The PDF's content hash remained unchanged.
These launches used disposable profiles and left the user's reading database
untouched. Process mappings and device descriptors confirmed NVIDIA graphics;
the application reported Impeller OpenGLESSDF, and the independent GDK probe
identified the GeForce RTX 2070 and NVIDIA 595.99.02. No software-renderer or
software-GL override was applied to the physical runs.

This is bounded installed-release shutdown acceptance on the actual X11/NVIDIA
path, separate from the isolated comparison. It does not establish permanent
`SIGABRT` elimination, physical Wayland acceptance, or a new release-wide gate.
No new production build, dependency change or full-suite result is claimed.
