# Professional workspace remediation — 2026-10-25

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

## Disposition of the requested findings

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

## Automated results

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

## Actual Linux evidence

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

## Remaining release gates

### Pinned Flutter compositor shutdown failure

Normal guarded close sometimes exits with SIGABRT after application data is
flushed/closed. GDB captured `g_mutex_clear` inside `FlCompositorOpenGL` teardown
in `libflutter_linux_gtk.so` while GTK disposes the view renderer. This reproduced
after the separate BusyBooks ownership-order repair, including a repeated-close
run with eight normal exits followed by an abort. It is an open Linux acceptance
failure, not a successful shutdown check.

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
arbitrary shutdown sleep was added. A verified fixed Flutter release/engine and
repeated native shutdown acceptance are required before release. Existing
implicit-view removal and software-GL diagnostics are retained in the logs.
The locally available 3.47.6/3.47.7 tags have no Linux embedder changes relative
to 3.47.5 and do not contain the identified renderer-lifetime fixes; an
unverified patch-version bump was therefore not used as a purported repair.

### Other platform coverage

Windows has no execution/build toolchain in this environment. Shared menu C++
contracts and Dart Windows presentation tests passed; native Win32 menus,
WebView2 focus/popovers and Windows compilation remain **not verified**.
Wayland, true fractional monitor scaling, real hardware GPU variations, full
screen-reader/high-contrast/IME coverage and audible narration acceptance remain
unverified. Native renderer formats and desktop UI checks above do not establish
those separate capabilities.

## Material component changes

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
DISPLAY=:108 G_DEBUG=fatal-criticals bash tools/probe_linux_input.sh
bash tools/probe_linux_formats.sh
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
