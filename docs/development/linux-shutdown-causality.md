# Linux shutdown causality and verification limits

The October 2026 investigation established a renderer lifetime race and two
application ownership gaps with the pinned official Flutter 3.47.5 / Dart 3.13.4
SDK. BusyBooks now corrects those ownership gaps in application code. The
original compositor mutex `SIGABRT` still lacks the exact matching-object and
tested-state evidence needed to establish its full cause. This report keeps
that limit separate from the confirmed `SIGSEGV` mechanism.

That paragraph records the 29 October evidence limit. The
[30 October mutex follow-up](linux-shutdown-mutex-followup.md) subsequently
captured the exact initialized mutex, GLib's tested value and matching raster
presentation pointers at the failure branch. A competing raster `SIGSEGV`
terminated that run, so the original terminal `SIGABRT` remains unverified.
The follow-up also records bounded installed-release closes on a healthy physical
X11/NVIDIA session. The historical results below are preserved.

Raw logs and execution records are retained in ignored
`evidence/shutdown-causality-20261029/`; links below resolve in the investigation
workspace. Earlier runs and rejected diagnostic attempts remain preserved.
Later task/engine traces and production build records establish the results
described here.

## Confirmed renderer lifetime failure

The actual Ubuntu GNOME X11 comparison alternated 30 guarded closes per arm on
the physical desktop. Arm A kept the normal reader host; arm B excluded its
construction while preserving the primary Flutter/GTK path. Each arm produced
29 normal closes and one `SIGSEGV`, with no other failures. Reader-host
initialization is therefore unnecessary for the observed crash. This comparison
does not establish a sole Flutter, GTK, driver or application cause.
See [A/B outcomes](../../evidence/shutdown-causality-20261029/real-attach-ab-30/outcomes.json).

A passive, instrumented arm B trace measured this order for the same renderer:

1. Raster entered presentation with renderer reference count one while holding
   a strong reference to the parent `FlView`.
2. GTK disposed that view with reference count three and recursively destroyed
   its children. The renderer reached finalization with reference count zero
   before raster acquired the redraw callback's reference.
3. Raster's later `g_object_ref` of that exact renderer returned null.
4. The queued GTK redraw received null and dereferenced its compositor field,
   terminating with `SIGSEGV`.

The trace's matching compositor mutex bytes were zero at disposal and before
clear; it did not abort. Breakpoints perturb scheduling, so this trace establishes
the captured object order rather than a failure rate or desktop acceptance.
See [trace03 analysis and raw-log pointers](../../evidence/shutdown-causality-20261029/trace03-causal-analysis.json).

The pinned SDK already includes [the redraw reference fix #186848](https://github.com/flutter/flutter/pull/186848)
and [the compositor-finalization change #188702](https://github.com/flutter/flutter/pull/188702).
Its [`FlEngine` presentation](https://github.com/flutter/flutter/blob/3.47.5/engine/src/flutter/shell/platform/linux/fl_engine.cc)
holds the parent view, but [`FlView`](https://github.com/flutter/flutter/blob/3.47.5/engine/src/flutter/shell/platform/linux/fl_view.cc)
keeps its renderer as a GTK-owned child, and
[`FlViewRenderer`](https://github.com/flutter/flutter/blob/3.47.5/engine/src/flutter/shell/platform/linux/fl_view_renderer.cc)
takes the idle reference after compositor presentation.
[GTK recursive destruction](https://docs.gtk.org/gtk3/method.Widget.destroy.html)
can release child ownership despite surviving parent references. The observed
race therefore occurs with both upstream changes already present.

## Adopted application ownership correction

[`gtk_view_retirement.cc`](../../linux/runner/gtk_view_retirement.cc) binds the
primary and embedded views without retaining them during active use. At normal
GTK destruction it retains descendants independently before recursive child
destruction, removes descendant signal handlers carrying the retiring view as
raw userdata, and adds a parent toggle reference plus an application hold.
It adds no normal parent or engine reference that would prevent existing owners
from draining.

The audited boundary is the pinned SDK's synchronous renderable removal under
the same mutex used for raster acquisition. Existing raster owners may finish;
new presentation owners cannot acquire the retired view. The final normal
parent reference schedules release on the GTK thread. Descendant references and
the toggle are released there. An actual-finalization barrier then waits for
the parent and every retained descendant, including any renderer still held by
an SDK idle, before balancing the application hold. Completion does not depend
on relative idle priorities or a fixed delay.

Two additional owners were measured and corrected:

- Realizing an embedded implicit `FlView` attaches the SDK's application-quit
  `delete-event` callback to the same main window. That callback can bypass the
  primary guarded close and retirement holds. After each embedded realization,
  BusyBooks disconnects only delete-event handlers whose userdata is that
  embedded view. The primary close guard remains in place. See the
  [measured popup ownership](../../evidence/shutdown-causality-20261029/private-A-popup-ownership-02/close-signals.jsonl).
- An unconsumed `gtk/settings` notification creates an engine-source `GTask`.
  The exact task survived close while the separate view-removal task finalized,
  explaining the previously retained primary engine. Primary Linux bootstrap
  now retains one public `YaruSettings` consumer, which constructs the official
  notification handler and acknowledges those messages. It does not call
  `init()`, add GSettings subscriptions or change theme policy. See
  [the task ownership trace](../../evidence/shutdown-causality-20261029/private-C-engine-tasks-09/lifetime.jsonl)
  and [the bootstrap consumer](../../lib/src/platform/linux_gtk_settings_notifications.dart).

The earlier child-retention candidate with an unexplained engine owner was not
accepted as cleanup verification. The adopted correction includes the measured
notification-consumer change. All adopted ownership is released at completion;
the correction uses no SDK/vendor patch, forced disposal, forced exit or
shutdown delay.

## Verified results and scope

| Check | Recorded result and limit |
| --- | --- |
| Welcome native lifecycle | [Fixed trace 10](../../evidence/shutdown-causality-20261029/device-isolated-C-engine-fixed-10/lifetime.jsonl) records creation and finalization of both notification and view-removal tasks, and primary engine arrival at `g_type_free_instance` after its inherited finalizer returned. Exit zero. |
| PDF and secondary popup lifecycle | [Fixed trace 11](../../evidence/shutdown-causality-20261029/device-isolated-C-popup-fixed-11/lifetime.jsonl) records actual finalization of both engines on GTK thread 1, both renderers/compositors, and exit zero. Its [native log](../../evidence/shutdown-causality-20261029/device-isolated-C-popup-fixed-11/C-001/gdb.log) ends with bindings, retiring views, retained widgets, holds, pending releases/finalizers and violations all zero. |
| Regression checks | [273 existing focused Dart tests](../../evidence/shutdown-causality-20261029/C-focused-regression-summary.json), [two new notification tests, formatting and analysis](../../evidence/shutdown-causality-20261029/C-gtk-settings-restart03-summary.json), and the [native input/retirement gate](../../evidence/shutdown-causality-20261029/final-native-input-gate.json) passed. These are focused checks, not a new complete platform qualification. |
| Production release | [Adopted-source build](../../evidence/shutdown-causality-20261029/Final-production-summary.json) passed locked dependency resolution, release compilation and vendor verification. Retirement diagnostics are `OFF`; the diagnostic counter symbol is absent. The bundled engine matches the unchanged official SDK and the lockfile is unchanged. |
| Production native lifecycle | [The final diagnostics-OFF executable](../../evidence/shutdown-causality-20261029/final-production-native-lifecycle/lifetime.jsonl) also completed Go To presentation/dismissal, resize and normal close with status zero. Exact `g_type_free_instance` entry observations after class finalization recorded both views, renderers, compositors and engines on GTK thread 1. |
| Pending write at close | [Disposable SQLite-lock case 04](../../evidence/shutdown-causality-20261029/pending-write-close-result04.json) kept the window alive while the note write was blocked, retained the old note until unlock, then saved the exact expected 64-character note with SQLite integrity `ok`. The [driver's final quit record](../../evidence/shutdown-causality-20261029/final-persistence-ui-04/native-actions.jsonl) reports process exit zero. [The original and copied profiles](../../evidence/shutdown-causality-20261029/final-pending-reopens/result.json) subsequently reopened on the production binary with the exact note, unchanged theme, integrity `ok`, normal status zero and no surviving owned processes. This is persisted-data verification, not a visual Notebook check after reopening. |
| Ordinary release repetition | [Welcome](../../evidence/shutdown-causality-20261029/final-50-welcome/outcomes.json), [the exact user PDF](../../evidence/shutdown-causality-20261029/final-50-pdf/outcomes.json) and [PDF with Go To opened/dismissed](../../evidence/shutdown-causality-20261029/final-50-pdf-popups/outcomes.json) each completed 50 ordinary closes: 150 total, all OS status zero, with no forced cleanup or surviving owned processes and unchanged build inputs. Popup presentation/hide identifiers matched throughout. These production repetitions do not measure internal finalizers; the separate native traces above do. |

The two PDF batches used the original
`Bhargava Aditya - Grokking Algorithms, 2nd Edition - 2024.pdf`.
Its [hash and file identity remained unchanged](../../evidence/shutdown-causality-20261029/final-input-preservation.json).
The preserved synthetic annotation belongs to the fixture elsewhere in the
same profile; no annotation was authored in the user's PDF. Current-launch
reader timestamps establish accepted publication/location persistence, rather
than pixel-by-pixel PDF rendering acceptance.

Earlier blind-input persistence attempts and failed recorder/harness runs remain
failed diagnostics. In particular, task captures 06–08 had recorder/prologue
argument problems; task 09 corrected those and matched creation/finalization by
task address. An engine dispose entry or a zero process status alone does not
establish that the engine finalized.

## Unresolved mutex abort and physical GPU limit

The `SIGABRT` stacks reach GLib `g_mutex_clear` through compositor disposal,
renderer finalization and GTK child destruction. An aborting run also captured
raster in a presentation lock region. On the installed GLib binary the abort
branch tests a nonzero mutex word; its message alone cannot distinguish a live
lock from invalid or corrupted storage. The saved abort stack lacks the exact
compositor/mutex identity and tested word needed to link those observations.
Later passive branch captures did not reproduce the abort. The renderer
retirement correction closes the confirmed lifetime interval, but neither that
fact nor later normal closes proves the abort's complete cause or elimination.
Arm B has one reachable primary view, but the SDK constructs a compositor on
each realization. The old abort capture did not record realization history or
compositor instances. A single-compositor interpretation is strongly supported
by the expected Welcome path, but it cannot replace the missing identity and
checked-state evidence. Re-realization is not claimed to have occurred.
See [the separate abort analysis](../../evidence/shutdown-causality-20261029/abort-static-causality-review.json).

Repeated host freezes have kernel evidence of NVIDIA PMU halt, Xid 62 and Xid
154 requiring GPU reset. In the current boot the kernel associates the fault
with physical Xorg at 17:06, before the final close batch began at 17:08; the
direct trigger remains unidentified. The later app, private portal and Xvfb
processes had no visible GPU device nodes and no GPU file descriptors, as
recorded in [the process boundary](../../evidence/shutdown-causality-20261029/gpu-lock-process-boundary.json).
The [current-boot kernel log](../../evidence/shutdown-causality-20261029/boot-94f907df-kernel.log)
records those timestamps and the Xorg context.
Those bwrap/Mesa CPU diagnostics do not qualify the actual NVIDIA backend,
physical Wayland, or hardware stability. Hardware acceptance is unavailable.
