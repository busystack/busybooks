# Development tools

Run tools from the repository root with the pinned Flutter/Dart SDK and lockfile.
The desktop CI commands are in [desktop.yml](../.github/workflows/desktop.yml).
Keep execution logs/screenshots/qualification JSON in ignored `evidence/`, test
output in `test-results/`, and automated logs in CI artifacts. Selected release
records can be release attachments. Maintained docs describe contracts and
procedures, rather than individual executions.

## Core and format checks

| Tool | Purpose |
| --- | --- |
| `storage_probe.dart` | Real SQLite/file workspace and backup boundary scenarios from `test/support` |
| `cache_probe.dart` | Cache identity, path isolation and resource checks |
| `annotation_order_probe.dart` | Semantic publication ordering |
| `move_volume_probe.dart DIR_A DIR_B` | Moves/recovery between two writable locations on different filesystems |
| `format_probe.dart` | Format preparation, original-byte export, locators, cache deletion/restart and data-only backup |
| `format_resources_probe.dart` | Resource ownership and active-decoder cancellation |
| `reader_logic_probe.mjs` | CFI, network policy, geometry and controlled adapter regressions |
| `reader_focus_probe.mjs` | Application focus protocol and resize/selection ownership with fresh controlled interfaces; also imported by `reader_logic_probe.mjs` |
| `pdf_selection_probe.mjs` | Logical PDF endpoint/direction, ownership and cancellation regressions using application-owned DOM fixtures; included in `reader_logic_probe.mjs` |
| `qualify_rar.py DECODER` | Exact decoded RAR4/5 fixture bytes and corrupt/encrypted/multipart/path rejection |
| `check_epub2_fixtures.py EPUBCHECK_JAR` | Independent EPUB 2 schemas and narrowly scoped checker exceptions |

Run Dart tools with `dart run tools/NAME.dart`, Python tools with `python3 tools/NAME.py`, and the JavaScript entry with `node tools/reader_logic_probe.mjs`.
The JavaScript entry imports `fixed_layout_probe.mjs`, `reader_startup_probe.mjs`,
`reader_defects_probe.mjs`, `reader_review_regressions.mjs`,
`reader_sidebar_probe.mjs`, `typography_probe.mjs`,
`comic_interaction_probe.mjs`, `literal_search_probe.mjs`,
`epub_integration_probe.mjs`, `reader_focus_probe.mjs` and `pdf_selection_probe.mjs`. These execute actual
adapter/renderer logic with controlled APIs; they do not establish native layout,
selection or focus.
The focus probe rejects synthetic input and detached/replaced publication
documents, checks current visible-document ownership, and coalesces resize
updates while preserving the exact source anchor. It checks stale resize rejection,
detached-selection clearing and absence of new selection popovers. It uses
application-owned fixtures; no browser or dependency implementation is replaced.
The defects probe also exercises PDF pause/drain/resume ordering, coalesced hidden
resize, retained source coordinates during hidden flush, expired/stopped passage
requests, and content search when display animation frames are unavailable.

`pdf_selection_native_proof.js` uses actual PDF.js text layers and public DOM APIs
through the existing controlled-resource Chromium runner. Run it with the pinned
Dart on PATH and
`BUSYBOOKS_REVIEW_PROOF="$PWD/tools/pdf_selection_native_proof.js" node tools/probe_chromium_format_review.mjs "$PWD/test/fixtures/text.pdf"`.
It checks exact multi-page endpoints/direction, original source anchors, clear and
replacement behavior, hidden resume, keyboard-link navigation/history, and absence
of focus or popup activation. The controlled defects probe also checks a queued
internal link and failed/stale layout cleanup against actual adapter functions.
Native pane focus/clipboard acceptance still requires the actual desktop apps.

Focused Flutter coverage lives in `book_presentation_test.dart`,
`book_pane_layout_test.dart`, `reader_focus_geometry_test.dart`,
`deferred_reader_navigation_test.dart`,
`book_search_session_test.dart`, `reader_workspace_test.dart` and the existing
Notebook suites under `test/src`. The full `flutter test` entry includes them.

Build the application first for the bundled RAR decoder. Set
`BUSYBOOKS_COMIC_DECODER` to its absolute path for Dart format/resource checks;
installed reading uses the sibling helper. EPUBCheck validation additionally
requires Java, `xmllint` and EPUBCheck 5.4.0; the CI workflow pins its download
checksum. See [format fixture provenance](../test/fixtures/formats/PROVENANCE.md).

## Native desktop checks

Linux probes require the development/runtime packages listed in
[README](../README.md), plus `g++`, Python and Node for their harnesses. They run
on a desktop display/session bus, or under `xvfb-run -a dbus-run-session --` for
headless CI. Build the Linux release first for bundled decoder/opening checks.

| Entry point | Native boundary and supporting tools |
| --- | --- |
| `bash tools/probe_linux_input.sh` | Actual GTK input/teardown, portable menu contract and reader-pane popup placement from `test/src/linux_reader_surface_test.cc`, `native_menu_selection_test.cc` and `native_popover_geometry_test.cc` |
| `bash tools/probe_linux_engines.sh` | WebKitGTK engine smoke using `prepare_engine_probe.dart` and `native_engine_probe.cc` |
| `bash tools/probe_linux_formats.sh` | Format matrix, typed locator validation and real-store/cache restart using `prepare_format_acceptance.dart`, `formats_native_proof.js` and `validate_native_locations.dart` |
| `bash tools/probe_linux_format_review.sh` | Overflow/spread/region, spine fallback and unnamed FB2 section regressions using `format_review_native_proof.js` and the same preparation/validation helpers |
| `bash tools/probe_review_corrections.sh` | Encoded paths, SVG resources, excerpts, page/flush ordering and missing first-document rejection; generates disposable inputs with `make_review_fixtures.py` and runs `review_native_proof.js` |
| `bash tools/probe_format_hardening.sh` | Actual DOM/frame/EXIF behavior and verified PDF snapshot after source replacement, using `hardening_native_proof.js` |
| `bash tools/probe_linux_typography.sh` | Pango/font preview and actual Foliate glyph/anchor checks using `native_typography_probe.cc`, `prepare_typography_probe.dart`, `make_typography_fixtures.py` and the `typography_*_proof.js` files |
| `python3 tools/probe_linux_mime.py` | Shared MIME registration in disposable XDG directories; optional argument selects the bundle's MIME database |
| `python3 tools/probe_linux_opening.py [BINARY]` | Actual bundle, relative-path forwarding and saved typed locations in SQLite; process termination during cleanup does not establish guarded shutdown |

`probe_chromium_format_review.mjs` runs the same format proof in headless Chrome
through DevTools and accepts optional absolute publication paths. Node must
provide its WebSocket API (use `--experimental-websocket` when required).
`BUSYBOOKS_CHROMIUM_BIN` selects Chrome; `BUSYBOOKS_DART_BIN` selects Dart.
`BUSYBOOKS_REVIEW_PROOF` selects an alternate proof such as
`review_native_proof.js` or `hardening_native_proof.js`.
`BUSYBOOKS_REVIEW_ANNOTATIONS` supplies saved annotations where applicable.
`BUSYBOOKS_REVIEW_REMOVE_RESOURCE` removes one exact resource-map key only from
the probe's disposable prepared index. Pair it with
`BUSYBOOKS_EXPECT_OPEN_ERROR` to require an opening failure containing the
expected message. This exercises required-document failure without altering an
original publication or third-party implementation.
`probe_chromium_typography.mjs` is the optional Chromium counterpart invoked by
the Linux typography script with generated native font-resolution JSON.
Chromium behavior does not establish WebView2 acceptance.

On Windows, retain the actual `native_font_probe` and `native_menu_probe` CMake
projects and their C++ sources. [Windows development](../docs/development/windows.md)
documents prerequisites, build/run commands and `qualify_windows.ps1`. A native
probe does not substitute for full application acceptance at different display
scales, with keyboard/IME, assistive technology and audible speech.

### Split workspace acceptance

Use the actual release application, fixture books and disposable profiles on
both Linux/WebKitGTK and Windows/WebView2. Follow
[the workspace contract](../docs/development/reading-workspace.md) and check:

- Reading ↔ Notebook ↔ Split retains exact publication locations, Notebook
  selection/scroll/filters and unsaved or failed-save drafts. Reading ↔ Split
  must retain the same usable reader rather than reopening the book.
- Drag and keyboard-resize the divider, including its minimum bounds, after
  opening/closing the sidebar, window resize/maximization and display-scale
  changes. Verify native content remains inside the reader pane and does not
  cover Notebook, the divider, menus or dialogs. Check text scaling separately.
- Below the measured content minimum, Split entry is disabled with its reason.
  An active Split temporarily shows its last focused pane, keeps the same route
  and sessions, and offers the other pane. Widening restores both panes and the
  ratio; explicitly choosing Reading/Notebook cancels this preference.
- Select a note in side-by-side Split and verify exact passage/highlight alignment
  without stealing editing focus or resetting filters. In collapsed Notebook,
  selecting/editing stays local; Show in Reading deliberately reveals its source.
  Check new annotations, independent scrolling, missing originals and reader Retry.
- Exercise keyboard traversal, note text selection, clipboard, undo, IME and
  focus return. Ctrl+F follows the focused content pane; delayed native input
  must not take over Notebook. Hidden panes must not remain accessibility targets.
- After resizing a PDF, collapse Split to Notebook and export through the real
  Save As workflow. Verify completion, full note text and unchanged saved PDF
  segments; widen and verify the same source position returns. Escape must close
  a noneditable selection popup before it can close the shared search sidebar.
- Activate same-book and cross-book search results with retained query/scopes,
  including narrow-overlay dismissal, deleted annotations and interrupted
  opening/recovery. Verify renderer Retry resumes the latest applicable query
  and does not navigate a superseded book.

Record the platform/runtime, display and text scales, inputs and observations
outside maintained source. Controlled Flutter/JavaScript tests and successful
compilation do not establish these native checks. Complex IME, assistive
technology and physical display/GPU behavior require explicit qualification.

## Linux workspace and shutdown diagnostics

`prepare_workspace_probe.dart ABSOLUTE_EMPTY_DIRECTORY` copies fixture books and
seeds a new profile using the production store. Set `BUSYBOOKS_COMIC_DECODER` to
the built helper. `probe_linux_workspace.py SEED EVIDENCE` drives the actual
release bundle; `--binary` overrides its path. It requires PyGObject/Gdk/GTK,
xdotool, a private X11 display with a window manager, and a private D-Bus session.
It changes settings only in its disposable desktop configuration.

Send JSON lines on stdin: `launch`, `open`, `resize`, `click`, `hover`, `key`,
`type`, `paste`, `screenshot`, `data`, `close`, `wait`, `quit`. For example,
`{"action":"launch","tag":"reading","file":"reflowable.epub"}` starts a copied
fixture, and `{"action":"screenshot","name":"reading.png"}` captures it.
`close` requests guarded close and reports the process exit; `quit` retires the
driver after the app has exited. Outputs include logs, screenshots and
`native-actions.jsonl`. Profile reuse is restricted to the driver's disposable
`/tmp/busybooks-native-workspace-*` directories. Use fixture-only data for
failure/restore work. Optional nested-Wayland inputs are exposed in `--help`.

`probe_linux_shutdown.py BINARY EVIDENCE --display DISPLAY --window-class CLASS
--xdotool PATH` runs guarded closes under GDB on an explicitly isolated display.
It needs GDB, xdotool and a window manager, and refuses an existing matching app.
Optional `--book`, `--seed-profile`, `--switch-book-views` and `--cycles` select
inputs. Each close produces a GDB log; `outcomes.json` records normal/aborted
exits. It stops on failure without suppressing a crash. See the unresolved
[Linux shutdown issue](../docs/development/known-issues.md#intermittent-linux-shutdown-abort).

## Memory and performance diagnostics

Compile standalone worker probes to exclude JIT/compiler memory from RSS:

```sh
mkdir -p build/probes
dart compile exe tools/image_header_memory_probe.dart -o build/probes/image-header-memory
build/probes/image-header-memory cover
build/probes/image-header-memory fb2
build/probes/image-header-memory comic
dart compile exe tools/probe_resource_budgets.dart -o build/probes/resource-budgets
BUSYBOOKS_COMIC_DECODER="$PWD/build/linux/x64/release/bundle/busybooks_comic_archive" build/probes/resource-budgets
```

The image probe checks rejection before large JPEG allocations. The budget probe
uses the committed resource-budget fixtures and checks retained output/RSS.
`probe_streamed_epub.dart EXPANSION_EPUB` checks streaming preparation; generate
its optional input outside committed fixtures with
`python3 tools/make_hardening_fixtures.py --expansion /tmp/busybooks-expansion.epub`.
`storage_benchmark.dart` measures store startup, file inspection, position commits
and backup in a disposable profile. Compile/run it the same way and redirect JSON
to `evidence/`; its timings exclude native rendering and Flutter frames.
Standalone SQLite probes need their resolved native asset; use the pinned Dart
native-asset build output appropriate to the platform.

`book_session_memory_probe.dart` exercises 180 visits to 60 stored books with
production controllers, checking provider/listener disposal and live allocation
samples. Run from the repository root with
`flutter run -d linux --profile -t tools/book_session_memory_probe.dart` in a
private desktop. Debug provider history intentionally retains development
objects, so the probe rejects debug mode. It prints samples and the temporary
`result.json` path, then leaves the probe window for normal close. These component
measurements are not total native-browser memory or hardware-independent ceilings.

## Fixture and asset generation

Keep all `make_*.py` generators. They are maintenance inputs even when ordinary
CI consumes committed fixture bytes. Regeneration is deliberate: versions of
Pillow, fonts and RAR authoring can change hashes. Preserve malformed/security
and previous-version reading-data fixtures; repeat relevant validation before
updating checksums. See [format provenance](../test/fixtures/formats/PROVENANCE.md)
and [reading-data provenance](../test/fixtures/reading-data/PROVENANCE.md).

- `make_fixtures.py`: root EPUB 3/PDF fixtures; requires the system Noto Serif font.
- `make_format_fixtures.py`: EPUB 2/KEPUB, FB2 and comics; Pillow and optional
  official RAR 6.x via `BUSYBOOKS_FIXTURE_RAR` (authoring tool not distributed).
- `make_resource_fixtures.py`: optional large/cancellable comics with explicit
  output arguments; Pillow and RAR are authoring dependencies.
- `make_hardening_fixtures.py`: oriented JPEG regression, or optional expansion
  EPUB with `--expansion`.
- `make_resource_budget_fixtures.py`: bounded-write expansion/discard fixtures,
  with optional RAR authoring.
- `make_review_fixtures.py OUTPUT_DIRECTORY`: disposable reader regression inputs.
- `make_typography_fixtures.py OUTPUT_DIRECTORY`: disposable licensed derived fonts
  and publications; requires fontTools and retains notices, without installing fonts.
- `make_comic_locator_upgrade_fixture.py`: previous-version database/backup fixtures;
  requires the documented local Git revisions and offline populated package cache.
- `make_windows_icon.py`: regenerates the Windows ICO from the owned SVG on Linux
  using gdk-pixbuf/librsvg and C++ tools.

## Upstream integrity

`vendor-manifest.json` records verified official sources, immutable revisions or
releases, upstream paths and checksums. It permits no modified vendor files or
patch exceptions. Preserve all upstream license/notice bytes. See
[dependency provenance](../docs/development/readers.md#dependency-provenance).
Git-sourced repository files must match both the recorded SHA-256 and Git blob
identity, so recalculating only a local file hash cannot bless an edit.

Run the offline inventory/checksum verification and its application-owned
synthetic-fixture tests from the repository root:

```sh
python3 tools/verify_vendor.py
python3 -m unittest discover -s test/tools -p '*_test.py'
python3 tools/verify_vendor.py --platform linux --bundle build/linux/x64/release/bundle --build-tree build/linux/x64/release
```

On Windows use `python`, `--platform windows`, bundle
`build/windows/x64/runner/Release` and build tree `build/windows/x64`.
Bundle verification checks the actual reader vendor tree and copied UnRAR/
WebView2 SDK notices. Build-tree verification compares extracted native source
and SDK files against verified archives. A mismatch, missing/unexpected file or
source rewrite fails verification. CI and both packaging scripts run these
checks before releasing a bundle; Windows staging is checked again after copy.

For an independent authoritative comparison when establishing or changing a
baseline, obtain these exact official inputs and supply their paths:

```sh
python3 tools/verify_vendor.py \
  --upstream foliate=/path/to/foliate-js \
  --upstream pdfjs-dist=/path/to/pdfjs-5.5.207-dist.zip \
  --upstream pdfjs-source=/path/to/pdf.js \
  --upstream unrar=/path/to/unrarsrc-7.2.6.tar.gz \
  --upstream webview2=/path/to/Microsoft.Web.WebView2.1.0.3537.50.nupkg
```

Git checkouts must contain the pinned commit objects. Release archives must
match the immutable digest recorded with their official URL. This checks
upstream contents independently of repository copies and catches a locally
modified tree even if someone recalculates its file hashes. The verifier does
not fetch inputs or rewrite the manifest. Do not modify dependency files for
test setup; verifier tests create only application-owned synthetic fixtures.

`package_linux.sh` and `package_windows.ps1` retain clean build/package procedures;
Windows packaging and qualification are described in the Windows guide. Linux
packaging writes the reproducible tarball and SHA-256 sidecar under
`build/distributions/`; `BUSYBOOKS_FLUTTER_BIN` selects the pinned SDK and
`SOURCE_DATE_EPOCH` optionally selects the archive timestamp.
