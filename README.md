# BusyBooks

A book reader for Linux and Windows.

Features:

- **Open Book** reads original PDF, EPUB 2/3, FB2, CBZ and CBR files directly.
  FB2 accepts `.fb2`, `.fb2.zip` and `.fbz`; DRM-free `.kepub.epub` uses the EPUB reader.
- **Create Collection** asks for a name and opens a database collection.
- **Open Collection** lists every saved collection, including those outside Recent.
- **Recent** contains books and collections by stable identity.
- **Notebook** reviews and edits a book's saved passages, bookmarks and private
  notes, including comic page/region notes and while the original is unavailable.
- **Split** places Reading beside the same Notebook, with an adjustable divider.
  View changes retain the book's position, notes, filters and drafts. At narrow
  widths an active Split shows the last focused pane and offers the other;
  widening restores both panes. Choose Reading or Notebook for a full-width view.
- **Search** uses one header query and temporary results sidebar for Book Text,
  Notebook, Bookmarks, Chapters, Books, Recent and Actions. Saved-book scopes use
  the database, including unopened books, protected note drafts and missing originals.
- **Move Book** moves the selected original with a recoverable journal;
  **Locate Book** reconnects matching content without moving it.
- **Backup & Restore Reading Data** includes collections and application-owned
  data. Original books and disposable rendering resources are excluded.

A book can belong to multiple collections or none. Positions, annotations and
appearance follow its SHA-256 identity. Collection removal leaves original files
and reading data intact. There are no filesystem collection workspaces or imports.

The header View selector offers Reading, Notebook and Split. Split requires room
for both panes when selected and explains its minimum width when unavailable.
In Split, selecting a saved annotation reveals its source beside the note; when
only Notebook fits, use Show in Reading to reveal the source. Ctrl+F searches the
focused pane, or the last focused pane when invoked from shared controls. Split's
view command can be assigned in Settings → Keyboard Shortcuts.

## Build and run

Use official Flutter **3.47.5**, its bundled Dart SDK and the checked-in lockfile.
Linux build dependencies: clang, CMake, Ninja, pkg-config, shared-mime-info, GTK 3 development
headers, libhandy 1 development headers and WebKitGTK 4.1 development headers.
Local typography also uses PangoCairo/PangoFc 1.48+ and Fontconfig 2.13+ development
libraries (included by the GTK development dependencies on Ubuntu 24.04).
Runtime: GTK 3, libhandy 1, WebKitGTK 4.1, SQLite 3 and bundled Flutter libraries.
Portable Ubuntu installations also need `librsvg2-common` for GTK's SVG icon
loader (minimal installations using `--no-install-recommends` can omit it).
The bundled RAR-only helper is built from pinned UnRAR source; no external
`unrar` command or runtime decoder download is needed. Its redistribution license
and acknowledgements ship under `share/licenses/unrar`.
Install `libspeechd2`, `speech-dispatcher` and an offline voice such as
`speech-dispatcher-espeak-ng` for read-aloud. Use current WebKit security updates.

```sh
flutter pub get --enforce-lockfile
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test tools
flutter analyze
flutter test
dart run tools/storage_probe.dart
dart run tools/cache_probe.dart
dart run tools/annotation_order_probe.dart
node tools/reader_logic_probe.mjs
bash tools/probe_linux_typography.sh
flutter build linux --release
BUSYBOOKS_COMIC_DECODER="$PWD/build/linux/x64/release/bundle/busybooks_comic_archive" dart run tools/format_probe.dart
bash tools/probe_linux_formats.sh
bash tools/probe_linux_format_review.sh
BUSYBOOKS_PROFILE="$(mktemp -d /tmp/busybooks-demo-XXXXXX)" build/linux/x64/release/bundle/busybooks test/fixtures/reflowable.epub
```

Run without a path for Home. Supply a supported book file as a launch argument.
Open saved collections inside BusyBooks. Keep the whole Linux bundle together. `BUSYBOOKS_PROFILE`
must be absolute; omit it to use BusyBooks' own application-support directory.
Use disposable profiles and fixture books for testing. Windows instructions are
in [windows.md](docs/development/windows.md). Linux package inputs are
`tools/package_linux.sh` and `snap/snapcraft.yaml`; neither installs or publishes
an application. Native smoke checks use `tools/probe_linux_engines.sh`.

To register an extracted Linux bundle with the application grid, put the whole
bundle in a stable location and run
`python3 tools/install_linux_desktop.py /absolute/path/to/bundle`.
This installs the desktop entry and approved icon under `$XDG_DATA_HOME` (normally
`~/.local/share`), with a quoted absolute executable path and file arguments.
It refreshes the desktop database and GTK hicolor icon cache when their tools
are installed, so an older user icon cache does not hide the new artwork.
Rerun it after relocating the bundle. Existing different BusyBooks launchers or
icons are preserved unless `--replace` is explicitly selected. It does not change
default file associations. Snap desktop registration is handled by snapd.

Linux bundles include the unchanged system SQLite runtime and a relative
`lib/libsqlite3.so` alias. The executable resolves that exact name using its
bundle RUNPATH before Flutter starts, so the locked system native asset works
without a host development package, loader environment overrides or changes to
SQLite. Keep the complete bundle together when moving it.

The cross-volume move probe requires two writable directories on different
filesystems. It creates disposable files within them; choose locations suitable
for testing (for example, `/tmp` and `/dev/shm` when they are separate mounts):

```sh
dart run tools/move_volume_probe.dart /path/on/first/filesystem /path/on/second/filesystem
```

See [development tools](tools/README.md) for native checks, fixture generation
and optional memory/performance probes. Keep local execution evidence in
`evidence/`, generated test output in `test-results/`, and automated logs in CI
artifacts. Selected release qualification records can accompany a release.

Current data lives in `reading-data.sqlite`; backups contain reading data and
references, excluding original books. Historical `library.sqlite` files and
managed book copies are left untouched and are not inspected. They have no
effect on startup or the interface. Schema migrations apply only to the current
reading-data database. See [storage.md](docs/development/storage.md).

## Development documentation

- [BusyMark revision and reuse map](docs/development/reference.md)
- [Reading workspace controls and native popovers](docs/development/reading-workspace.md)
- [Shared typography and local fonts](docs/development/typography.md)
- [Reader engines and content boundary](docs/development/readers.md)
- [Books, database collections, backup and recovery](docs/development/storage.md)
- [Windows development and packaging](docs/development/windows.md)
- [Known issues and qualification limits](docs/development/known-issues.md)
- [Third-party sources](NOTICE) and licenses under `assets/reader/vendor` and `native/vendor`
