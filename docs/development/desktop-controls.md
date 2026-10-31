# Desktop control contracts

Reference: BusyMark commit `7008772` in the adjacent, unmodified BusyMark checkout.
This review covers application-owned presentation under `lib/`, both native reader
hosts, and owned reader assets. The older `desktop-ui-audit.tsv` records the
previous popup migration; the control-specific decisions below supersede its
broad primitive classifications.

`desktop-control-contracts.json` inventories every permitted direct control
constructor by source, owning class, constructor and exact occurrence count. Its
reference names identify the actual BusyMark construction, not a file-wide
exemption. `desktop_presentation_architecture_test.dart` checks that inventory;
adding another direct control requires a specific reviewed contract. Feature
screens normally compose the shared controls below.

## Shared rendering contracts

All BusyMark design symbols in this table refer to
`lib/src/app/busymark_design.dart`, unless another file is named.

| BusyBooks component | Specific BusyMark reference and construction | Disposition |
| --- | --- | --- |
| Header/compact icon buttons | `BusyMarkHeaderIconButton`, `BusyMarkCompactIconButton`: Yaru icon style, semantic neutral foreground, tight shared size/padding, Yaru focus border, explicit accessible name | Retained; all visible hints use the corrected shared tooltip host |
| Tooltips | `BusyMarkTooltipStyle`, `app_theme.dart:tooltipTheme`, Flutter Tooltip's themed Container/Center/Text composition: black 80%, white text, white 10% 1px border, 8px radius, 10/6 padding, body-medium 14px, 30px minimum, 450ms wait, 100ms exit, 150/75ms fades | GTK defaults and Windows common-control tooltip removed. The primary application resolves and paints the shared theme at the actual text scale/DPR; hosts composite those RGBA pixels, without another engine or book capture. Below-center placement is clamped to window edges; host has no focus/input ownership |
| Ordinary and semantic push buttons | `BusyMarkPushButton`: standard uses neutral FilledButton; suggested/destructive use ElevatedButton and the existing semantic role colors. Geometry and every interaction state come from the same shared Yaru button style | Direct feature TextButtons converted to the existing semantic component |
| Closed menu selectors | `BusyMarkPopupSelector.triggerBuilder`: TextButton with outlined-button neutral foreground/icon state properties, reference padding, label, 8px gap and 16px down arrow | Retained exact reference trigger; native menu alone is not its visual contract |
| Combo rows | `BusyMarkComboRow`: complete row owns hover/focus/activation, YaruListTile.square, bounded value/arrow, disabled foreground, native checked choices | Reused for Reading scope/default selectors and all preference values |
| Action/switch rows | `BusyMarkActionRow`, `BusyMarkSwitchRow`, `_BusyMarkSwitchState`: YaruListTile.square, neutral row hover, shared title/subtitle/trailing alignment, real YaruSwitch and enabled state | Reused; no per-screen geometry/colors |
| Settings groups | `BusyMarkGroupedList(filled: true)` and `workspace/presentation/settings_screen.dart`: filled rounded grouped surface, separators, shared row geometry, settings-page padding 24/14/24/32 | Reading scope, format, typography and actions now composed in these groups |
| Sidebar navigation/records | `BusyMarkSidebarNavigationTile`, `_BusyMarkSidebarRecordRowState`: clipped neutral selected surface, Yaru row geometry, owned keyboard focus, shared hover | Retained throughout Welcome, library, reader, search and font results |
| Reader tree and Notebook inline passage activation | `workspace/presentation/workspace_screen.dart:_SidebarRowSurface`: 8px clipped surface, semantic selection, neutral hover, one activation owner | Explicit shared neutral hover retained/corrected. Chapter names remain accessible without chapter-title tooltips |
| Search field | `app/busymark_search_field.dart:_BusyMarkSearchFieldState`: shared themed TextField, search prefix, ordinary themed clear IconButton, local editing shortcuts | Retained precise existing component; native text context menus and IME ownership preserved |
| Grouped text entry | `BusyMarkGroupedTextEntry`: borderless themed TextFormField inside YaruListTile.square, same row/subtitle/error construction | Retained for note, metadata and prompt editing; native text context menu only |
| Shortcut badges | `app/keyboard_shortcut_badge.dart:BusyMarkKeyboardShortcutBadge`: neutral control fill, subtle border, 4px radius, 8/2 padding, Ubuntu Mono/fallbacks, wrap opportunities and original accessible label | Adapted without changing bindings or keymap model |
| Shortcut page/editor | `workspace/presentation/keyboard_shortcuts_settings.dart`: filled command groups with trailing badges; current/proposed group, explicit recording row, feedback/conflict group, standard Cancel and suggested Assign, remove/restore action group | Replaced the flat list and bare capture form; BusyBooks retains conflict rejection and persistence semantics |
| Dialog shell/buttons | `BusyMarkDialogShell`, `BusyMarkDialogButton`, `BusyMarkPushButton`: themed neutral dialog surface/shape, native-style titlebar, bounded scrolling contents and semantic footer actions | Retained repaired shared modal lifetime; route completion precedes caller-owned controller disposal |
| Toast/action | `app/busymark_toast.dart:_BusyMarkToastSurface`: popover-colored decorated surface, transparent ink owner, 16/8 surface padding, semibold body-medium message, themed TextButton action and compact dismiss icon | Retained this specific reference construction. This is the only toast action contract; no general TextButton exemption |
| Surfaces/status/loading | `BusyMarkSurface`, `BusyMarkGroupedSurface`, `BusyMarkStatusBox`, `BusyMarkBanner`, the reference workspace spelling dialog Yaru spinner and Writerside-template Yaru linear progress: semantic fills, themed shape and native card shadows, semantic action buttons | Retained; startup root now explicitly uses the semantic view fill |
| Menus | `BusyMarkMenuButton`/header menu composition, with BusyBooks' existing `NativeMenuService` and GTK/Windows hosts | Commands, submenus, separators, checks/radio, disabled entries, icons and shortcut labels stay native. Presentation failure produces the existing notification; no Flutter menu fallback |

## Screen and consumer review

Paths below are relative to `lib/src/`. The named constructions above apply to
all their normal, empty, loading, error and recovery branches.

| Sources | Visible controls and final composition |
| --- | --- |
| `app/busybooks_app.dart`, `app/app_theme.dart`, `app/desktop_frame.dart`, `app/linux/*` | Stable router/window/overlay ownership retained. Header and window controls use shared HeaderIconButton/hint; theme geometry follows the reference semantic button, input and surface definitions |
| `app/startup_failure.dart`, `app/busybooks_toast.dart` | Startup DialogShell with standard/suggested actions on explicit view fill; toast surface/action follows the exact reference above |
| `app/busybooks_dialogs.dart`, `app/product_actions.dart`, `app/busybooks_main_menu.dart` | Properties, About, confirmations, file recovery, export, error and text prompts all use the shared modal route, DialogShell, semantic actions and grouped entries/rows; native main menu and header trigger |
| `app/busybooks_about_dialog.dart`, `app/busybooks_design.dart:BusyBooksDialogIdentity` | About follows `busymark_dialogs.dart:_BusyMarkAboutDialog`, `_AboutVersionTag` and `busymark_dialog_identity.dart:BusyMarkInformationalDialog`/`BusyMarkDialogIdentity`: 420px shell, fixed untitled close bar, scrollable 16px content inset, centered 128px existing logo and bold headline, muted tagline, accent version pill and filled License/Website/Source-code action rows. The existing DialogShell supplies the same informational geometry; modal ownership is unchanged |
| `workspace/presentation/welcome_screen.dart` | Filled Create/Open groups, ActionRow, SidebarNavigationTile, StatusBox, native recent-item context menus and shared search/header controls |
| `library/presentation/collection_screen.dart` | Grouped book cards/rows, shared sidebar and search controls, neutral PopupSelector for sort/view, semantic file actions and native Book menu; themed progress and status branches |
| `book_workspace/presentation/book_header.dart`, `reading_location_control.dart`, `book_context_menu.dart`, `book_workspace_screen.dart`, `book_pane_layout.dart` | HeaderIconButton, neutral BookViewSelector trigger, native book menu, read-only current-location text with no hint/focus/button, semantic loading-error Retry; existing Reading/Split layout unchanged |
| `reading/presentation/reader_screen.dart`, `reader_sidebar.dart` | Shared header/compact controls, SidebarRecordRow and neutral tree-row activation, native panel selectors/context menus, shared status/retry/progress. No chapter-title tooltip; action-only hints use the same shared tooltip |
| `reading/presentation/appearance_menu.dart`, `selection_menu.dart`, `speech_menu.dart` | Existing native checked/radio menus; no secondary view or fallback. Header trigger has the same neutral button/hint contract |
| `reading/presentation/appearance_panel.dart` | Reading scope and format defaults integrated into a filled group; publisher/font/size, page appearance, PDF/comic options, advanced typography, reset/save defaults all in filled shared groups. All original capabilities/preferences/ownership retained |
| `reading/presentation/font_chooser.dart` | Same settings padding, shared search entry and record rows; standard Close and Refresh/Retry. Narrow scaled heading truncates visually while retaining its accessible name; requests, previews, selection and cancellation unchanged |
| `reading/presentation/reader_panel.dart` | Retained primary-window Look Up surface with shared titlebar close, standard Retry/full-entry actions, shared spinner/error text. Request cancellation and reader session ownership unchanged |
| `notebook/presentation/notebook_screen.dart`, `book_view_selector.dart` | Standard bookmark-filter/Clear Filters actions; neutral reference PopupSelector for kind, note and sort; native checked choices. Existing view routing/layout and draft guards retained |
| `notebook/presentation/notebook_item.dart`, `region_preview.dart` | Standard Add/Edit Note, Retry, Discard, Show More/Less and Show in Reading; grouped entry, native item menu and neutral inline passage hover. Autosave, draft/discard protection and selection unchanged |
| `annotations/presentation/annotation_actions.dart`, `annotation_presentation.dart` | Native highlight/color/context choices, shared Notebook editor handoff and discard confirmation; semantic color presentation retained |
| `search/book_search_widgets.dart`, `book_search_session.dart`, `app/busybooks_search_field.dart` | Shared search entry/clear action, neutral scope/filter selectors, SidebarRecordRow result activation, native result menus, shared Banner/StatusBox/progress and semantic recovery actions |
| `app/settings_screen.dart`, `app/keyboard_shortcuts_settings.dart`, `app/keyboard_shortcut_badge.dart` | General, Accessibility, Data, Reading and Shortcuts use the same filled group/page/row patterns; responsive sidebar selector uses neutral PopupSelector. Shortcut editor owns capture/focus and releases it on all dismiss paths. Late save completion checks that its own dialog remains current before closing; it cannot pop the Settings page during reverse transition |

## Native hosts and reader assets

`linux/runner/reader_host.cc` and `windows/runner/reader_host.cpp` now only position,
composite, dismiss and expose the accessible name of the shared tooltip frame.
They no longer choose tooltip font, padding, border or palette. GTK popup is
pass-through/non-focusable; Windows uses a no-activate transparent layered window.
Activation, key input, deactivation, metrics/theme/scale changes and disposal
invalidate the owned hint. Menu and text-menu hosts remain the existing native
implementations. No retired reader-popover entry point or extra engine exists.
The accepted GTK view-retirement and Snap layout implementations are untouched.

Owned `assets/reader/reader.js`, `reader.css`, `bootstrap.js` and the remaining
owned `.mjs` modules contain no application toolbar, text-input form or Material
menu. Saved-region buttons are transparent publication-coordinate hit targets
with focus/selection outlines. Image/footnote HTML dialogs display publication
content with publication typography/colors and a backdrop; they add no app
button/menu styling. Region guidance and loading use the existing platform menu
font and resolved canvas/foreground variables. These publication presentations
are preserved; vendor assets are untouched and separately integrity-checked.

## Verification boundaries

Production BusyBooksApp/GoRouter tests reproduce backdrop/Escape dismissal while shortcut persistence is held, retain the Settings route, and cover the complete Reading Settings page,
font chooser, shortcut groups/editor/capture/conflicts/persistence, Notebook
buttons and native filter choices. Host-packet tests assert the actual tooltip
RGBA frame, resolved theme/text scale, timing and dismissal on Linux and Windows.
The complete suite retains modal input protection, reader/draft preservation,
menu failure notification, read-only location, and absent Go To/chapter hints.
Physical platform evidence and executable identities are recorded with execution
logs outside tracked source. Passing source/widget checks alone does not establish
Windows native or installed-package visual acceptance.
