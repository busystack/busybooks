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
| `qualify_rar.py DECODER` | Exact decoded RAR4/5 fixture bytes and corrupt/encrypted/multipart/path rejection |
| `check_epub2_fixtures.py EPUBCHECK_JAR` | Independent EPUB 2 schemas and narrowly scoped checker exceptions |

Run Dart tools with `dart run tools/NAME.dart`, Python tools with `python3 tools/NAME.py`, and the JavaScript entry with `node tools/reader_logic_probe.mjs`.
The JavaScript entry imports `fixed_layout_probe.mjs`, `reader_startup_probe.mjs`,
`reader_defects_probe.mjs`, `reader_review_regressions.mjs`,
`reader_sidebar_probe.mjs`, `typography_probe.mjs` and
`comic_interaction_probe.mjs`. These execute actual adapter/renderer logic with
controlled APIs; they do not establish native layout, selection or focus.

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
| `bash tools/probe_linux_input.sh` | Actual GTK input/teardown and portable menu contract from `test/src/linux_reader_surface_test.cc` and `native_menu_selection_test.cc` |
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
`probe_chromium_typography.mjs` is the optional Chromium counterpart invoked by
the Linux typography script with generated native font-resolution JSON.
Chromium behavior does not establish WebView2 acceptance.

On Windows, retain the actual `native_font_probe` and `native_menu_probe` CMake
projects and their C++ sources. [Windows development](../docs/development/windows.md)
documents prerequisites, build/run commands and `qualify_windows.ps1`. A native
probe does not substitute for full application acceptance at different display
scales, with keyboard/IME, assistive technology and audible speech.

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

`vendor-manifest.json` is maintained provenance and content hashes for pinned
third-party inputs, not execution output. Preserve all vendor licenses. See
[local vendor modifications](../docs/development/readers.md#local-vendor-modifications).
`package_linux.sh` and `package_windows.ps1` retain clean build/package procedures;
Windows packaging and qualification are described in the Windows guide. Linux
packaging writes the reproducible tarball and SHA-256 sidecar under
`build/distributions/`; `BUSYBOOKS_FLUTTER_BIN` selects the pinned SDK and
`SOURCE_DATE_EPOCH` optionally selects the archive timestamp.
