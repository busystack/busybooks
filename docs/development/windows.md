# Windows build and native acceptance

## Local qualification environment (2026-10-26)

The existing Windows 11 VM was resumed after the host was upgraded to official
VirtualBox **7.2.22r175245** and `vboxdrv` was restored. The earlier missing-driver
result is historical; it no longer describes the available environment.

VM `474b7e1c-3ee7-4260-9d28-f6ce97c6f8e3` runs Windows 11 Enterprise 24H2,
**10.0.26100.2894 x64**, with Guest Additions **7.1.8r168469**, eight virtual CPUs,
4 GiB RAM, an 80 GiB dynamic SATA VDI and VBoxSVGA/128 MiB VRAM, with 3D
acceleration disabled. The existing unlocked console session, rather than a
service desktop, hosts the tests. Functional acceptance in this VM does not
qualify physical GPU/driver performance.

Task-owned tools, source and a disposable application profile are under
`C:\BusyBooksQualification`. Official unmodified Flutter **3.47.5**, Dart
**3.13.4**, Visual Studio Build Tools 2022 **17.14.43**, MSVC **19.44.35229**,
Windows SDK **10.0.26100.0**, CMake **3.31.6-msvc6**, Node **24.22.1**, Python
**3.13.4** and MinGit **2.56.0.windows.3** were installed or verified. The C++
workload includes ATL, required by the existing SAPI implementation. The existing
WebView2 Evergreen runtime is **135.0.3179.98**; the project SDK remains pinned to
**1.0.3537.50**. No dependency or SDK versions were changed.

`flutter doctor -v` recognizes the Windows desktop toolchain and connected
Windows device. Missing Android SDK and Chrome are unrelated platform warnings;
Windows development passes. Detailed commands, versions, source hashes and
results are retained in
[`evidence/windows-qualification-20261025`](../../evidence/windows-qualification-20261025/)
and indexed by [professional-workspace-results.json](professional-workspace-results.json).

Automation uses an official VirtualBox transient shared folder and physical
console keyboard/mouse input, plus a PowerShell request queue running in the
existing interactive session. MSAA inspects Flutter's actual Windows accessible
nodes; UI Automation inspects Windows Settings and native file dialogs. Native
menus are real Win32 popups, and publications render in the actual WebView2
child surface. No passwords, authentication bypass, insecure remote service,
execution-policy change or framework patch is involved. Preserve the original
saved VM state, network/display configuration and personal session on completion.
This run returned the VM to **Saved**, restored bridged `eno2`, 1024×768 and
100% DPI, and removed its task share and consoles. The existing user session and
original share remain intact; official tools remain in the isolated task directory.

## Required build environment

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
build inputs. Compilation, actual transient popover placement at 100%, 150% and 200% display
scaling, and tested focus-return paths are covered by the retained Windows
qualification. Actual minimize/restore also passes on the final release. Other
matrix items retain their individual evidence boundaries.

## Build and run

The build fetches Microsoft.Web.WebView2 SDK 1.0.3537.50 from NuGet. Install the
Microsoft Evergreen WebView2 Runtime and Microsoft Visual C++ x64 runtime. Keep
the complete Release directory together, including SQLite, plugin DLLs and
`busybooks_comic_archive.exe`. CMake builds the RAR-only helper from the local
checksum-pinned UnRAR source archive and installs its full license and
acknowledgements under `share/licenses/unrar`. No external decoder installation
or runtime download is required. The Win32 helper uses wide paths, a memory-limited
Job Object and the same bounded streaming callbacks as Linux; execution on a real
Windows host is covered by the Windows qualification probes and actual CBR rendering.

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
open saved collections through Open Collection. Open PDF, EPUB 2/3, raw/wrapped
FB2, CBZ and CBR through every file entry point. `.kepub.epub` follows EPUB;
standalone `.kepub`, generic ZIP and generic RAR are not registered book formats.
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
Associations cover `.epub`, `.pdf`, `.fb2`, `.fbz`, `.cbz` and `.cbr`. Windows
matches the final extension, so `.fb2.zip` uses Open Book, drops or command-line
opening; BusyBooks does not claim generic `.zip` or `.rar` associations.

## Reproducible qualification and evidence boundary

Run the checked-in workflow in an unlocked Windows desktop with the installed
pinned SDK and required tools on PATH:

```powershell
& ./tools/qualify_windows.ps1 `
  -FlutterSdk C:\BusyBooksQualification\sdk\flutter `
  -SourceDirectory C:\BusyBooksQualification\busybooks `
  -EvidenceDirectory C:\BusyBooksQualification\evidence `
  -SourceRevision (git rev-parse HEAD)
```

The script enforces the official Flutter framework revision, resolves the
existing lockfile, generates localizations, checks formatting/analysis, runs the
complete Flutter suite, storage/cache/order and JavaScript probes, builds the
Windows release and exercises the shipped comic decoder, format/resource
validation, DirectWrite font probe and actual Win32 menu probe. It records each
command, exit status, log hash and release-file hash. Keep the interactive desktop
available for the menu probe. A portable C++ test alone does not qualify Win32.

The application-owned bootstrap distinguishes the trusted browser ResizeObserver
notification from actual script/import/rejection failures. WebView2's current
URL attribution is covered by a captured native event and regression; notifications
remain in session-scoped diagnostic logs and do not falsely close the book on a
DPI change. Actual exceptions and authored lookalike events remain fatal. No
browser, vendor reader or SDK patch is involved.

The menu probe uses the production `native_menu_host.cpp`, actual
`TrackPopupMenuEx`, physical pointer/keyboard input and the official Flutter
message codec. It checks disabled radio entries, enabled selection, rejection
of conflicting selections, preserved menu indices/session cancellation,
repeated dismissal, unavailable-host errors and owner-focus return. Controlled
Flutter fallback tests remain identified separately from native execution.

Native acceptance uses disposable book copies and a disposable SQLite profile.
Selected screenshots, MSAA trees, native child visibility/focus, saved-note
hashes, normal-exit process handles and before/after storage checks establish the
executed scope. Maximum-length multiline notes, a real SQLite-lock failure and
Retry, native backup/restore dialogs and a missing CBR original are included.
The full current disposition and tested revisions are recorded in
[professional-workspace-verification.md](professional-workspace-verification.md).
Exploratory screenshots, failed test-driver assumptions and earlier builds are
retained with their actual scope; filenames alone are not passing evidence.

The prior GitHub run
[39312939311](https://github.com/albert-gee/busybooks/actions/runs/39312939311/job/118266965365)
and the earlier missing-host-driver attempt are historical results, not current
Windows qualification. No CI push, public release or binary publication was
performed.

Packaging/installer registration, file associations, physical GPU compatibility,
complex IME composition, audible voice quality and a full screen-reader audit
require their own explicit results. The local release executable and native
workflows do not imply those broader qualifications. See
[format-verification.md](format-verification.md) for the larger format matrix.

## Local typography implementation

The main and transient Flutter engines register the same application-owned font
channel. A joined worker uses DirectWrite's local-only system collection,
canonical/localized family names and full/PostScript face identities. Native
samples use DirectWrite/Direct2D/WIC; WebView2 receives private local FontFace
aliases. No font downloads, filesystem font endpoint or interface-font change is
introduced. See [typography.md](typography.md) and its verification record.

The Windows CI also builds/runs `tools/native_font_probe` against stock Arial and
Times New Roman. Run its CMake commands from typography.md on a Windows desktop.
The Windows qualification executes this native probe against stock Arial and
Times New Roman. The local font channel is not substituted by a Linux result.
A full assistive-technology audit and physical-display font rendering remain
separate qualification scopes.
