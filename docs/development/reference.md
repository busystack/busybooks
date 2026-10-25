# BusyMark reference and implementation record

Authoritative checkout: `/mnt/Media/busystack/busymark`, revision
`7008772ce26b0d133bed9c0d01754b43d93c672b`, branch `release/v0.6.3`.
BusyBooks started as an empty directory and an independent Git repository on
`feat/busybooks`. No BusyMark history or runtime dependency is used.
`git diff-files --name-only --no-ext-diff` and `git ls-files -m` returned no modifications.
No applicable AGENTS.md was found in the parent directories or either source tree.

The live checkout uses Flutter 3.47.5 (official stable), Dart >=3.12.1 <4,
Yaru ^10.1.0, Riverpod 3, GoRouter 17, SQLite 3 and file_selector.
The installed SDK reports Dart 3.13.4. SDK and pub cache were copied to ignored `.local-tools/` directories with
`/tmp/busybooks-flutter-sdk` and `/tmp/busybooks-pub-cache` symlinks for this
restricted environment; shared installations remain read-only.

## Reuse map

| BusyMark source | BusyBooks adaptation |
| --- | --- |
| app_theme, busymark_design, glyphs | Mechanically renamed theme, semantic surfaces, geometry, controls and icons |
| linux_window_host, linux_page_frame, linux_header_style | Flutter-owned Linux window controls, full-height sidebar, titlebar gestures and header styling |
| workspace sidebar header/view menu, Outline tree row/surface | Adapted compact selector, disclosure/indentation, focus/selection, initial expansion and trailing location slot; publication navigation replaces Markdown authoring actions |
| dialogs, search_field, toast, motion_widgets | Renamed shared modal, local input, feedback and reduced-motion primitives |
| window_control_service | Injectable lifecycle and serialized close handling |
| GTK preferences, icons, accent; native_menu_service | Renamed channels, native symbolic icons, menu/session semantics, live GTK preferences |
| linux native chrome/accent/preferences/icons | Ported services, with BusyBooks application identity |
| my_application.cc | Ported GTK window and menu composition; authoring/credentials/visualization integrations removed |
| JsonFileLocalSettingsStore, AppSettingsController | Focused reading preferences with ordered writes and initial-settings handoff |
| notes_store.dart | Owned storage isolate, request/reply lifecycle, transactions; independent reading-data schema |
| atomic_file_writer | Ported collision-safe Linux publication; Windows publication added separately. Anchored-path utilities were inspected; unused observer/authoring helpers are not retained |
| session/recovery persistence | Durable positions and annotations are committed during use, then flushed before close |
| command_registry, keymap_controller, shortcut_binding/capture | Shared registry semantics, effective bindings, conflict validation and persistent overrides, limited to book commands |
| l10n.yaml, localization.dart, ARB approach | Generated product-local application strings; locale options advertise translated resources only |
| Linux CMake, desktop/AppStream, snap, CI | Independent clean-input Linux and Windows builds; no authoring binaries |

Direct inspection covered the files named above and the specified bootstrap,
router, settings screen, native menu/shortcut entry points, pubspec/lockfile,
packaging and shared-behavior tests. The following requested paths do **not**
exist at this live revision: `docs/development/linux-engine.md`,
`docs/development/performance-observers.md`, `lib/src/core/performance_trace.dart`,
`lib/src/app/command_palette.dart`, `linux/cmake/`, `windows/`.
There is no StartupAppSettings class in the live app_settings.dart. BusyBooks
adds the required startup handoff around its port of the ordered writer.
The absent engine documentation cannot establish whether upstream lifecycle
issues are resolved. Native lifecycle acceptance is recorded from execution,
never inferred from the absence of that file.

## Implementation order

1. Port common foundation and isolate product identity; establish engine probes.
2. Prove Foliate.js EPUB 3 and PDF.js rendering, selection and stable locations in native desktop surfaces.
3. Implement direct-file/collection workspaces, transactional reading data, reader/annotations, assistance and reference-only backup/restore.
4. Validate native lifecycle, keyboard/accessibility, packaging, performance and visual parity.

Engine candidates are pinned under assets/reader/vendor. PDF uses PDF.js directly,
not Foliate's experimental PDF adapter. EPUB uses Foliate's actual EPUB loader,
paginator, fixed layout renderer, CFI, search and highlight interfaces.

Snap inputs also retain the reference's build-owned official SDK checkout and
GNOME/Mesa RUNPATH precedence correction. Editor codec/font consolidation and
credential permissions are not transferred. BusyBooks adds the session D-Bus
slot needed by its GApplication file-open service. snapd's
[dbus policy](https://github.com/canonical/snapd/blob/master/interfaces/builtin/dbus.go)
allows profile-suffixed owned names beneath that declared name. Actual confined
startup, speech and runtime dependency resolution remain unverified.

## Dependency map for Books, Collections and Notebook

| Boundary | BusyBooks implementation |
| --- | --- |
| Resource identity/routes | workspace model/service/controller; Home; app router; product actions; command catalog; native file delivery |
| Persistence | owned ReadingDataStore worker; typed validators; collections/memberships/locations/Recent; existing book/annotation records |
| Inspection/resources | book inspection; stat-bound validation token; EPUB cache; isolated native descriptors |
| Views | reader lifecycle/controller; Notebook controller/drafts; shared annotation actions; collection overview keyed by ID |
| Native content | bootstrap/reader adapter; Linux/Windows reader and popover hosts; visibility separate from geometry |
| User data operations | explicit journaled BookMoveService; global identity-checked Locate; transactional logical reading-data backup |
| Presentation/distribution | shared Yaru controls/settings/menu/search; generated English/German localization; Linux/Windows package inputs |

No BusyMark checkout is needed at build or runtime. The existing vendored reader
revisions/licenses, official Flutter 3.47.5 and dependency lockfile are retained.

BusyMax's read-only schedule-toolbar reference for adjacent Previous/Next is
`9d860f483bba039d9863834ab455c36e34c70824` (`fix/account-settings`). Its local
header/icon services use `go-previous-symbolic` and `go-next-symbolic`; BusyBooks
keeps independent copies/adaptations of the common components. Sidebar reuse
uses BusyMark's same revision above. Actual visual/native parity requires the
separate desktop checks in [format-verification.md](format-verification.md).
