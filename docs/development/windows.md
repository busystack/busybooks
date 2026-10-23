# Windows build and native acceptance

Use an actual x64 Windows 10/11 desktop, Visual Studio 2022 or newer with Desktop
Development with C++, and official Flutter 3.47.5 stable. The runner extends the
official Flutter template with a WebView2 child content surface, SAPI speech,
DWM appearance, file-drop and per-profile single-instance file-open delivery.
Flutter owns the single titlebar and common BusyStack controls.

Direct book paths and drops reach the same opening workflow as Linux. Collections
use IDs in reading-data.sqlite; directories are unsupported opening targets.
Reading state uses full content fingerprints, independently of membership.
Native readers receive explicit original/cache paths and a session identifier.
Move Book releases the active native reader before moving a selected physical
file. Same-volume no-clobber MoveFileExW omits COPY_ALLOWED. Cross-volume copying
uses the worker's verified staging/journal path, then guarded source removal.
Windows execution, locked-file behavior and package acceptance require a real
Windows host; Linux tests do not validate Win32 or WebView2 behavior.

The reading workspace now owns a reusable transient FlutterViewController above
WebView2 for selection, inline notes, appearance, Go To and voice controls. It
starts the same packaged official Flutter bundle through a restricted popover
entry, before profile/window bootstrap. Main menus use a Win32 host with the
existing BusyMark menu/session contract. Both paths keep the publication visible;
main-route dialogs still hide it. No extra engine distribution, framework or
Fluent styling is introduced. Both native source files are explicit runner
build inputs. Compilation, DPI placement, foreground/minimize handling and focus
return of these Windows paths remain unverified until Windows execution.

## Build and run

The build fetches Microsoft.Web.WebView2 SDK 1.0.3537.50 from NuGet. Install the
Microsoft Evergreen WebView2 Runtime and Microsoft Visual C++ x64 runtime. Keep
the complete Release directory together, including SQLite and plugin DLLs.

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
$env:BUSYBOOKS_PROFILE=Join-Path $env:TEMP ("busybooks-acceptance-" + [guid]::NewGuid())
build\windows\x64\runner\Release\busybooks.exe test\fixtures\reflowable.epub
```

Run without an argument for Home. Create a collection using its action and
open saved collections through Open Collection. Open EPUB/PDF files through any file entry point.
Test originals from two different directories and both internal/external
references. For an offline distribution, supply the Microsoft-signed x64 runtime
installers:

```powershell
./tools/package_windows.ps1 -WebViewRuntimeInstaller C:\path\webview.exe -VisualCppRuntimeInstaller C:\path\VC_redist.x64.exe
iscc packaging/windows/busybooks.iss
```

The optional per-user Inno installer runs both installers before launch. Portable
ZIP users install the runtimes first. File-association tasks are optional. Test
only in disposable profiles/VMs; repository builds do not replace installations.

## Evidence boundary

No Windows host/VM is accessible in this session. The corrected Windows runner
has **not** been compiled or executed. Linux Dart tests, Windows path-helper
checks and CI configuration do not establish Windows acceptance.

Historical [run 39312939311](https://github.com/albert-gee/busybooks/actions/runs/39312939311/job/118266965365)
was for `fd1aa90a1aa6a3a4e6138b344f40a8f3451790ad`, before this architecture
correction: Windows dependency resolution, localization and analysis passed;
48 tests passed and four Linux-host tests failed. Compilation and later probes
were skipped. `a2036e5` corrected host dispatch, but that earlier local fix also
had no Windows CI result. Neither result validates the new workspace changes.
No push/rerun/publication was performed.

Run the unchanged Windows CI job on the corrected commit, then execute the
interactive matrix in verification.md: original-file opening without copies,
independent collections/Recent, modified/missing files and identity-checked
relocation, shared annotations and positions, reference-only backup/restore,
WebView2 rendering/selection/locations, UI Automation text, keyboard/focus/modals,
SAPI audio/pause/resume/voices/rate, file association/drop, ordinary close/reopen,
Windows collision/recovery semantics, and offline distribution installation.
Record the tested SHA separately for build, test and interactive results.

For the reading workspace at `1ea696692ad1bd7a2d415e8665b4eb2f19d7b0e1`,
also check selection actions without blanking WebView2, note-write errors,
Escape/outside-click dismissal, native menus and effective bindings, Tab through
publication links into Flutter controls, full screen, minimize/restore and
100%/125%/150% DPI. Use mixed-pages.pdf for page-specific fit and rotated text
geometry, and fixed-layout.epub for same-spread jumps and text anchors at zoom.
Switch books during search/narration and confirm old callbacks cannot affect
the new session. The controlled-DOM JavaScript probe is supplementary and does
not establish WebView2 behavior or UI Automation access to the publication.

## Local typography implementation

The main and transient Flutter engines register the same application-owned font
channel. A joined worker uses DirectWrite's local-only system collection,
canonical/localized family names and full/PostScript face identities. Native
samples use DirectWrite/Direct2D/WIC; WebView2 receives private local FontFace
aliases. No font downloads, filesystem font endpoint or interface-font change is
introduced. See [typography.md](typography.md) and its verification record.

The Windows CI also builds/runs `tools/native_font_probe` against stock Arial and
Times New Roman. Run its CMake commands from typography.md on a Windows desktop.
Linux cannot establish Windows compilation, WebView2 font resolution, preview
painting, keyboard focus, display scaling or accessibility. These remain
explicitly unverified until executed on Windows.
