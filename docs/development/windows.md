# Windows development and packaging

## Prerequisites

Build on an x64 Windows 10/11 desktop with official Flutter **3.47.5**, its
bundled Dart **3.13.4** SDK and the checked-in dependency lockfile. Install
Visual Studio 2022 or newer with **Desktop development with C++**, an x64 MSVC
toolchain, Windows SDK, CMake and the C++ ATL component used by SAPI. See
[Flutter's Windows setup guide](https://docs.flutter.dev/platform-integration/windows/setup)
for workload installation and diagnostics; use BusyBooks' pinned Flutter version.

Put Flutter, Git, CMake, Node.js and Python on PATH for the complete verification
workflow. Confirm the Windows and Visual Studio toolchains with `flutter doctor
-v`, and confirm a Windows desktop device with `flutter devices`. Native menu
checks require an unlocked interactive desktop.

The build fetches Microsoft.Web.WebView2 SDK **1.0.3537.50** from NuGet. Running
the application requires the Microsoft **Evergreen WebView2 Runtime** and
**Visual C++ x64 runtime**. Keep the complete Release directory together,
including SQLite, plugin DLLs and `busybooks_comic_archive.exe`. CMake builds
the RAR-only helper from the local checksum-pinned UnRAR archive and installs
its full license and acknowledgements under `share/licenses/unrar`. Reading
requires no external decoder or runtime decoder download.

## Native runner

The runner extends Flutter's Windows template with a WebView2 child HWND, SAPI
speech, DWM appearance, file-drop handling and per-profile single-instance
file-open delivery. Flutter owns the titlebar and common BusyStack controls.
Direct paths and drops use the shared opening workflow. Collections use IDs in
`reading-data.sqlite`; directories are unsupported opening targets. Reading
state uses content SHA-256 independently of collection membership.

Native readers receive explicit original/cache paths and a session identifier.
Move Book releases the reader before moving the selected physical file.
Same-volume no-clobber `MoveFileExW` omits `COPY_ALLOWED`; cross-volume moves use
verified staging, a durable journal and guarded source removal. The decoder
uses wide paths, a memory-limited Job Object and bounded streaming callbacks.

Reader information uses the primary Flutter application: Look Up is a bounded
panel in the reading pane, and footnotes stay in the renderer. Main menus, View
Options, speech choices and selection actions use the Win32 host and shared
menu/session contract; note editing opens the existing Notebook editor. The
current-location indicator is read-only. Shared modal routes retain the reader
session and paint a captured WebView2 frame behind the modal barrier while the
native input surface is covered. Closing waits for actual route removal before
releasing form resources and restoring the live surface. Header hints use the
operating system tooltip control, centered below their anchors and constrained
to the window. No second Flutter engine is created.
See [workspace architecture](reading-workspace.md).

Reading, Notebook and Split use the same workspace and reader. In Split, the
WebView2 child is bounded to the reader pane. Native visibility waits for an
acknowledged current-session pane rectangle, including divider/sidebar changes
and display scaling. Trusted content-focus events also require current native
focus; visible Notebook editing does not give the publication keyboard ownership.
Standalone Notebook suspends the reader, while the approved collapsed Split
retains it behind the other pane.

The application bootstrap distinguishes the trusted browser ResizeObserver
notification from script/import/rejection failures. Resize notifications remain
session-scoped diagnostics; actual exceptions and authored lookalikes remain
fatal. This boundary belongs to BusyBooks' bootstrap, with no browser/SDK patch.

The primary Flutter engine registers the local-font channel. A joined worker uses
DirectWrite's local-only collection and canonical/localized family and face
identities. Samples use DirectWrite/Direct2D/WIC; WebView2 receives private local
FontFace aliases. See [typography.md](typography.md).

## Build and run

Run these commands from the repository root:

```powershell
flutter pub get --enforce-lockfile
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test tools
flutter analyze
flutter test
node tools/reader_logic_probe.mjs
dart run tools/storage_probe.dart
dart run tools/cache_probe.dart
dart run tools/annotation_order_probe.dart
flutter build windows --release
$env:BUSYBOOKS_COMIC_DECODER = Join-Path $PWD 'build\windows\x64\runner\Release\busybooks_comic_archive.exe'
python tools/qualify_rar.py $env:BUSYBOOKS_COMIC_DECODER
dart run tools/format_probe.dart
dart run tools/format_resources_probe.dart
$env:BUSYBOOKS_PROFILE = Join-Path $env:TEMP ("busybooks-acceptance-" + [guid]::NewGuid())
& .\build\windows\x64\runner\Release\busybooks.exe test\fixtures\reflowable.epub
```

Run without an argument for Home. Omit `BUSYBOOKS_PROFILE` for the normal
application-support directory; use a disposable absolute profile and copied
fixtures for acceptance. Open saved collections through Open Collection.

PDF, EPUB 2/3, raw/wrapped FB2, CBZ and CBR should be exercised through the file
chooser, drops and command-line forwarding. `.kepub.epub` follows EPUB;
standalone `.kepub`, generic ZIP and generic RAR are not registered formats.
Use originals from different directories and test missing/changed originals,
Move/Locate, exact original export, backup/restore and offline operation.

## Reproducible qualification

Run [qualify_windows.ps1](../../tools/qualify_windows.ps1) in an unlocked desktop.
The SDK path is the root of your official Flutter installation. The source path
is your checkout, and the evidence path is a writable output directory:

```powershell
$flutterSdk = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
& ./tools/qualify_windows.ps1 `
  -FlutterSdk $flutterSdk `
  -SourceDirectory $PWD.Path `
  -EvidenceDirectory (Join-Path $PWD 'evidence\windows-qualification') `
  -SourceRevision (git rev-parse HEAD)
```

The script enforces the pinned official framework revision and bundled Dart,
resolves the lockfile, generates localizations, checks formatting/analysis, runs
Flutter tests and storage/cache/order/JavaScript probes, builds the release and
checks the shipped decoder, formats/resources, DirectWrite fonts and Win32 menus.
It writes command logs, statuses, log hashes, release-file hashes and
`automated-results.json` to the supplied evidence directory, and verifies that
`pubspec.lock` is unchanged. Keep generated output outside maintained docs.

The native menu probe compiles production `native_menu_host.cpp` with the
Flutter message codec and exercises actual `TrackPopupMenuEx`, keyboard/pointer
input, disabled/radio entries, selection validation, session cancellation,
dismissal, unavailable-host errors and focus return. The shared popup geometry
test checks pane confinement, scaled coordinates and measured-size changes. The font
probe uses stock Arial and Times New Roman. Run them after the app build:

```powershell
cmake -S tools/native_font_probe -B build/native-font-probe
cmake --build build/native-font-probe --config Release
./build/native-font-probe/Release/busybooks_native_font_probe.exe
cmake -S tools/native_menu_probe -B build/native-menu-probe
cmake --build build/native-menu-probe --config Release
./build/native-menu-probe/Release/busybooks_native_menu_probe.exe
./build/native-menu-probe/Release/busybooks_menu_selection_test.exe
```

Automated probes do not establish all GUI behavior. Actual Windows acceptance
also checks WebView2 rendering/selection/footnotes, primary reader-panel placement and
focus, minimize/restore, 100%/150%/200% display scaling, page/region notes after
cache deletion/restart, native failed-save/Retry and backup/restore dialogs.
Exercise all three book views, divider dragging/keyboard resizing, the approved
collapsed-pane/widening behavior, note-to-passage alignment, focused-pane Ctrl+F
and renderer recovery in Split. Use the shared
[Split acceptance procedure](../../tools/README.md#split-workspace-acceptance),
including bounds, modal/popup exclusion and hidden-pane focus checks.
Linux, Chromium and controlled Flutter results do not establish Win32/WebView2
behavior. Physical GPU/driver performance, complex IME composition, audible voice
quality and a full screen-reader audit need their own checks.

## Packaging and installation

Supply official Microsoft-signed x64 offline runtime installers. The packaging
script validates both signatures, performs a clean pinned build/test cycle and
stages the whole release with root licenses and this guide:

```powershell
./tools/package_windows.ps1 `
  -WebViewRuntimeInstaller 'C:\path\to\MicrosoftEdgeWebView2RuntimeInstallerX64.exe' `
  -VisualCppRuntimeInstaller 'C:\path\to\VC_redist.x64.exe'
iscc packaging/windows/busybooks.iss
```

Replace the installer paths with your downloads. The portable ZIP and SHA-256
sidecar are under `build/distributions/`; portable users install the runtimes
before launch. The optional per-user Inno Setup installer runs both runtime
installers before launch and requires Inno Setup's `iscc` command. File-association
tasks are optional and cover `.epub`, `.pdf`, `.fb2`, `.fbz`, `.cbz` and `.cbr`.
Windows matches the final extension, so `.fb2.zip` uses Open Book, drops or the
command line; BusyBooks does not claim generic `.zip` or `.rar` associations.

Validate the installed package, helper/licenses, runtime installation, file
associations and offline startup in a disposable environment. Building a release
executable does not establish installer acceptance. See
[known issues and qualification limits](known-issues.md).
