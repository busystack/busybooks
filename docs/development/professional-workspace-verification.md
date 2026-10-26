# Workspace remediation and release qualification — 2026-10-26

The final implementation revision is
`767f692fda74292149532afb44b8013f0ca53cf8`. The Reading/Notebook architecture is
preserved. The Linux native qualification below remains scoped to
`a85db3feaad7b897c0ab90ad0868af066f42df7d`; it was not repeated during the
Windows continuation. Windows builds, source audits and native evidence have
separate exact revision records. Earlier VM-driver failures are historical.

The Windows continuation corrected six defects exposed by regression tests or
actual native use: duplicate header accessible names, appearance Escape before
a child receives focus, Notebook's editor consuming shared-search Escape, and
creation dates decoded as milliseconds despite the persisted microsecond
contract, header tooltips overlapping the Windows caption controls, and a
standard browser resize notification incorrectly failing the book. It also
corrected an intermediate tooltip semantics lifecycle
assertion introduced while removing duplicate accessible names. Storage,
backup schema, reader engines, dependency pins and transactional draft ownership
are unchanged.

## Final corrections

| Finding | Correction | Verification |
| --- | --- | --- |
| Cached annotation search membership could validate a deleted record | Activation resolves the current matching book/annotation through Workspace records and Notebook's protected-draft contract. Cached result membership is never a data authority. Deferred navigation revalidates record, book, route and search generation. Missing records refresh the session. | Deleted cached snapshot; queued deletion/query/category/book switches in Notebook and Bookmarks; protected failed creation; async update and valid navigation regressions. |
| Non-disposing book families retained every visited book | Auto-disposing search/sidebar families hold a lease only while their book owns the active workspace. Reading/Notebook and Settings retain that lease. Closing/replacing the book releases it; widget listeners complete disposal. | Exact provider counts over 60 distinct books, disposal/reopen, cancelled debounce/subscription work and profile-mode allocation measurement. |
| An old native search cancellation could overwrite a newer query | Cancellation captures renderer session/query revision and rejects obsolete completion. | A paused cancellation followed by a new query retains the new searching state. |
| Native PDF work could stall after its surface was hidden | Suspension drains native input/layout while frames remain available, then hides it. Later suspended flushes persist application records without requiring another hidden frame. Active close also drains before hiding. Native and durable-write phases remain separate so protected failed drafts can still be edited in Notebook. | Delayed final position/acknowledgement; failed native drain/retry; concurrent flush/suspend; protected Notebook writes; actual narration/Notebook/close workflow. |
| A delayed flush reply could release another request | Native flush acknowledgements carry and validate request identity. Prior, future and unowned replies are rejected. | Focused stale-reply tests, faithful protocol fixtures and existing bridge-failure coverage. |
| Speech-service failure could retain narration ownership and bypass connection cleanup | Expected service failures are typed, logged and exposed as diagnostic state. Stop releases narration ownership; disposal closes even after a failed Stop, shares its completion and rejects late requests/events. Programming errors propagate. | Service-loss recovery, programming-error propagation and disposed-service regressions; real native speech/close checks. |
| A native test probe leaked its XTest connection | The probe owns and closes a separate X connection before unloading XTest. Application surface code is unchanged. | Actual GTK input/teardown with ASan, UBSan and leak detection; no suppressions. |
| Icon buttons had empty names in the actual GTK accessibility tree | Shared header artwork and compact icons carry explicit localized labels inside their button semantics. Tooltip metadata alone is insufficient on the pinned Linux bridge. Existing selected/disabled/action semantics and positioned tooltips remain. | A failing-before/passing-after regression checks real button-node labels, flags and actions. Native AT-SPI inspection is recorded separately from widget semantics. |

No SDK pins, application dependencies, database schema, backup format, reader
engine, archive validation or transactional note implementation changed.

## Book-session resource ownership

Search owns a debounce timer, renderer-intent subscription, provider listeners,
results, per-category query/selection maps, action references and a borrowed
focus-return node. Disposal cancels the timer/subscription; Riverpod owns its
listeners. Async publication and activation check mounted state, identity and
generation. Sidebar owns navigation presentation and publication snapshots,
plus its provider listeners; it owns no native engine or file handle. Closing
their lease releases large result/outline/page-label snapshots. Protected notes
remain in the existing Notebook owner.

The baseline measurement retained 21/41/61 search providers and 20/40/60 sidebar
providers after 20/40/60 books. The extra search provider was application
Actions. After correction the final regression retained one search/sidebar
pair, and closing the workspace removed both. Transient filters/outline state
persist within an active book session; reopening a closed session reconstructs
stored metadata/preferences with fresh transient state. The old test expectation
of indefinite closed-book filter retention was replaced with explicit active
view-switch retention and fresh-session assertions, preserving saved preferences
and format capability checks.

Debug-mode VM allocation alone is misleading here: Riverpod's installed
development observer keeps provider history frames. Profile-mode measurement
checks live allocations independently; the exact samples are retained in the
results manifest. No third-party development observer was modified or disabled.
RSS also includes GTK/WebKit/software graphics and is reported separately from
Dart heap and controller counts.

The final profile probe visited 60 distinct stored PDF books three times (180
visits), loading 300 chapter results per visit. Every 20-visit sample retained
exactly one search controller and one sidebar controller, also confirmed by
post-GC VM allocation counts. Heap use ranged from 8.01 to 8.17 MiB; RSS ranged
from 351.16 to 395.77 MiB and finished at 383.13 MiB. Closing the workspace left
zero providers and no reader-intent listener. The probe then closed through the
window manager with exit code 0. This measures the production controllers and
store in a native profile application; the separate native opening probe covers
real publication engines. It is not a claim of a hardware-independent memory
ceiling.

## Retained Linux verification and provenance

The clean starting checkout was `0bf8dad`, with 425 passing tests, three skips,
clean analysis/formatting and a successful Linux release build. The earlier
manifest identified `01ad861`; comparison shows that `01ad861..0bf8dad` changed
documentation and two verification tools, with no runtime or test changes.
That reconciles the exported source boundary, but does not qualify subsequent
implementation changes. The intermediate `c46d9b3` run passed 437 tests; it was
superseded by the native lifecycle corrections and is retained as historical
evidence.

The complete suite at `a85db3f` passes **447 tests, with three existing skips**
(opt-in live Wiktionary and two Windows-only cases). Lockfile enforcement,
localization generation, formatting of 171 Dart files, analysis, reader
JavaScript probes, normative EPUB fixture checks and the Linux release build
also pass. The retained command manifest records the final platform probe
commands and exit codes. Controlled JavaScript/widget tests are identified as
such and do not substitute for native execution.

The evidence root is
[`evidence/release-qualification-20261025`](../../evidence/release-qualification-20261025/).
[professional-workspace-results.json](professional-workspace-results.json)
identifies commands, source revisions, platform results, selected screenshots,
logs and hashes. `final-source-inputs.json` records hashes of all 585 tracked
runtime/test/tool inputs. `qualified-bundle-provenance.json` identifies the actual
release executable, Dart AOT library and Flutter engine used for final native
qualification. Later documentation-only delivery changes are checked against
these inputs; earlier baseline evidence is never relabeled as final testing.
The native component/profile runs started at the accessibility correction's
unpublished pre-amendment revision. Its only difference from `a85db3f` is the
Dart semantics test's current flag API assertions/import; all runtime and native
probe inputs are identical. That exact diff is retained in
`qualified-native-input-equivalence.json`. The complete Dart suite and serialized
release build were rerun at `a85db3f`; the UI-tested bundle matches that build.
Generated evidence is retained under the repository's existing ignored evidence
directory, rather than solely in disposable `/tmp` profiles.

Flutter remains 3.47.5, framework
`6a19cca56475dbfba1478ee68d7bd0c2ef891da1`, engine
`af7e796e161ae0bb1ff0758c71a7105418bd9ded`, Dart 3.13.4. No framework, compiler,
runtime or third-party source/binary was patched. The SDK checkout had an
unrelated root `pubspec.lock` difference at baseline; it was not overwritten.
BusyBooks' own dependency lockfile is unchanged.

## Previously qualified Linux native acceptance (`a85db3f`)

The hash-qualified release bundle ran on Ubuntu 24.04.5, GTK 3.24.41 and
WebKitGTK 2.52.6. Private Xvfb/Openbox desktops isolate test input from the user's
desktop. The final Wayland run used official Weston 13.0.0, its desktop shell
and pixman renderer, nested in a separate X11 display. BusyBooks itself used
GTK's Wayland backend; this was not an XWayland application or a mocked reader.
It does not qualify GNOME Wayland, fractional physical-monitor scaling or GPU
performance.

| Final check | Executed result |
| --- | --- |
| GTK input, modal, surface resize and teardown; portable menu contract | Passed, including fatal GTK critical diagnostics |
| Reader engines and typography | Passed; seven native typography proofs |
| WebKit format acceptance | 34 passing proofs: 22 fixtures and 12 restarts; two deliberately invalid fallback cases rejected |
| Additional WebKit format review | Eight passing proofs |
| Actual main application opening | 19 original books opened in one primary process, including forwarded relative paths, byte identity and saved typed locations |
| Storage, cache, annotation order and cross-volume move | All commands passed |
| Format/resource validation | 153 format checks passed; real decoder/store cancellation retained existing notes and left no published partial work |
| Chromium format review | Four real-browser proofs passed with controlled local resources; this does not qualify Win32 or WebView2 |
| Native surface ASan/UBSan/leak detection | Passed without suppressions or third-party instrumentation/patches |

Inspected final-source screenshots cover Home; wide/narrow Collections;
opening/dismissing the Collection sidebar and then opening a book through the
unobstructed grid; Reading/Notebook; native menus, compact overflow and disabled
commands; Go To and appearance over actual WebKit; typed Book Text and Notebook
search; Settings/Data; private-note editing and missing-original recovery.
Integer GTK scales 1 and 2, portal text scales 1 and 1.5, light/dark application
themes, Adwaita/Yaru and GTK HighContrast symbolic artwork were exercised. The
sidebar tooltip remains within the Flutter sidebar beside the visible native
reader at 2×. Full-display menu captures distinguish a menu extending outside
its application window from actual display clipping.

The actual AT-SPI tree now names Home, Sidebar, Previous/Next, Bookmark,
Appearance, Search, View, Book Actions, Main Menu, Sidebar View and annotation
actions. Yaru window controls expose their existing named accessible nodes.
This is native label inspection, not a complete Orca audit. Ordinary keyboard
input, shortcuts, native-to-Flutter focus, Escape and Unicode clipboard input
were exercised. Complex IME composition remains unqualified: the isolated US
IBus profile's attempted Unicode compose sequence produced literal digits in
both BusyBooks and a stock GTK entry. That control did not establish an
application-specific defect. No CJK input engine or physical IME session was
qualified. GTK HighContrast artwork inspection does not establish a complete
system high-contrast audit.

The final maximum-note workflow used the actual Notebook editor, native GTK
file dialogs and Settings → Data. A SQLite transaction held by a separate test
process caused Save failed while the complete multiline draft remained visible.
After release, Retry saved exactly the expected Unicode text. A subsequent
**1,000,000-unit, 55,556-line** note survived save, native backup, a different
saved replacement, native restore, normal restart and an engine-aborted close.
Its UTF-8 SHA-256 remained
`7ded207b8c41342b9dc1d78266b027a2ddfa67c6ee2dfe307d6d016940f14cbc`;
SQLite integrity checks were `ok`. The new retained native backup is 1,260,482
bytes, ZIP-valid, and contains the same complete note. An initial paste without
a completed Select All exceeded the supported limit and was correctly rejected;
that screenshot is not evidence of a SQLite write failure.

With a disposable original PDF temporarily absent, Reading showed inline
Notebook/Locate recovery. Notebook, Marks and local note search remained usable;
Escape restored Marks. The original fixture was restored after the test. A
retained query intentionally survives reopening search: typing without clearing
it produced `privateprivate` and no results in one exploratory capture. Only
the inspected `private` result captured while the file was absent qualifies
positive offline search.

Read Aloud started through the healthy host Speech Dispatcher endpoint, then
Notebook stopped narration and hid the publication without the former flush
timeout. A broken, separately started private audio server also hung the
official Speech Dispatcher client; that environment failure is recorded
separately. Functional service start/stop does not certify audible output or
voice quality. Failed disposable-run cleanup is recorded, not counted as a
normal close. Final normal closes and compositor-aborted closes both remain in
the transcript; the Wayland application close returned 0 and still logged the
engine's implicit-view removal diagnostic.

Earlier captures with incomplete focus/setup, wrong pointer targets, an expired
nested display, or names describing an intended action rather than visible
content are excluded from passing evidence. One overlapping release build
failed with an AOT `ApiError`; the serialized final release build passed and
its executable/AOT/engine hashes equal the immutable bundle used for native
acceptance. Superseded test/API findings are retained separately; final analysis
uses current semantics flags and has no issues. No assertions were suppressed.

Material source changes are confined to search activation/session ownership,
the active-book lease/sidebar provider, Notebook's authoritative draft lookup,
guarded view switching, reader flush identity/order, speech/narration cleanup
and shared icon semantics. Focused regressions, native diagnostic/acceptance
tools and development documentation accompany them. The manifest lists the
exact changed files and every retained evidence hash. No runtime dependency on
BusyMark or new annotation cache was added.

## Windows 11 qualification continuation — 2026-10-26

The existing VM resumed using official VirtualBox **7.2.22r175245** after the
user restored `vboxdrv`. Windows 11 Enterprise 24H2 **10.0.26100.2894 x64** and
Guest Additions **7.1.8r168469** ran in the existing unlocked interactive console
session. Configuration remained eight CPUs, 4 GiB RAM, 80 GiB dynamic SATA VDI,
VBoxSVGA/128 MiB VRAM and no 3D acceleration. Guest source/tools/profile are
isolated under `C:\BusyBooksQualification`. No credentials or authentication
changes were needed. Official VirtualBox shared-folder/console APIs, PowerShell,
MSAA and Windows UI Automation provide a retained, reproducible automation path.

The resize classification follows the browser's
[Resize Observer notification algorithm](https://www.w3.org/TR/resize-observer/#deliver-resize-error).
The failed 200% frame at `64a1f18` is retained as defect evidence, not successful
high-DPI acceptance. Native investigation showed that WebView2 attributes this trusted, exception-free
notification to the current document URL. The handler accepts that observed
attribution or the specification's empty filename, requires zero source position,
and keeps unrelated filenames and actual exceptions fatal. The first strict
attempt at `15063a2` still failed native DPI acceptance; its logs and the explicitly
instrumented diagnostic variant are retained. Neither is a final passing run.
The correction does not call `preventDefault`, disable crash reporting or modify
Foliate.js, PDF.js, WebView2 or Flutter. The final native DPI
run is recorded independently below/in the manifest.

The guest uses official unmodified Flutter **3.47.5 / Dart 3.13.4**, Visual Studio
Build Tools **17.14.43**, MSVC **19.44.35229**, Windows SDK **10.0.26100.0** and
CMake **3.31.6-msvc6**, with the required C++/ATL components. Node **24.22.1**,
Python **3.13.4**, MinGit **2.56.0.windows.3** and existing WebView2
**135.0.3179.98** were verified. SDK tracked sources are unchanged; framework
revision is the same pinned `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`.
`flutter doctor` passes Windows desktop requirements; Android SDK/Chrome warnings
are outside the requested Windows target.

| Windows finding | Final correction and evidence |
| --- | --- |
| Actual MSAA header names repeated the tooltip and artwork label | Stable outer semantics boundary excludes duplicate tooltip semantics while retaining the explicit artwork label required by GTK. Button-node tests check names, selected/disabled state and actions; actual Windows MSAA names are single. |
| A tooltip lifecycle assertion appeared during Search after that initial change | The semantics boundary now remains attached independently of tooltip reconstruction. The previously failing complete-suite case and focused regression pass. |
| Appearance ignored Escape until a child took focus | Only the appearance presentation takes initial keyboard focus; existing Go To input and Close-button behavior remain. A failing-before/passing-after regression and native popover dismissal cover the correction. |
| Notebook's focused editor consumed Escape while shared Search was active | Editor Escape defers to the active book search session. Regression and actual one-keypress acceptance preserve the note, restore the prior sidebar and keep WebView2 hidden. |
| Native-created annotations displayed years such as 58788 | The shared formatter reads validated epoch microseconds, matching every annotation producer and persistence contract. No stored record or backup migration is involved. The real 2026 timestamp regression passes; the seed tool uses the same unit. |
| A header hint was painted underneath the Windows caption controls | The common header tooltip placement consumes the existing left/right decoration obstructions. A geometry regression checks that the tooltip remains inside the header and avoids the overlaid caption region. The native stress captures exposed this defect; it required no workspace or window-control redesign. |
| A 200% DPI change produced a false fatal opening error | BusyBooks' bootstrap treated the standard browser ResizeObserver notification as a failed publication. Only a trusted, exception-free notification with the exact standard message now uses the existing diagnostic channel. It remains logged with book/session/stage context; actual exceptions, rejections, resource failures and authored lookalike events remain fatal. Focused bootstrap/controller regressions cover both bridge transports, subsequent real errors and stale sessions. No vendor or SDK source changed. |

`tools/qualify_windows.ps1` records the complete Windows workflow, commands,
exit codes, log hashes and release-file hashes. `tools/native_menu_probe` compiles
the production Win32 menu host and official Flutter codec; 26 native checks
exercise actual disabled/enabled radio entries, invalid multiple selection,
physical disabled activation, keyboard selection, preserved indices, session
replacement, repeated dismissal, unavailable-host error and focus return.
Flutter fallback is covered by controlled service/widget tests, not claimed as
a naturally occurring native-host failure in the application.

The complete final Windows workflow at `767f692` passes **all 22 commands**:
**453 Flutter tests pass, zero fail, two skip** (Linux-only symbolic-link traversal
and opt-in live Wiktionary). Formatting checks 171 Dart files with no changes;
analysis reports no issues. The Windows release build succeeds in 25.4 seconds
(incremental build; the earlier full build took 208.7 seconds).
Storage passes 88 checks, cache 19, annotation ordering five, RAR decoding 16 and
format validation 153. Resource cancellation, reader JavaScript, the DirectWrite
font probe and all 26 real Win32 menu checks pass. No failed assertion was removed
or weakened. The final guest audit reports zero mismatches for all **598** tracked
runtime/test/tool inputs, no tracked SDK differences and an unchanged project
lockfile.

The final source audit checks those inputs against
`767f692fda74292149532afb44b8013f0ca53cf8`. The workflow ran from
22:30:36 to 22:45:29 UTC on 2026-10-26, including the real Win32 menu probe at
actual 200% Windows DPI. Earlier complete runs and UI sessions retain their original revisions:
`cd914fd` established the Windows baseline; `dfcf6a7` exposed the tooltip lifecycle
regression; `181923d` fixed it and appearance focus; `74e0b80` qualified real
Win32 keyboard selection; `02303f0` fixed shared-search Escape. Native functional
workflows at `02303f0` predate only the date formatter/test/seed correction.
They are not relabeled as final-revision runs. The `52a92fe` suite had 451 passing
tests; `64a1f18` had 452; `15063a2` had 453 but failed its subsequent native DPI
check. Only the corrected `767f692` suite and packaged release supply the final
automated and DPI evidence. The final suite/build and native captures are
indexed independently in the machine-readable manifest.

Real native workflows already include EPUB 2/3, KEPUB, PDF with physical/printed
labels, image-only PDF, fixed-layout EPUB, FB2/FBZ, CBZ and RAR5 CBR; actual
WebView2 reading, Win32 menus, both native transient popovers, selection, text
and region annotations, focus handoff and suspended-reader visibility. Local
Notebook/Marks/search remain usable with a missing CBR original, and native
Locate restores the correct original without losing its note. Reading and
Notebook retain the sidebar and native session. Actions search opens Settings;
text search navigates PDF results, and a Notebook search reveals a target after
500 variable-height records.

A genuine native EPUB selection produced a private note with **1,000,000**
characters and **24,999** line breaks, SHA-256
`161909ad35909e3dbef9e1290e6f8fc3d410f4a17576eb45e3750817b28b8153`.
MSAA retrieves its entire value, SQLite confirms it, and restart preserves it.
A bounded external SQLite write lock produces the real retained-draft error;
a 2,361-character Unicode draft survives navigation, then Retry saves its exact
hash after the lock releases. Native Settings → Data backup and restore use
actual Windows file dialogs and confirmation. The schema-3 archive validates,
and replacing then restoring the maximum note recovers its exact text/hash.
A genuine CBR region note also persists and remains editable offline. These
checks use disposable fixtures/profiles; personal data is untouched.

Presentation checks cover light/dark, actual Windows **100%, 150%, 200%** display
scaling, narrow/wide windows, responsive sidebar overlays and compact contextual
overflow, native symbolic/menu icons and popover placement above visible WebView2.
Windows Night sky contrast mode produced a readable native menu; this is a
scoped contrast check, not a complete screen-reader/WCAG audit. Display scale
and contrast mode are restored, including the original Windows Spotlight
background mode. SAPI playback controls appear and switching to Notebook stops
playback; audible voice quality is not verified.

At `52a92fe`, the real release completed **30 openings of ten distinct format
fixtures over three cycles**. Every sample retained one application, one native
reader host and six WebView2 child processes. Application private memory ranged
from **187.31 to 224.59 MiB**, ending at **203.84 MiB**. Handle counts at cycle ends
were 1,031, 1,084 and 1,093; after releasing test-driver COM proxies and idle
cleanup they fell to **802**, with 24 application threads. This is bounded sampled
behavior, not a platform-independent memory ceiling. The native cycle then
closed normally with exit code **0**, and all seven owned processes disappeared.
Subsequent corrections change tooltip geometry and classification/logging of a
standard resize notification. Provider ownership, native hosts, vendor reading
engines and persistence are unchanged. The retained
180-visit profile probe above remains the direct provider/allocation measurement.

Three pre-final normal application closes returned real process-handle exit
code **0**, with no remaining owned processes. The final build has its own
close and resource measurements below/in the manifest. No forced application
termination is counted as successful shutdown. A later VM host-disk I/O pause
interrupted the queued test launcher before execution; moving only task-created
temporary downloads/fixtures to the media volume recovered space and the VM.
No VM relocation, reinstall, snapshot removal or security-policy change occurred.

The final packaged `767f692` release independently rendered all ten format
fixtures at 100% DPI; all ten real WebView2 captures were inspected. FB2 outline
and keyboard activation also reveal the complete chapter, Cyrillic text, poem,
table and embedded image. Earlier blank frames taken before navigation settled
are retained as exploratory captures, not content verification. The same release
opens its actual Win32 Main Menu while the header reports **Opening book**.
At actual 200% DPI it remains ready through resizing, shows an unobscured header
tooltip, and hosts the settled Appearance and Go To surfaces above WebView2.
One physical Escape dismisses Appearance and returns focus to the same native
reader HWND. Go To accepts 50% and settles at its page-aligned Chapter 2 location
(53%, genuine publisher label 17); the request does not promise exact screen
pagination. The initial exact-50%-header assertion was a test-driver assumption.

Final-source native checks also cover Search Escape from the focused note editor,
sidebar restoration, SAPI start/stop across Notebook switching, actual Windows
minimize/restore, a normal close from Reading and a cold restart. The restarted
Notebook retrieves the complete million-character note with **Saved** status,
correct 2026 creation date and WebView2 hidden. Final normal close from Notebook
returns exit code **0** and leaves no owned application/WebView2 processes.
Read-only SQLite integrity is **ok**, and the maximum note, failed-save/retried
draft and CBR region note retain their exact hashes. These native observations
and their source revision are indexed in `native-final-smoke-summary.json`.

The VM is back in its original **Saved** state, with the existing user session
preserved, original bridged `eno2` network, 1024×768 resolution and 100% DPI.
The original share remains; the task share, consoles and power request are
removed. Official development tools remain in the isolated task directory.
The private release ZIP is retained with SHA-256
`23011a96bc62461dfb95a73e4555629ce919154f2065ebed0c078682f029ffb1`;
it was neither published nor installed over a personal installation.

Evidence is retained under
[`evidence/windows-qualification-20261025`](../../evidence/windows-qualification-20261025/),
including source audits, scripts, screenshots, MSAA/focus/visibility trees,
SQLite checks, native backup, exact process-exit observations and log hashes.
`evidence-index.json` hashes the retained Windows files. Historical Linux logs
keep their original paths/revisions; `host-additional-task-moves.json` records
the hash-verified current locations of task-created inputs moved off the root
volume. Windows scratch evidence was also hash-verified onto retained media;
disposable `/tmp` files are not the sole copy of qualification evidence.
Exploratory captures are not automatically passing evidence. VM graphics do not
qualify physical GPUs; complex IME, audible narration, installer/file association
and a full assistive-technology audit retain their explicit limits. Nothing was
pushed, published or released. See [windows.md](windows.md) for reproduction.

## Linux shutdown boundary and release decision

The earlier pristine BusyBooks baseline and remediated application both captured
the same `g_mutex_clear`/SIGABRT stack in the official Flutter
`FlCompositorOpenGL` teardown. The separate BusyBooks signal-disconnection defect
was already repaired. Current review preserves release of native children and
channels before GTK destroys their containing view, and the native surface
sanitizer probe reports no application-owned memory/undefined-behavior/leak
failure. Final native run outcomes, including aborts, remain recorded explicitly.

Five closes of an untouched official Flutter counter template and five of an
independent public-API two-view harness completed normally. Those controls did
**not** reproduce the intermittent compositor abort and are not claimed as an
independent minimal reproduction. A separate mixed-display startup failure also
occurred with the untouched template; fresh isolated displays/runtimes were
used for acceptance. Failed exploratory runs are not passing native evidence.

Upstream [issue 192873](https://github.com/flutter/flutter/issues/192873) was
closed by [PR 193268](https://github.com/flutter/flutter/pull/193268), merged
September 25, 2026, concerning destruction during pending rendering. It is
related lifetime work, not a verified match for this mutex stack. The previously
identified renderer-lifetime commits are outside the pinned release. No exact
matching released correction was verified; the available 3.47.6/3.47.7 tags have
no Linux embedder changes relative to 3.47.5. An SDK change requires a separate
decision and its own native qualification.

The user-visible residual risk is an intermittent abnormal process exit during
window close after application data has flushed. This must be an explicit
release-risk decision; it is not an obligation to patch or maintain Flutter.
No engine changes, arbitrary shutdown delay, forced application exit workaround
or weakened crash detection were introduced. Failed test-run cleanup is recorded
separately and is never counted as successful shutdown acceptance.

The final debugger run again aborted in the engine on the first close; the
20-cycle probe stopped at that captured failure. All 42 seeded annotation
records had identical before/after hashes and SQLite integrity was `ok`.
The final million-unit native note also remained intact after its separate
narration/Notebook close reached the same engine abort. These observations
support application-owned flushing; they do not turn failed clean-shutdown
acceptance into a pass or prove durability against every possible crash.

| Release determination | Disposition |
| --- | --- |
| BusyBooks implementation | **Pass** for the implemented corrections and executed regressions |
| Linux application-owned acceptance | **Pass**, within the retained `a85db3f` native scope and explicit limits above; no new Linux run is claimed |
| Windows native acceptance | **Pass**, within the executed Windows 11 VirtualBox Win32/WebView2 scope and explicit limits above |
| Known upstream Flutter shutdown risk | **Present**; exact released correction not verified |
| Overall release qualification | **Ready subject to an explicit documented risk decision** accepting the known Linux Flutter shutdown abort. No release publication is authorized by this qualification. |

The tested implementation revision is immutable. The delivery commit changes
documentation/results only; `windows-source-inputs.json` and the post-delivery
hash audit establish that all 598 Windows runtime, test and tool inputs still
match `767f692`. The retained Linux `final-source-inputs.json` remains scoped to
its original revision. All task-owned completed source and documentation changes are
committed; no push or release publication is authorized or performed.

The historical workspace review follows. Its earlier test counts and captures
retain their original implementation scope; current results above and in the
manifest supersede its release-gate conclusions.

## Historical workspace remediation at `01ad861`

The workspace implementation is committed and automated verification passes.
**Release acceptance remains open:** real Linux testing reproduced a shutdown
abort inside the pinned Flutter OpenGL compositor. Windows native execution,
Wayland/fractional monitor scaling and a complete assistive-technology audit were
not available. This record does not certify production readiness.

The authoritative baseline was clean commit `cb7ded3` on `fix/ui-elements`.
BusyMark was inspected at `7008772ce26b0d133bed9c0d01754b43d93c672b`, including
its real search session/sidebar, workspace, settings, GTK menus/icons and focus
semantics. No BusyMark dependency was introduced. Flutter remains 3.47.5
(`6a19cca56475dbfba1478ee68d7bd0c2ef891da1`), engine
`af7e796e161ae0bb1ff0758c71a7105418bd9ded`, Dart 3.13.4. Package constraints,
the lockfile, reading engines, database schema and backup format are unchanged.

## Historical disposition of the requested findings

Numbers refer to the remediation brief. “Native” below means the real release
application with GTK/WebKitGTK, except where a focused native probe is named.

| Finding | Implemented disposition | Verification and limits |
| --- | --- | --- |
| 3: disconnected Reading/Notebook routes | Both URLs render one retained Book Workspace page, shared header/sidebar/search and retained content. Warm switches retain the native session; Notebook hides it, stops narration and excludes its focus. | Workspace element/session/state tests; real view switches, Notebook editing and native keyboard search. |
| 4: duplicated header, missing narrow actions, Home terminology | One header and selector. Reading controls adapt together; contextual overflow retains bookmark/appearance/location access. The actual selector layout decision supplies Main Menu's fallback. Home labels are localized as Home. | Narrow/text-scaled widget checks and real Linux captures. |
| 5.1–5.2: renderer-owned/sidebar unavailable in Notebook | A book-scoped typed sidebar owns open/panel/tree/filter/offset/selection state. Stored outline and Marks work independently of renderer readiness. Permanent panels are Outline, applicable Thumbnails, Marks and applicable Books. | Retention/format tests; native Notebook and missing-original Marks/outline. No permanent Search Results entry. |
| 5.3–5.5: ambiguous marks, competing editing/deletion | Marks is a book-order navigation index with type, excerpt, effective note, location and selection. Edit Note reveals/focuses Notebook. Both surfaces call one confirmation path inside the mature coordinated deletion operation. Native selection creation/lightweight reading controls remain. | Navigation/action/deletion/draft tests, including failed deletion and in-flight saves; native Marks/Notebook inspection. |
| 5.6–5.7: history icon and obscured selector tooltip | Marks uses `YaruIcons.rule_and_pen` and `document-edit-symbolic`. The selector tooltip stays inside unobstructed Flutter sidebar bounds. | Actual Yaru/Adwaita symbolic resources rendered at 1×/2×; tooltip captured beside visible native WebKit. No Flutter elevation workaround. |
| 6: unrelated reading/notebook searches | One retained, book-scoped categorized session owns query/results/selection/generation/focus/loading/error/identity and previous sidebar presentation. Search temporarily replaces the retained navigation body. One header input; no All category. Actions reuses the command registry and existing palette command/shortcut. | Debounce/cancellation/stale-session/keyboard/restoration tests; native typed Book Text and Notebook searches, local search without the original, category captures. Image-only PDF/comic capabilities suppress unsupported Book Text. |
| 7.1–7.4: duplicated list, ordering, filters and wide cards | Notebook defaults to integer creation time descending with identity tie-break. Book Order/Type remain explicit. Compact sort/type/notes selectors wrap; a visible bare-bookmark count opens the Bookmarks filter. Cards use 760px maximum content width, appropriate grouping, date/type/location/passage/note/actions and selection feedback. Region cards show validated cached artwork or inline recovery. No manual ranking was added. | Sorting/filter/grouping tests; native wide/narrow/scaled Notebook and actual region crop. Artwork tests cover codec/orientation, missing original, corruption and unchanged notes. |
| 7.5: truncated private notes | Multiline selectable preview, explicit Show Full Note/Show Less, complete line breaks and complete editable text. Stored content is never truncated for presentation. | Long-note widget coverage, million-unit storage/bridge regressions; actual million-character save/restart/backup/restore described below. |
| 7.6: autosave plus Save ambiguity | Notebook has Saving/Saved/Save failed/Retry and meaningful pending-draft Discard. Ordinary Save is removed. Existing captured baseline, revision, conditional write/insert, deletion hold, flush and owner contracts remain. | Extensive existing draft regressions retained; actual SQLite lock produced a retained multiline draft and successful Retry. Annotation failure no longer leaks SQL/private text into Home. |
| 7.7–7.8: bounded iterative reveal and generic states | Identity-centered lazy slivers reveal exact records without estimating or iteratively scanning offsets. Conflicting filters clear for explicit reveal; user scroll remains stable afterward. Separate empty/filter/deleted/loading/missing-original/save-failure states have local actions. | 1,200 variable-height real records, opposite-end reveal after sort/filter change, fewer than 30 built cards and retained manual scroll. Native missing-original/save-failure captures. |
| 8: overloaded global Main Menu | Stable application commands only, plus View when the actual header selector is hidden. Book Actions retains history, assistance, properties, move/locate/export and collection return. Settings → Data owns backup/restore. Keyboard command identities remain. | Menu/availability/overflow/Settings-return tests and real GTK menus. Book Properties was additionally restored to book context independently of renderer readiness. |
| 9: disabled radio group exception and blocking failures | Common portable validation accepts disabled radio entries, rejects multiple selected members, and retains preorder indices/session ownership. GTK uses state/targets; Win32 preserves disabled/radio/check flags. Disabled activation is rejected. Recoverable host failures log context and use the existing themed Flutter fallback; invalid arguments remain errors. | Dart service/widget tests and compiled portable C++ contract tests; actual GTK state and repeated dismissal/opening. Windows host execution is unverified. Fallback failure injection is controlled testing, not a claim of a naturally failing native host. |
| 10: full settings form inside appearance popup | Shared preferences, separate compact native presentation. Reflow controls are theme/size/spacing/width/margins/publisher style/More. Fixed layouts expose applicable fit/zoom/spread/background, PDF rotation and comic direction. Advanced font/default controls remain in Settings Reading. | Popover capability/persistence/native readiness/cancellation tests and actual EPUB/fixed EPUB/PDF/comic popovers. Per-book Settings scope is explicit and cannot target another return book. |
| 11: form-heavy Go To and ambiguous PDF labels | Compact native surface. PDF integers mean physical pages, unique nonnumeric labels mean printed labels, and `=label` explicitly selects a printed label, including numeric labels. Duplicate labels fail locally. Reflow uses chapter/progress/genuine publisher references; comics use physical pages. | Deterministic locator tests, existing native first-frame/paint/navigation cancellation regressions, actual reflow/PDF Go To. No invented print pagination. |
| 12: Settings surface, fixed sidebar, ineffective Reduced Motion, data placement | Typed General/Reading/Accessibility/Shortcuts/Data pages; wide sidebar or narrow selector; semantic main view background. Reduced Motion is explicitly informational system status. Original backup/restore engine and protected flushing remain. | Adaptive/surface/preference/shortcut/Data/restore tests; actual Settings pages and backup/restore dialogs. |
| 13–15: inconsistent controls, Collection overlay and page failures | Existing BusyBooks/Yaru controls and semantic tokens reused. Notebook selectors wrap; inline page actions replace dialog buttons. Narrow Collection defaults closed, dismisses its overlay and reserves no sidebar width; filters/scroll/selection remain. Save and reading recovery failures remain local where appropriate. | Collection/layout/focus tests and native wide/narrow/overlay captures; native write failure and missing-original recovery. |
| 16: accessibility and keyboard | Accessible Home/control labels, retained tree/list keyboard navigation, search arrows/Enter/Escape/clear, focus restoration and configurable command identities. Shared chrome explicitly transfers GTK/Win32 focus from native publication, with session/popover/inactive-window guards. Hidden surfaces/panels exclude focus and hit testing. | Widget/command/native-surface probes and actual typed native→Flutter handoff. Hidden Collection Search no longer shadows Notebook Ctrl+F. Full screen-reader/high-contrast/IME acceptance remains unverified. |
| 17: formats and safety | Existing Foliate/PDF integrations, format parsing, validation, locator/archive/resource limits, native surface ownership and persistence contracts remain. Cached region previews only read bounded, sealed resources and add no backup fields. | Full regression suite, existing JavaScript probes and 34 actual WebKit format proofs, including restarts and expected invalid fallback rejection. |
| 18–20: baseline, native checks, docs and cleanup | Baseline recorded before edits; obsolete controllers/palette/native font-chooser branch removed; existing architectural docs reconciled; focused commits, no push. | Detailed results and native limitations below; generated evidence remains under the repository's existing ignored evidence directory. |

## Historical automated results

| Check | Baseline | Final |
| --- | --- | --- |
| `flutter analyze` | No issues | No issues |
| Dart format verification | 152 files, no changes | 169 files, no changes |
| `flutter test --concurrency=2 --reporter=expanded` | Original available suite: 401 passed, 3 skipped | 425 passed, 3 skipped |
| `flutter build linux --release` | Passed | Passed |
| `bash tools/probe_linux_input.sh` on managed private X11 display | Passed | Passed with fatal GTK critical diagnostics; portable native menu contract included |
| Existing reader JavaScript probes | Passed | Passed; these are controlled logic tests |
| `bash tools/probe_linux_formats.sh` | Existing infrastructure inspected | 34 `formatProof.passed` events, 22 format fixtures plus 12 restarts; two deliberately invalid EPUB fallback cases rejected |

The three skips are the opt-in live Wiktionary request and two Windows-only
checks. No tests were deleted or assertions weakened. Runs overlapping heavy
build/native work exposed timing failures, recorded separately from baseline.
The large-list fixture incorrectly charged 1,200 individually durable SQL writes
to a 30-second popover-transition helper. Preparation now uses ordinary real
asynchronous fixture setup; reveal/layout retain bounded pumps and all original
identity/laziness/scroll assertions. The final complete run passed unchanged
production persistence boundaries.
The real cache-image widget test also waits for its bounded asynchronous image
read before settling animations; an indeterminate progress indicator cannot
settle while a fake test clock races ahead of disk work.

Final logs and hashes are enumerated in
[professional-workspace-results.json](professional-workspace-results.json).
Focused coverage includes the original Notebook/reader workspace/native menu/
Linux frame/settings suites, storage/backup/resource/format/locator protections,
failed first insertion/update/delete, draft revision races, restore rollback,
native popover acknowledgements and actual maximum supported note transport.

## Historical Linux evidence

The release bundle ran with GTK 3.24.41 and WebKitGTK 2.52.6, Xvfb `:108`, a real
Openbox window manager and private D-Bus session. The application used disposable
profiles seeded through `ReadingDataStore`; original fixtures were copied to
`/tmp`. `tools/probe_linux_workspace.py` drives real X11 pointer/keyboard input
and GTK clipboard/file dialogs. Screenshots include actual native WebKit and
native GTK popovers/menus. They are not widget-test or mocked surfaces.

The evidence root is
[`evidence/professional-workspace-20261025`](../../evidence/professional-workspace-20261025/).
Its action transcript records requested theme/scale, actual portal text scale,
process/window identities, screenshot geometry and guarded process exit results.
The tracked result manifest preserves artifact hashes. Images/logs are generated
artifacts excluded by the existing `.gitignore`.

Scale checks distinguish two independent mechanisms: actual integer GTK display
scales 1×/2× (100%/200%), and system text scale 1.5 at GTK 1×. The latter was
verified from the desktop portal, because per-process GSettings alone did not
change Flutter's portal-derived text scaling. It establishes 150% text/layout
acceptance; it does not establish fractional monitor/compositor scaling. Light
and dark shell, Notebook, Settings and native reader/popovers were inspected at
the available scales and at narrow/wide widths.

Representative captures include Home, Collection and its dismissible overlay,
Reading/Notebook, Marks/outline/thumbnails, search categories, Notebook editor,
native appearance and Go To, Main Menu, Settings pages, missing original and
failed autosave/Retry. The result manifest identifies selected evidence rather
than treating every exploratory screenshot as acceptance evidence.

Bookmarks and Chapters captures were individually checked against the category,
query and result actually visible. Enter navigated to Chapter 2; Escape restored
Outline with Chapter 2 selected. Opening Settings through Main Menu while that
search was active and returning retained the category, query and selection.
Activating an Actions result deliberately closes search before executing the
command; the Settings return check uses the separate Main Menu path.

The installed `document-edit-symbolic` was resolved and actually rendered from
Yaru and Adwaita at 16/32 physical pixels. Selector tooltip screenshots were taken
with the native reader visible, confirming the bounded presentation is not
obscured by its GTK overlay.

### Note durability through the actual application

A multiline ASCII note of exactly 1,000,000 characters was pasted into the native
application's Notebook editor. Saved status was followed by a read-only SQLite
length/hash check, guarded close/restart and reopening the note. Settings → Data
then created a real `.busybooks` ZIP through the GTK save dialog. After changing
the note, the native restore picker and Restore confirmation reinstated it.
The final production record was rechecked after restoration:

- Length: `1000000` characters/UTF-16 units.
- SHA-256: `37d00ff3489d0eaecaa7e54c373b8e2cc4b6c7893e5d1cc583049e18cd72eaf0`.
- Backup: `/tmp/busybooks-native-workspace-c98zqgsm/maximum-note.busybooks`,
  `1068734` bytes.

This supplements the existing escaped/multibyte/million-unit bridge and backup
tests. A separate real external SQLite `BEGIN IMMEDIATE` lock caused the actual
five-second busy timeout: the full multiline draft stayed editable with Save
failed/Retry; releasing the lock and selecting Retry persisted it. Further
testing caught and repaired stale publication of that failure on Home. Only
disposable profiles were locked or changed.

The original EPUB copy was temporarily renamed while its stored Notebook was
opened from Collection's real book context menu. The missing-original banner,
retained outline/Marks, complete notes and Notebook search remained usable. The
copy was restored afterward; repository fixtures were never renamed/deleted.

## Additional confirmed repairs

- Native GTK/Win32 keyboard ownership now explicitly returns to shared chrome;
  Flutter focus changes alone could leave the native renderer receiving typing.
- Restoring a retained Notebook editor no longer steals an explicit active
  header search focus request. Search field activation explicitly requests focus.
- Hidden Collection Search previously intercepted Notebook's Ctrl+F. Shortcut
  maps now honor visibility while visible disabled commands retain ownership.
- Header hints stay within the header, including the query clear action;
  navigation/Search hints stay within the sidebar. Search transitions retire
  old hover overlays, and scaled tooltip width is bounded. Location details
  remain in actual accessibility labels and Go To, with a concise action hint.
- Queued settings writes capture their store before provider disposal, avoiding
  asynchronous access to a disposed Riverpod Ref.
- Sidebar animation frames now update actual native content bounds; separate
  route/modal and workspace gates prevent stale visibility acknowledgements.
- Valid stored integer creation times beyond Dart's date range render a local
  unavailable date without changing data or crashing cards.
- Book Properties remains reachable in Book Actions while Notebook is active;
  Restore's confirmation uses Restore instead of the generic Open label.
- Annotation errors remain with protected drafts/contextual actions. SQL and
  complete private notes no longer persist in Home's global failure state.
- Native ownership is released in GTK window destruction before containing
  widgets disappear. A debugger-confirmed invalid signal disconnect from the
  old application-disposal order is repaired and covered by the GTK probe.

## Earlier shutdown observations

### Pinned Flutter compositor shutdown failure

Normal guarded close sometimes exits with SIGABRT after application data is
flushed/closed. GDB captured `g_mutex_clear` inside `FlCompositorOpenGL` teardown
in `libflutter_linux_gtk.so` while GTK disposes the view renderer. This reproduced
after the separate BusyBooks ownership-order repair, including a repeated-close
run with eight normal exits followed by an abort. Clean shutdown acceptance failed in that run; the current release-risk
disposition is recorded above.

The desktop-driver transcript records 18 normal guarded closes and four SIGABRT
exits. The separately instrumented repeated-close run and pristine-baseline
comparison below establish why successful UI captures cannot close this gate.

A pristine archive of starting commit `cb7ded3` was separately built under `/tmp`
with the same pinned SDK. Its first guarded-close debugger cycle reproduced the
same SIGABRT/compositor stack. This establishes a pre-existing native engine
failure discovered during this task, separately from the repaired BusyBooks
signal-disconnect defect. The baseline test/build checks performed before edits
had not exposed this intermittent shutdown path.

The local official Flutter checkout contains upstream development commits
[`abacb741720`](https://github.com/flutter/flutter/commit/abacb7417205339cd75ad09e55b8e6063a983ec0)
and
[`34067b1a6e2`](https://github.com/flutter/flutter/commit/34067b1a6e2c5121dbaf5915517f989c2f48fe68)
addressing renderer lifetime and active-draw teardown. They are on the available
`origin/windowing_test_linux` development branch, outside the pinned release.
No private GTK-child retention shim, SDK mutation, forced process exit or
arbitrary shutdown sleep was added. No verified released fix was established. An SDK upgrade is a separate
release decision; maintaining Flutter is not a BusyBooks implementation task. Existing
implicit-view removal and software-GL diagnostics are retained in the logs.
The locally available 3.47.6/3.47.7 tags have no Linux embedder changes relative
to 3.47.5 and do not contain the identified renderer-lifetime fixes; an
unverified patch-version bump was therefore not used as a purported repair.

### Other platform coverage

At the original remediation revision, Windows native execution, Wayland,
true fractional monitor scaling, hardware GPU variations and complete assistive
technology/IME/audio acceptance were unverified. The current environment
investigation and additional qualification above supersede that earlier scope.
Portable C++ and widget tests never establish Win32/WebView2 acceptance.

## Historical remediation components

- `lib/src/book_workspace/`: retained workspace, common header, book context
  actions, location control and typed persistent sidebar controller.
- `lib/src/search/`: one search session/result contract and temporary sidebar;
  `busybooks_search_field.dart`/command registry/application focus integration.
- `lib/src/notebook/` and `lib/src/annotations/`: content/card presentation,
  sorting/filtering/reveal, save status, coordinated actions and cache preview.
- `reader_controller.dart`, `reader_screen.dart`, `reader_sidebar.dart`, compact
  appearance, native popover and reading-navigation contracts. Superseded reader
  sidebar state and standalone command palette were removed.
- Settings page/screen, Main Menu/design/glyphs/product actions, Collection/Home,
  LinuxPageFrame and queued app settings ownership.
- Read-only cached region preview worker operation; Linux/Windows menu hosts,
  shared portable validation, native reader focus handoff and GTK owner cleanup.
- English/German localization, focused regression suites, real GTK/menu C++
  probes and disposable-profile/native desktop verification tools.
- `reading-workspace.md`, `readers.md` and typography documentation reconciled
  with the current compact popover and advanced Settings ownership.

## Reproduction

Use the pinned toolchain and the existing repository build/native dependencies:

```sh
flutter analyze
dart format --output=none --set-exit-if-changed lib test tools
flutter test --concurrency=2 --reporter=expanded
flutter build linux --release
xvfb-run -a dbus-run-session -- env G_DEBUG=fatal-criticals bash tools/probe_linux_input.sh
xvfb-run -a dbus-run-session -- bash tools/probe_linux_formats.sh
```

For desktop captures, prepare an empty absolute disposable directory with
`dart run tools/prepare_workspace_probe.dart /tmp/busybooks-workspace-seed`.
Set `BUSYBOOKS_COMIC_DECODER` to the built comic decoder when preparing CBR.
Run `python3 tools/probe_linux_workspace.py SEED EVIDENCE` under
`dbus-run-session` with a private X11 display/window manager, PyGObject and
xdotool. Its JSON-line commands include
launch/open/resize/click/hover/key/paste/screenshot/data/close/quit; launch can
reuse a probe-owned `/tmp` profile or accept a book filename and settle duration.
Do not use a real user profile for failure/restore probes.

Task-owned source, tests, tools and documentation are committed in focused
commits on `fix/ui-elements`. Nothing was pushed. The final delivery reports the
Git working-tree state and the open release gates above.
