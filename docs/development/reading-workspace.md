# Book workspace and native lifecycle

BusyBooks uses BusyMark's common Yaru shell, tokens, header controls, menus,
settings and dialogs. The read-only reference is BusyMark
`7008772ce26b0d133bed9c0d01754b43d93c672b`. In particular, the header View selector
adapts `BusyMarkHeaderPopupMenuButton<DocumentViewModePreference>` in
`workspace_screen.dart`: labeled entries, icons, effective shortcuts and a
trailing selection check. BusyBooks offers Reading, Notebook and Split. BusyMark's
`_EditorPreviewSplit` supplies the side-by-side pane and fixed divider reference;
BusyBooks' adjustable, keyboard-operable divider is a BusyBooks enhancement.

`/` is Home, `/workspace` is the active database collection, `/read/:id` is
Reading, `/notebook/:id` is Notebook, and `/split/:id` is Split. All three book
URLs use one retained
`BookWorkspaceScreen` page/element: common `BookHeader`, persistent sidebar and
one Reading content tree and one Notebook content tree. `BookPaneLayout` changes
their allocation while preserving their parents and state; Split does not create
another reader or Notebook. Reading uses the full width, Notebook uses the full
width, and Split places Reading on the left and Notebook on the right. Reading ↔
Split retains the usable native publication. Settings return targets recognize
these same routes; there is no second route adapter.

The divider retains its ratio for the window session. It has a 12-logical-pixel
hit area, a resize cursor, keyboard focus and increase/decrease semantics. Left
and Right move it by 16 logical pixels; Shift uses 64. Allocation uses the actual
content width after sidebar allocation. With effective text scale `s >= 1`, the
minimum Reading width is `max(400, 320 × s)` and the minimum Notebook width is
`max(360, 280 × s + 64)`, plus the 12-pixel divider. At ordinary text scale,
side-by-side Split therefore needs 772 logical pixels of content width. At
text scales of 150% and 200%, it requires 976 and 1276 logical pixels respectively.
Display scaling is handled by the existing logical-to-native bounds path.

Below that minimum, entry into Split is disabled with its required-width reason
in the selector, Main Menu and command search. An already active Split keeps
`/split/:id` and shows its last focused pane, defaulting to Reading. A nonblocking
status names the visible pane and offers the other pane. This hides the other
content tree without suspending or replacing the reader or discarding drafts,
selection, scrolling, filters or divider ratio. Widening restores the two panes
automatically. Explicit Reading or Notebook selects that full-width route and
cancels this retained Split preference; no application-wide minimum window size
is imposed.

| Owner | Retained state |
| --- | --- |
| `WorkspaceController` | Book identity, stored annotations, collection and availability |
| `bookSidebarProvider(bookId)` | Typed panel, open state, outline expansion/focus, panel offsets, Marks filter/selection, retained publication metadata |
| `bookSearchSessionProvider` | Active/category/query, generation, stable results/selection, loading/error, focus request/return and previous sidebar presentation |
| `NotebookController` | Sort/type/notes filters, identity-relative scroll/reveal, selected editor and protected revisioned drafts |
| `bookPresentationProvider` | Current book, measured Split capacity, divider ratio and last focused content pane |
| `ReaderController` | Native engine/session, positions/history, capabilities, visibility acknowledgements and transient input handoff |

The sidebar family auto-disposes. `retainActiveBookSession` holds its lease only
for the open book, including all three book views and Settings round trips. The
one window search controller retains lightweight category/query/scope/selection memory;
closing it releases results, renderer ownership and outline subscriptions. It does
not retain a controller or reader per visited book. Reopening a book reconstructs
stored metadata and saved preferences; transient Marks and outline browsing starts
a new book session.
Protected Notebook drafts remain owned by `NotebookController`, independently
of these presentation lifetimes.

Collection overview state is keyed by collection ID. Notebook filter/selection/
scroll and unsaved note drafts are application-owned state keyed by book/annotation identity. Routes and
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
insertion remains available across all three views, including without the original
file.
Retries reuse that identity; a held discard settles and removes only its own
creation, preserving newer edits and failed-action state. Existing drafts cannot
use this insertion path. Close, backup, export and restore wait for pending note
actions and writes. Backup and export flush the renderer before notes so final
native draft messages are included.

Book data and annotations live in WorkspaceController, independently of native
renderer readiness. Standalone Notebook never opens a native surface. In that
view the retained Reading presentation is excluded from focus/ticking, its native
surface is hidden, narration is stopped and the renderer is suspended. Split keeps
the reader operational alongside the same Notebook. A collapsed Split hides the
inactive pane without suspending its reader. Missing originals and renderer errors
affect the reader pane; saved notes, Locate and reader Retry retain their existing
owners. Stored annotations/outline metadata remain usable without the original
file or renderer readiness.
Suspension first drains native input and pending layout while the surface can
still produce frames. Only then is it hidden. Renderer acknowledgement and
durable storage remain distinct phases: a failed storage write retains its
protected draft for Notebook recovery. A sealed, suspended reader contributes
no new native input, so later backup/close operations flush application-owned
records without waiting for a hidden rendering frame. Concurrent renderer
drains share one acknowledgement; request IDs reject delayed or unowned replies.
Closing an active reader likewise drains its work before hiding the surface.
Expected speech-service failures remain visible diagnostic state and are logged;
they release narration ownership and do not prevent safe data flushing. Speech
disposal closes the connection even if Stop fails, rejects later requests and
shares its completion across callers. Unexpected programming errors propagate.
Both annotation surfaces mutate the same records. Markdown export includes
quotations, personal notes and readable references, with durable anchor comments.

Reading places Sidebar → Home → Previous → compact location → Next in the
leading header group. The controls and GTK artwork (`go-previous-symbolic` /
`go-next-symbolic`) follow BusyMax's schedule toolbar, inspected at
`3fff55e62ae7dc6467d60309ca988b74d0950bc4`. The location between the chevrons is
BusyBooks' approved composition. Existing focus/hover/disabled states, spacing,
and direction-aware Yaru fallbacks remain. Home uses `go-home-symbolic` and the
existing guarded Home command from Reading, Notebook, Split and collection workspaces;
it flushes protected input and reading state before returning to Home. Repeated
Home/close commands share one in-flight action. Back to Collection and reading history remain separate book-context commands.

The content-sized location trigger displays a printed page label, physical-page
fallback or genuine EPUB reference/progress without a redundant Page prefix.
Its tooltip names Go To; its accessibility description retains the full
page/physical position, also shown in the native Go To surface.
It uses its current header bounds for Go To and disappears before essential
controls when space is short. Search hides both step buttons together; Home
remains available and the retained title/search transition excludes inactive
search input from focus and semantics. There is no permanent navigation footer;
fit/zoom/rotation and image-only-PDF information live in Appearance/View Options.
Inactive narration reserves no strip.

The Reading sidebar adapts BusyMark's `_SidebarHeader`, view menu,
`_SidebarTreeRow` trailing slot and row surface. Outline rows omit decorative
chapter icons while preserving the disclosure slot and depth indentation. Its compact icon menu selects
Outline, Thumbnails for page-based PDF/comic publications, Marks and, inside a
collection, Books. Search Results is not a permanent panel. Selecting the current panel reveals it; the header sidebar
button controls visibility. Reading/Notebook/Split stays a separate header selector.
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

Marks uses publication order and typed All types/Highlights/Bookmarks/Region Notes
filters plus Has Notes. Rows distinguish type, passage, effective private-note
preview, location and selection. Edit Note opens Notebook, reveals that identity
and focuses its editor.
Color updates preserve the same record contract. Marks and Notebook call one
confirmation action inside the existing per-annotation deletion coordination.
Cancellation/failure retains drafts and in-flight save protections.

Notebook defaults to Recently Added (integer creation time descending, identity
as deterministic tie-break), with Book Order and Type alternatives. Its compact
selectors wrap under text scaling. The normal all-types view emphasizes reading
records and explicitly links the count of bare bookmarks to the Bookmarks filter;
Marks always retains those bookmarks. Cards use the shared 760px content width,
show type/date/location/passage and selectable multiline private-note previews,
and offer explicit full-note expansion. Dates outside Dart's supported calendar
range display an unavailable label without modifying the valid stored timestamp.
Annotation `created` values are epoch microseconds, matching both reader creation
paths. Calendar presentation uses that unit directly; it does not rewrite records.

In side-by-side Split, deliberately selecting an annotation through its heading,
Edit Note action or list keyboard selection reveals its validated source in the
adjacent reader while retaining Notebook selection and editing focus. Rebuilds,
autosave, filtering, sorting and restored selection do not initiate navigation.
Ordinary selection preserves the active filters; new annotations appear only when
those filters include them. Reader and Notebook scrolling remain independent.
In collapsed Split, selection edits the note without navigating a hidden reader;
Show in Reading deliberately reveals the Reading pane and its exact source.
Unavailable sources do not prevent note editing. The same Show in Reading action
keeps Split when it is active; the explicit Reading view command chooses full width.

Notebook editing uses the existing debounced autosave: Saving, Saved only after
successful persistence, Save failed and Retry. Discard is offered for a pending
draft; there is no ordinary Save button. The controller's save/flush methods are
retained for transactions, backup and native contextual creation.

Targeted reveal centers the lazy sliver layout on a stable annotation identity.
Both sides remain lazily built, including variable-height records. Reveal clears
conflicting filters and applies once; later manual scrolling is retained relative
to that identity. It does not iterate estimated offsets or scan rendered rows. Sidebar changes capture transient accepted input
before changing native geometry. No new notes store or document type is involved.

Reading and Split with a visible reader use View, Bookmark, compact Appearance,
Book Actions, Search and Main Menu. Standalone Notebook and a collapsed Split
showing Notebook share the header and omit reading-only controls.
The actual header layout decision moves secondary reading commands to Book Actions
when width or search displaces them; its selector visibility is passed to Main
Menu for the sole View Mode fallback. No independent menu breakpoint exists.
Home uses Home terminology and all actions retain command IDs and effective
configurable shortcuts.

Main Menu contains Open Book, Open Collection, Create Collection, Full Screen,
Settings and About, plus that conditional View Mode fallback. Book Properties/Move/Locate/Export,
reading assistance/history and Return to Collection use Book Actions. Backup and
Restore use Settings → Data and the unchanged backup engine/format.

Native menu validation allows disabled single-choice entries and still rejects
multiple selected entries in one contiguous exclusive group. GTK radio actions
use string state/targets; Win32 preserves disabled/radio/selected flags and the
same preorder command indices. Activation checks enabled state and owning menu/
route identity. Recoverable host presentation errors log diagnostics and use the
existing Flutter menu fallback; invalid contracts remain programming errors.
Native failures do not open a blocking error dialog.

The Marks fallback glyph is `YaruIcons.rule_and_pen`; GTK uses the installed
`document-edit-symbolic` mapping. Sidebar-selector tooltips are constrained to
the unobstructed sidebar bounds because Flutter cannot paint over WebKit's GTK
overlay. Sidebar tooltip width is bounded under text scaling. Switching search
presentation dismisses old tooltips and disables tooltip triggers in the retained
offstage navigation; Close Search uses the same placement. Positioning reads
layout constraints rather than another render object's size during overlay layout.
Book-header controls inherit beside-trigger placement within the shared header,
so their hints remain above native content even with the sidebar closed.
Native theme/icon and overlay checks use the
[workspace driver](../../tools/README.md#linux-workspace-and-shutdown-diagnostics).

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
text scaling. Secondary Reading controls move to Book Actions in narrow layouts;
Search, Home and Main Menu remain reachable. Page controls retain their ordering
when the compact location is hidden.

Bookmark guards cover the complete captured book/location toggle before SQL is
queued. Pending activation disables every entry point for that location; failure
clears the guard and preserves the committed selection. Navigation does not move
an in-flight operation to another book. View transitions retain their original
route through queued reads; failed capture/read leaves the current view intact.
Settings accepts only Home, collection, Reading, Notebook and Split return targets;
re-entry is disabled/no-op and cannot overwrite that original destination.

Go To resolves its current header anchor for pointer, shortcut and menu entry.
PDF printed labels and physical position remain distinct; reflowable EPUB/FB2 use
progress/chapter and publisher references without invented screen-page counts.
Comics use physical page count/references, First/Last and the same Go To surface.
PDF's one destination input resolves bare integers as one-based physical pages,
unique nonnumeric strings as exact printed labels, and `=label` as an explicit
printed label (including numeric labels). Duplicate labels are rejected. The
current reference describes both printed and physical positions. There is no
printed/physical mode selector. The compact surface measures its natural height, including feedback and text scaling, and
scrolls inside the acknowledged reader pane. The primary supplies its measured
pane rectangle with each presentation; application-owned native placement caps
the body and its natural-height update to that pane with space for native borders
and the GTK arrow. Header anchors outside the pane cannot place controls over
Notebook. Windows converts the logical pane to screen pixels once and intersects
it with the monitor work area. Controls retain their text scale and wrap or scroll
at the available width. Native preparation allocates a frame
surface without exposing empty interactive controls: GTK maps a transparent,
nonmodal view; Windows uses the existing first-frame callback and redraw sequence.
Channel ready only delivers data. A presentation-specific Flutter paint
acknowledgement, plus native frame readiness, permits presentation and focus.
Each presentation has a keyboard scope below its dismissal shortcuts, so Escape
works before a selection control is focused. The fallback adds no traversal stop;
editor and default-button autofocus retain their normal targets and composition.
Initialization, delivery and build failure settle a bounded primary request with
retry feedback. Retry settles the primary frame that removes this feedback before
requesting native presentation, so its publication-bounds update cannot cancel
the new popup; rapid replacements share the same bounded layout barrier. Cancellation, replacement and stale callbacks cannot reveal the
old presentation. A never-ready timed-out engine can be recreated on retry;
engines that may contain accepted input remain available for protected capture.
Go To waits for a correlated renderer navigation result before closing; failed or
cancelled page work keeps the form available. Controlled tests exercise the
channel/paint protocol; actual GTK/WebView2 placement and focus require native
acceptance as described in [development tools](../../tools/README.md).

Reading retains Foliate.js, PDF.js, the labeled sidebar, search, appearance,
selection controls, dictionary and narration. Entering standalone Notebook stops
narration, retains the reading position and suspends native focus. Reading ↔ Split
keeps the same usable reader; a deliberate Notebook passage jump enters reading
history. Session/generation guards reject stale callbacks. Visibility intent is
separate from geometry, but a positive native reveal requires acknowledgement of
the current book/session's measured reader-pane bounds. Hidden panes, overlays and
modal routes cannot receive native pointer, keyboard or accessibility focus.

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
explicit save warning/retry. PDF search retains original UTF-16 ranges and maps them back to
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
keyboard reachable. Notebook/Marks offer a Region filter and return to
the correct page and region. A page bookmark's optional note remains page-wide;
independent regions never participate in page-bookmark deduplication. Ordinary
renderer annotation payloads still omit private note text.

Notebook region cards read optional artwork from the existing sealed comic cache
through a value-keyed, auto-disposed provider. The worker validates the owning
book/cache identity, page identity, resource budgets, hashes and oriented dimensions
before decoding. It samples directly into a bounded 640 × 360 PNG preview without
opening the original, rebuilding a cache or changing annotation records. Missing
or invalid artwork has an inline Show in Reading recovery action; the complete
private note remains available. Returning from Reading retries unavailable
artwork. This adds no persistence domain or backup field.

## Selected-text actions

The selection popover includes Search in This Book and Look Up. Search captures
the entire trimmed passage (including Unicode and footnote selections), opens
the shared header field and temporary Book Text search session, and starts an
owned immediate engine search. Repeating it starts a new query revision without
advancing a result. The publication stays at its passage until a result or result
navigation command is chosen; Back/Forward and Return keep their existing engine
history. The header controller receives external query changes only; ordinary
edits, caret positions and IME composition are not overwritten during rebuilds.

Look Up and Book Actions' Dictionary command share one workflow. After the existing
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
feedback. [The selection/lookup contract](readers.md#selection-search-and-online-lookup)
and [known issues](known-issues.md) describe service limits and remaining
qualification boundaries. Controlled checks do not establish native acceptance.

## Local font selection

Settings → Reading owns the advanced searchable local-family chooser and bounded
native sample. The compact native reading popover presents only theme, size,
spacing, width/margins and publisher style, or applicable fit/zoom/rotation/spread
controls for fixed layouts. More Reading Settings opens the current-book scope
explicitly; global defaults remain separately selected. Candidate movement never
saves or repaginates; explicit activation
uses the existing book/default writer. Publisher mode retains the custom choice;
unavailable choices retain their identity and show a local fallback explanation.
Renderer-supplied typography capabilities gate the controls and application path.
See [typography.md](typography.md) for the shared model, separate-engine cache,
Settings chooser Escape/focus and disposal and durable reflow/selection
ownership. The shared header/sidebar and single Reading/Notebook content trees
are retained across Reading, Notebook and Split.


## Shared search and adaptive presentation

Search follows BusyMark's one-header-query, temporary-results-sidebar pattern.
The stable category order is Book Text, Notebook, Bookmarks, Chapters, Books,
Recent, Actions; genuinely inapplicable categories are omitted. Home offers
Notebook, Bookmarks, Books, Recent and Actions; Settings offers Actions, without
using a retained hidden publication as a search target. There is no combined
category, separate results window, private Notebook query or collection-grid search.
The collection grid keeps its independent reading-state filter, sort, selection,
view mode and scrolling. Ordinary sidebar widgets remain mounted offstage, excluded
from focus/semantics/ticking, and return when search closes.

Notebook and Bookmarks search persisted annotations through the SQLite worker,
including unopened books and missing originals. Their explicit scopes are This
Book, Current Collection and All Saved Books. Books searches title, author, series
and original filename/path in Current Collection or All Saved Books. Context shows
the actual book/collection name. Defaults follow the visible surface; category
commands choose that default explicitly. The Search icon restores its last
applicable category and scope. Opening a result retains its originating scope and
never adds membership or broadens a collection search. Recent filters existing
book/collection resources in their original chronological order.

Content categories wait for a nonempty query and show “Enter text to search.”
Whitespace remains searchable. Clearing invalidates requests and removes results
and selection. Actions deliberately displays the grouped catalog initially,
including unavailable and unassigned commands. Typed Actions queries rank name,
prefix/token and metadata matches. Identity-preserving updates include shortcuts,
availability and disabled reasons, using the current command registry at activation.

Search debounces for 120ms. Enter flushes that work, awaits results and validates
the original generation before activation; repeated Enter cannot overlap navigation.
Up/Down selects without opening. F3/Shift+F3 navigates Book Text occurrences only,
requests bounded windows beyond the displayed page and wraps at the actual book
boundaries. Previous without an active occurrence selects the last occurrence.
Tab traverses controls normally, IME composition remains local, and Escape dismisses
an active popup before closing search. The clear affordance retains search.
Category selectors show current effective bindings; Books and Recent default to
Ctrl+Shift+D and Ctrl+Shift+R, while Marks retains Ctrl+Shift+H. Other category
commands can be assigned in Settings.

In Split, Ctrl+F opens Book Text from the reader and This Book Notebook search
from Notebook. Shared chrome uses the last focused content pane, defaulting to
Reading. Explicit category commands retain their designated category. Reading
and Notebook view commands default to Ctrl+Alt+1 and Ctrl+Alt+2; Split is available
in the same registry and shortcut settings with no default assignment. Text
editing, clipboard commands, undo and IME composition remain with the focused
Notebook editor. Both visible panes do not imply publication keyboard ownership.

Book Text searches only the active publication via application-owned reader code.
PDF support is publication-level: an image cover, illustration or blank current
page cannot disable, cancel or switch search. A scanned PDF may finish without
matches. Comics do not support Book Text. Reader readiness and suspension are
separate states; a supported loading reader retains its query, while a suspended
reader offers an explicit Reading action. Search does not start a hidden reader.
For a renderer failure, Retry uses the existing reader recovery workflow and
resumes Book Text with the retained query, including edits made during recovery,
when the correct book's reader becomes ready. An ordinary search failure retries
only the search operation. A same-book Reading ↔ Split change retains the active
request/results and recovery ownership; leaving those reader views abandons a
pending recovery, including after a later return. Readiness submits the latest
applicable query without collapsing Split.
Literal matching is Unicode case-insensitive and non-overlapping, without regex
syntax, accent folding, normalization or whitespace trimming. Exact offsets refer
to original publication text; EPUB/FB2 matches can span inline markup and PDF
matches can span text items. See [reader matching](readers.md).

Results identify their book, source reference and matching excerpt; chapters retain
publication order and ancestor context. Wrapping rows follow text scaling, and
selection scrolls using measured geometry. Bounded retrieval exposes Show more
results without claiming the loaded subset is an exact total. Loading, unavailable
sources, errors/retry and completed empty results have distinct presentation.
Notebook results open the exact annotation editor; passage navigation is a separate
row action. Bookmarks navigate directly when their original is available, while
missing records remain accessible through Notebook and Locate. Books/Recent reuse
opening and missing-file recovery. Captured identities, source digests, membership,
query generation, renderer ownership and route transitions are revalidated after
asynchronous waits. A result's owned handoff is accepted; unrelated navigation
invalidates pending work. Wide layouts retain cross-book search during handoff;
narrow layouts dismiss the same overlay while keeping lightweight query memory.
Deferred passage jumps bind the target book, claimed opening revision and
activation ownership until dispatched or abandoned. Source records and anchors,
query/scope and renderer ownership are checked again before the eventual `goto`,
including after queued dispatch waits. A replacement, failed opening, close,
suspension or unrelated navigation abandons the request, so another book cannot
consume its anchor. Narrow dismissal preserves the owned activation until that
request completes or is abandoned.

Book Text and Chapters navigate the reader within Split, while Notebook results
reveal the exact note there. Cross-book note/bookmark activation captures a Split
target from its originating route, retaining the category, scope and query through
its own handoff. Home and other non-Split origins keep their normal destinations.
In collapsed Split, an explicit passage action selects Reading and binds a jump
to the retained ready opening until the measured reader pane becomes visible;
it does not force-show native content over Notebook. The explicit existing-opening
intent differs from a request waiting for a new opening: a fresh open, close or
session replacement still invalidates the former. Note results select Notebook
and hide the native surface before that pane handoff. The existing narrow search
overlay still dismisses for activation independently of this Split width policy.

Native visibility uses separate route/modal and workspace gates. Opening shared
chrome captures transient input, dismisses without restoring publication focus,
and explicitly transfers GTK/Win32 ownership to Flutter. Session-scoped handoff
cannot focus an inactive window or owned native popover. Flutter focus alone does
not transfer GTK/WebView2 ownership. Trusted pointer/focus notifications identify
only the current visible publication document; the primary verifies native focus,
session and focus revision before accepting them. Late native keys cannot replace
Notebook's last-focused-pane intent. Flutter mirrors each native focus revision
once; its inactive-window blur does not itself reclaim OS focus. If that first
mirror loses native ownership, one post-frame native query can reconcile it only
while the same publication focus target, session, revision and presentation remain
current. Explicit chrome/editor handoffs cancel that reconciliation. Positive
native focus requests also validate their renderer session and exclude popovers.
Divider/sidebar/window resizing updates native
bounds to the reader pane before reveal and refreshes selection rectangles without
changing their durable anchors or reopening selection popovers. Closing search
restores a valid origin focus
or the active publication. No query is saved into settings, recovery or backups.

Settings uses typed General/Reading/Accessibility/Keyboard Shortcuts/Data pages,
a wide sidebar or narrow selector and the semantic main view surface. Reduced
Motion is explicitly informational system status. Per-book reading controls are
available only for the Settings return book that owns the retained renderer.
Collection uses LinuxPageFrame's dismissible narrow overlay without reserving
sidebar padding. Overlay bodies and retained inactive panels exclude hidden
focus targets; native visibility uses separate route/modal and workspace gates.
Opening shared chrome captures transient input, dismisses without restoring native
publication focus, and explicitly transfers GTK/Win32 ownership to the main view.
That request carries the renderer session and cannot focus an inactive window or
an owned native popover. Native Tab traversal uses the same handoff. Flutter focus
alone does not move GTK/WebView2 keyboard ownership. Restore's confirmation uses
its own Restore label, rather than the generic Open default.

Queued preferences capture their store before asynchronous serialization, so
accepted writes can finish after provider disposal without accessing a dead Ref.
Annotation mutation failures return to the draft or contextual action that owns
recovery. They do not publish SQL/private-note details into Home's workspace
failure state. A failed draft remains protected and Retry retains the original
conditional write/creation contract.
Shortcut maps include visible commands in the current route, so hidden Collection
Search cannot shadow Book Search's Ctrl+F in Notebook. Disabled visible commands
still own their combination and retain the existing text-editing safeguards.

GTK window destruction releases the native reader/popover, chrome hosts and
channels before GTK disposes the main Flutter view and overlay. Application
disposal is an idempotent fallback. See [known issues](known-issues.md) for the
separate intermittent Linux compositor shutdown abort.
