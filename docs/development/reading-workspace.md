# Book views and native lifecycle

BusyBooks uses BusyMark's common Yaru shell, tokens, header controls, menus,
settings and dialogs. The read-only reference is BusyMark
`7008772ce26b0d133bed9c0d01754b43d93c672b`. In particular, the header View selector
adapts `BusyMarkHeaderPopupMenuButton<DocumentViewModePreference>` in
`workspace_screen.dart`: labeled entries, icons, effective shortcuts and a
trailing selection check. BusyBooks offers only Reading and Notebook.

`/` is Home, `/workspace` is the active database collection, `/read/:id` is
Reading, and `/notebook/:id` is Notebook. Collection overview state is keyed by
collection ID. Notebook query/filter/selection/scroll and unsaved note drafts
are application-owned state keyed by book/annotation identity. Routes and
filters may dispose widgets without discarding drafts. Debounced saves preserve
revision identity, a saved baseline and the owning book identity. A targeted
repository lookup supplies the baseline for each edit session, including when
the active list belongs to another book. Discard pauses
autosave before confirmation, settles an existing write and restores the
captured baseline in SQLite. It acknowledges only the targeted edit; newer
edits remain. Cancelling resumes autosave. Failure retains the draft and reports
the unfinished action. Editor refresh uses this shared state, not a captured
widget note.

Every deletion goes through WorkspaceController and the same per-annotation
coordination. It settles a pending save before deleting and clears drafts only
after successful deletion. Existing-note updates require the correct book ID
and an existing row; they cannot insert. New annotation creation is explicit.
Before the first insertion, the primary Notebook controller retains the complete
captured passage, stable annotation/book IDs and revisioned note text. A failed
insertion remains available in both views, including without the original file.
Retries reuse that identity; a held discard settles and removes only its own
creation, preserving newer edits and failed-action state. Existing drafts cannot
use this insertion path. Close, backup, export and restore wait for pending note
actions and writes. Backup and export flush the renderer before notes so final
native draft messages are included.

Book data and annotations live in WorkspaceController, independently of native
renderer readiness. Notebook never opens a native surface. It requests one
book's annotations and metadata and works when all original paths are missing.
Both annotation surfaces mutate the same records. Markdown export includes
quotations, personal notes and readable references, with durable anchor comments.

Reading places Sidebar → Home → Previous → compact location → Next in the
leading header group. The controls and GTK artwork (`go-previous-symbolic` /
`go-next-symbolic`) follow BusyMax's schedule toolbar, inspected at
`3fff55e62ae7dc6467d60309ca988b74d0950bc4`. The location between the chevrons is
BusyBooks' approved composition. Existing focus/hover/disabled states, spacing,
and direction-aware Yaru fallbacks remain. Home uses `go-home-symbolic` and the
existing guarded Home command from Reading, Notebook and collection workspaces;
it flushes protected input and reading state before returning to Home. Repeated
Home/close commands share one in-flight action. Back to Collection and reading
history remain separate menu commands.

The content-sized location trigger displays a printed page label, physical-page
fallback or genuine EPUB reference/progress without a redundant Page prefix.
Its tooltip/accessibility description retains the full page/physical position.
It uses its current header bounds for Go To and disappears before essential
controls when space is short. Search hides both step buttons together; Home
remains available and the retained title/search transition excludes inactive
search input from focus and semantics. There is no permanent navigation footer;
fit/zoom/rotation and image-only-PDF information live in Appearance/View Options.
Inactive narration reserves no strip.

The Reading sidebar adapts BusyMark's `_SidebarHeader`, view menu,
`_SidebarTreeRow` trailing slot and row surface. Outline rows omit decorative
chapter icons while preserving the disclosure slot and depth indentation. Its compact icon menu selects
Outline, PDF-only Thumbnails, Annotations, Search Results and, inside a
collection, Books. Selecting the current panel reveals it; the header sidebar
button controls visibility. Reading/Notebook stays a separate header selector.
Context rows use collection names and book titles, never collection paths.

Outline uses ordered publication navigation with stable preorder identities,
parent/child relationships and exact destinations. Branches initially expand,
following BusyMark. Later metadata and location updates preserve user collapse,
focus and scroll. An active collapsed descendant selects its visible ancestor;
ordinary publication scrolling does not recenter the sidebar. Arrow keys traverse
visible rows and branches, and Enter/Space follows the destination. Disclosure
only changes expansion. Long/deep trees remain lazy rows with directional
indentation and a trailing page column. Per-book application state retains each
panel's scroll, expansion, filters, selection and search across view changes.

Optional outline/page resolution follows the first usable passage. PDF named
destinations retain within-page coordinates and rectangles; invalid targets do
not disable siblings. Structural messages use bounded chunks and revisioned
patches. Printed PDF labels and physical pages remain separate. EPUB page labels
come only from its publisher page-list mapping, evaluated at the destination's
start. A reflowable/fixed EPUB without verified print pagination shows an
explained unavailable marker, not a guessed spine page or progress percentage.

PDF previews use PDF.js, including image-only pages: at most two render jobs,
a visible/nearby window of at most twelve, and a twenty-second per-page deadline.
Changing windows cancels obsolete jobs; failures wait for explicit Retry. The
primary cache retains at most thirty-two previews and eight MiB. Images preserve
aspect ratio; page selection uses the same location formatting/history as
Outline and Go To. No EPUB page-preview capability is advertised.

Annotations uses publication order and All/Highlights/Bookmarks/Regions plus With Notes.
Compact previews use the effective protected draft; complete notes stay in the
existing store/controllers and Notebook. Context actions share deletion, color
and edit coordination. Open in Notebook reveals the requested item, then leaves
later user scrolling alone. Sidebar changes capture transient accepted input
before changing native geometry. No new notes store or document type is involved.

Reading's ordinary trailing controls are View, Bookmark, Appearance/View Options,
Search in Book and one Main Menu, in that order. Notebook has View, Search in
Notebook and one Main Menu; Export/Move/Locate remain in its contextual Main Menu.
Annotation and Recent row menus have their own descriptive labels. Native GTK
header artwork reaches the real app through the initialized icon provider's
inherited notifier scope, including live catalog replacement and Yaru fallbacks.
Only reader-specific native view/control mappings are requested. Notebook has
its own `notebookView` Yaru pen glyph and `document-edit-symbolic` GTK mapping;
Reading keeps `view-paged-symbolic`. Sidebar Annotations retains its independent
history glyph/mapping. The installed Yaru and Adwaita themes resolve and render
the two view symbols through the actual native loader at 1×/2× without a display;
this is resource verification, not desktop menu/visual acceptance.

Main Menu uses the existing native/nested fallback menu bridge with command
icons, effective accelerators and contextual groups. The header's one actual
selector-visibility decision is also passed to Main Menu: its View submenu is
present only for an active book when the selector is hidden (Reading compact or
search, Notebook search). The menu does not compute a second width threshold.
Visible selectors and fallback entries use the same command IDs/shortcuts;
Reading/Notebook and panel entries have exclusive checks; Full Screen, Sidebar, Search and Bookmark use
toggle checks. Full Screen follows window-service notifications. Book commands
remain available to Notebook independently of renderer readiness. Captured
route/workspace ownership is rechecked before command execution. Menu loading,
selection and host errors use awaited application-level feedback.

Windows' native view-mode entries receive bounded alpha masks rasterized from
the existing Yaru glyphs at the current display scale (16–64 pixels). The Win32
host colors their DIBs with system menu/high-contrast colors, validates dimensions
and a 64 KiB aggregate mask cap, and owns bitmaps until menu disposal. Labels,
radio checks and command/session indices remain unchanged. Preparation checks
owning context/session again before presenting. The existing Flutter fallback
uses the same glyphs. This follows the existing native menu contract with
optional bitmap fields, not a new menu host or icon dependency; actual Windows
compilation/painting requires a Windows environment. Win32 bitmap item behavior
uses [MENUITEMINFO](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-menuiteminfoa).


Header actions share that command boundary. Appearance retains a live header
anchor, including Retry after resize; input capture and native session guards
remain unchanged. Header space accounts for window-control obstructions and
text scaling. Secondary Reading controls move to Main Menu in narrow layouts;
Search, Home and Main Menu remain reachable. Page controls retain their ordering
when the compact location is hidden.

Bookmark guards cover the complete captured book/location toggle before SQL is
queued. Pending activation disables every entry point for that location; failure
clears the guard and preserves the committed selection. Navigation does not move
an in-flight operation to another book. View transitions retain their original
route through queued reads; failed capture/read leaves the current view intact.
Settings accepts only Home, collection, Reading and Notebook return targets;
re-entry is disabled/no-op and cannot overwrite that original destination.

Go To resolves its current header anchor for pointer, shortcut and menu entry.
PDF printed labels and physical position remain distinct; reflowable EPUB/FB2 use
progress/chapter and publisher references without invented screen-page counts.
Comics use physical page count/references, First/Last and the same Go To surface.
The form measures its natural height, including feedback and text scaling, and
scrolls only inside native screen bounds. Native preparation allocates a frame
surface without exposing empty interactive controls: GTK maps a transparent,
nonmodal view; Windows uses the existing first-frame callback and redraw sequence.
Channel ready only delivers data. A presentation-specific Flutter paint
acknowledgement, plus native frame readiness, permits presentation and focus.
Initialization, delivery and build failure settle a bounded primary request with
retry feedback. Retry settles the primary frame that removes this feedback before
requesting native presentation, so its publication-bounds update cannot cancel
the new popup; rapid replacements share the same bounded layout barrier. Cancellation, replacement and stale callbacks cannot reveal the
old presentation. A never-ready timed-out engine can be recreated on retry;
engines that may contain accepted input remain available for protected capture.
Go To waits for a correlated renderer navigation result before closing; failed or
cancelled page work keeps the form available. Controlled tests exercise the
channel/paint protocol; actual GTK/WebView2 first-frame/focus/monitor behavior
still requires authorized native acceptance.

Reading retains Foliate.js, PDF.js, the labeled sidebar,
search, appearance, selection controls, dictionary and narration. Changing views
stops narration, retains reading position and hides/removes native focus. Returning
to the same usable surface restores visibility without a navigation command;
a Notebook passage jump deliberately enters reading history. Session/generation
guards reject stale callbacks. Native visibility remains independent of geometry.

The existing restricted transient Flutter view above WebKit/WebView2 is retained.
It runs the same official Flutter bundle and shared controls. Persistence remains
in the primary application. Note draft messages reach primary application state
before transient controls disappear. Reopened editors use the effective shared
draft without changing the authoritative Discard baseline. Session/presentation
and revision guards protect status replies; asynchronous status updates never
reset an active text field. Explicit Save latches its request synchronously:
the note becomes read-only, including the input event before the next frame,
and repeated Save is ignored. Timeout reports an unconfirmed operation and
keeps that guard until the primary reply. Failure unlocks the owning editor;
success seals its closing presentation until replacement. Actions retain their
original session/presentation, and ignored queued actions are acknowledged
without changing current data. Close/Escape still preserves shared drafts.
Native menus retain the existing hosts.

Reading and storage share the existing 1,000,000 UTF-16-unit note bound (no
null characters). The Reading field refuses unsupported changes without
replacing its prior text. Popover actions allow at most 6,065,536 UTF-8 bytes:
six bytes per unit for worst-case JSON escaping, plus 64 KiB for the envelope.
Both popover hosts and their trusted forwarding callbacks use the same header
constant; the primary validates this popover-only budget and leaves publication
event/command bounds unchanged. Initial publication opening and later annotation
updates use the same non-mutating projection: locations, identities, kind,
colors and saved quotations/references remain; private notes stay in primary
state. Private note length cannot inflate either renderer command. Annotation
counts, quotations and geometry still share the ordinary 1 MiB dispatch bound.
`reader-action-size` means native rejected before forwarding: it settles the
local request, restores editing and reports that text is still local. Unknown
delivery failures and timeouts retain their real result waiter and Save guard.
A direct native-reply observer remains active after timeout: a later definitive
rejection releases only that request, while an uncertain outcome stays guarded.

Before replacement, dismissal, flush or close, the primary uses the existing
native channel's bounded `capturePopover` handoff. The transient view returns
only its unacknowledged revision and ownership; the primary attaches it to the
existing book/passage context and shared draft lifecycle. Closing/replacing
seals the field synchronously until handoff succeeds; a failed handoff retains
the editor and blocks destructive disposal. Book replacement captures before
the preparing phase invalidates the old session. Existing drafts retain their
book identity and conditional update; no creation is inferred from a missing
loaded-list item. Successful capture is
acknowledged by revision before the presentation changes. Backup/export still
flush shared notes after the renderer/capture phase, so delivery or save failure
cannot silently produce an incomplete successful flush.

Startup has module-initialization and publication-opening phases. A handshake
starts a separate bounded first-passage deadline; only `opened` declares usable
content. Timed-out/fatal sessions reject late success. PDF opening requires its
first visible page; render failures reject that operation, while cancelled or
obsolete layout work resolves distinctly. Optional labels, metadata, outline and
cover processing follow the first passage and fall back independently.

Fatal publication errors stay visible until explicit recovery succeeds.
Persistence failures retain the readable surface and pending position with an
explicit save warning/retry. PDF search maps transformed Unicode ranges back to
original text before calculating text-layer anchors and excerpts.

Native rendering, keyboard traversal, accessible publication text, popover
stacking, audible speech, scaling and visual comparison require actual Linux
and Windows execution. Controlled channel/DOM tests do not establish those.


## FB2 and comic controls

FB2 uses the existing reflowable appearance defaults, local fonts, text search,
selection actions, dictionary, narration and protected note editor. Outline,
search, position, selection, footnotes and narration emit the same typed durable
FB2 locator. Notes made inside an FB2 note body reopen that body on return.

CBZ and CBR share page controls, sidebar thumbnails, fit-page/fit-width, zoom,
panning, single/spread presentation and automatic/LTR/RTL direction. Wide pages
occupy a spread by themselves. View changes preserve the selected page and
applicable normalized scroll position. Artwork colors remain unchanged by the
application theme. Comic view defaults have their own settings entry; PDF
rotation/tint defaults keep their existing meaning. Text search, selection,
dictionary and read-aloud are absent for image-only comics. Notebook search and
private notes remain available.

On a comic, the existing Add Note command enters a temporary rectangle mode
inside one image. Drag a rectangle, or use arrows to move, Shift+arrows to resize,
and Ctrl for smaller steps; Enter confirms and Escape cancels. Ordinary drag
panning resumes outside selection mode. Confirming opens the existing native
note editor with the captured session, book, page and rectangle. Save, failed-save
draft retention, Retry and deletion use the existing protected workflow. The
region is normalized against the oriented intrinsic image and painted/hit-tested
with one shared transform. Saved region buttons open the same editor and are
keyboard reachable. Notebook/Annotations offer a Region filter and return to
the correct page and region. A page bookmark's optional note remains page-wide;
independent regions never participate in page-bookmark deduplication. Ordinary
renderer annotation payloads still omit private note text.

## Selected-text actions

The selection popover includes Search in This Book and Look Up. Search captures
the entire trimmed passage (including Unicode and footnote selections), opens
the existing header field and Search Results panel explicitly, and runs the
existing immediate search. Repeating it starts a new query revision without
advancing a result. The publication stays at its passage until a result or result
navigation command is chosen; Back/Forward and Return keep their existing engine
history. The header controller receives external query changes only; ordinary
edits, caret positions and IME composition are not overwritten during rebuilds.

Look Up and Main Menu's Dictionary command share one workflow. After the existing
explicit online-consent dialog, a compact owned native popover shows the full
term, loading state, selectable plain-text definition excerpts, language/part of
speech labels, English Wiktionary attribution and Close. Open Full Entry is an
explicit browser action when an entry is available. Errors remain inside the
popover; connection, timeout, service and invalid-response failures offer Retry.
Escape dismisses using the existing native focus-return path. Lookup dismissal
returns Flutter and native keyboard focus to the publication even while search
is open, including GTK's own Escape dismissal before a Flutter action; book/session/presentation checks reject an obsolete focus handoff. The surface scrolls
inside narrow bounds and keeps the publication visible at the same location.

Both handoffs retain protected note capture, annotation ownership and save-failure
recovery. Lookup results are scoped to their captured book/session/presentation,
term and revision. Status updates neither replace a newer popover nor request
focus. Native dismissal invalidates pending work even without a Flutter action.
See [readers.md](readers.md#selection-search-and-online-lookup) for the verified API
format, English-only definition text, phrase/selection limits and excerpt bounds.


The lookup shares Go To's natural-height/paint acknowledgement. Its complete
scrolling contents are measured independently of the current native allocation,
so replacing a short loading state can grow into a readable definition. Long
excerpts scroll inside native bounds. Stable keys keep keyboard focus attached to
the same action when a status update adds Retry or Open Full Entry beside Close.
GTK transient-view construction clears the owning view's current GDK GL context
before creating the pinned Flutter engine and before explicit realization; this
avoids the reproduced blank compositor surface without changing the SDK or host.
A hide notification preceding failed presentation still preserves primary Retry
feedback. [Selection/lookup verification](selection-lookup-verification.md)
separates deterministic coverage, public provider checks and native execution.

## Local font selection

Appearance and Settings use the same searchable local-family chooser and bounded
native sample. Candidate movement never saves or repaginates; explicit activation
uses the existing book/default writer. Publisher mode retains the custom choice;
unavailable choices retain their identity and show a local fallback explanation.
Renderer-supplied typography capabilities gate the controls and application path.
See [typography.md](typography.md) for the shared model, separate-engine cache,
GTK chooser Escape handoff, native-hide disposal and durable reflow/selection
ownership. The header/sidebar and Reading/Notebook composition are unchanged.
