# BusyBooks

A book reader for Linux and Windows.

Features:

- **Open Book** reads an original EPUB/PDF directly from its filesystem location.
- **Create Collection** asks for a name and opens a database collection.
- **Open Collection** lists every saved collection, including those outside Recent.
- **Recent** contains books and collections by stable identity.
- **Notebook** reviews and edits a book's saved passages, bookmarks and private
  notes, including while the original file is unavailable.
- **Move Book** moves the selected original with a recoverable journal;
  **Locate Book** reconnects matching content without moving it.
- **Backup & Restore Reading Data** includes collections and application-owned
  data. Original EPUB/PDF files are excluded.

A book can belong to multiple collections or none. Positions, annotations and
appearance follow its SHA-256 identity. Collection removal leaves original files
and reading data intact. There are no filesystem collection workspaces or imports.

## Build and run

Use official Flutter **3.47.5**, its bundled Dart SDK and the checked-in lockfile.
Linux build dependencies: clang, CMake, Ninja, pkg-config, GTK 3 development
headers, libhandy 1 development headers and WebKitGTK 4.1 development headers.
Local typography also uses PangoCairo/PangoFc 1.48+ and Fontconfig 2.13+ development
libraries (included by the GTK development dependencies on Ubuntu 24.04).
Runtime: GTK 3, libhandy 1, WebKitGTK 4.1, SQLite 3 and bundled Flutter libraries.
Install `libspeechd2`, `speech-dispatcher` and an offline voice such as
`speech-dispatcher-espeak-ng` for read-aloud. Use current WebKit security updates.

```sh
flutter pub get --enforce-lockfile
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test tools
flutter analyze
flutter test
dart run tools/storage_probe.dart
dart run tools/move_volume_probe.dart /tmp /mnt/Media/busystack
dart run tools/cache_probe.dart
dart run tools/annotation_order_probe.dart
node tools/reader_logic_probe.mjs
bash tools/probe_linux_typography.sh
flutter build linux --release
BUSYBOOKS_PROFILE="$(mktemp -d /tmp/busybooks-demo-XXXXXX)" build/linux/x64/release/bundle/busybooks test/fixtures/reflowable.epub
```

Run without a path for Home. Supply an EPUB/PDF file as a launch argument.
Open saved collections inside BusyBooks. Keep the whole Linux bundle together. `BUSYBOOKS_PROFILE`
must be absolute; omit it to use BusyBooks' own application-support directory.
Use disposable profiles and fixture books for testing. Windows instructions are
in [windows.md](docs/development/windows.md). Linux package inputs are
`tools/package_linux.sh` and `snap/snapcraft.yaml`; neither installs or publishes
an application. Native smoke checks use `tools/probe_linux_engines.sh`.

IDE builds need a persistent package cache. After verification with a temporary
`PUB_CACHE`, regenerate the project's package configuration with the developer's
normal pinned SDK and cache before handing the workspace back. For the default
cache on Linux:

```sh
env -u PUB_CACHE flutter pub get --offline --enforce-lockfile
```

Current data lives in `reading-data.sqlite`; backups contain reading data and
references, excluding original books. Historical `library.sqlite` files and
managed book copies are left untouched and are not inspected. They have no
effect on startup or the interface. Schema migrations apply only to the current
reading-data database. See [storage.md](docs/development/storage.md).

## Project notes

- [BusyMark revision and reuse map](docs/development/reference.md)
- [Reading workspace controls and native popovers](docs/development/reading-workspace.md)
- [Shared typography and local fonts](docs/development/typography.md)
- [Reader engines and content boundary](docs/development/readers.md)
- [Books, database collections, backup and recovery](docs/development/storage.md)
- [Third-party sources](NOTICE) and licenses under `assets/reader/vendor`
