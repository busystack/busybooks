# Windows build and native acceptance

## Local qualification environment (2026-10-25)

The Linux host has VirtualBox 7.1.8r168469 and an existing Windows 11 VM,
`474b7e1c-3ee7-4260-9d28-f6ce97c6f8e3`. It is saved, with 8 virtual CPUs,
4 GiB RAM, an 80 GiB dynamic VDI on SATA, VBoxSVGA/128 MiB VRAM and 3D
acceleration disabled. Cached guest
properties identify Windows 11 x64 build 26100 and Guest Additions 7.1.8 with
one logged-in user; these are historical properties, not a verified current
interactive desktop or development-tool inventory.

An actual `VBoxManage startvm 'Windows 11' --type headless` attempt fails with
`NS_ERROR_FAILURE (0x80004005)`: the host has no `vboxdrv` module/device for
kernel `7.0.0-38-generic`. `modinfo vboxdrv` fails and noninteractive privileged
module loading requires administrator authentication. The installed VirtualBox
tool recommends its official `/sbin/vboxconfig` installation step. Restoring
the official host driver is the current prerequisite for resuming qualification;
the saved guest state, snapshots, authentication and VM settings must be kept.

Guest execution, source transfer, installed Windows tools, release compilation,
Win32 menus and WebView2 acceptance remain **not verified** until the VM can
resume. Do not substitute portable Linux C++ tests for those gates. The current
logs and qualification disposition are indexed by
[professional-workspace-results.json](professional-workspace-results.json).
After access is restored, follow the existing Windows CI commands and the
native workflow checks below; keep source/artifacts in a new task-owned guest
directory and restore the original saved power state without discarding work.
No passwords belong in commands, logs, scripts or Git history.

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
build inputs. Compilation, DPI placement, foreground/minimize handling and focus
return of these Windows paths remain unverified until Windows execution.

## Build and run

The build fetches Microsoft.Web.WebView2 SDK 1.0.3537.50 from NuGet. Install the
Microsoft Evergreen WebView2 Runtime and Microsoft Visual C++ x64 runtime. Keep
the complete Release directory together, including SQLite, plugin DLLs and
`busybooks_comic_archive.exe`. CMake builds the RAR-only helper from the local
checksum-pinned UnRAR source archive and installs its full license and
acknowledgements under `share/licenses/unrar`. No external decoder installation
or runtime download is required. The Win32 helper uses wide paths, a memory-limited
Job Object and the same bounded streaming callbacks as Linux; execution on a real
Windows host remains a required gate.

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

## Evidence boundary

The existing Windows 11 guest could not be resumed because its official host
driver is missing, as recorded above. The corrected Windows runner has **not**
been compiled or executed. Linux Dart tests, Windows path-helper checks and CI
configuration do not establish Windows acceptance.

Historical [run 39312939311](https://github.com/albert-gee/busybooks/actions/runs/39312939311/job/118266965365)
was for `fd1aa90a1aa6a3a4e6138b344f40a8f3451790ad`, before this architecture
correction: Windows dependency resolution, localization and analysis passed;
48 tests passed and four Linux-host tests failed. Compilation and later probes
were skipped. `a2036e5` corrected host dispatch, but that earlier local fix also
had no Windows CI result. Neither result validates the new workspace changes.
No push/rerun/publication was performed.

Run the Windows CI job on the current commit, then execute the
interactive matrix in [format-verification.md](format-verification.md): original-file opening without copies,
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
