# Reader architecture and supported formats

EPUB uses [Foliate.js](https://github.com/johnfactotum/foliate-js) pinned to
`78914aef4466eb960965702401634c2cb348e9b1` (MIT). Its EPUB loader,
reflow paginator, fixed-layout renderer, CFI resolver, text walker and
overlayer remain unmodified. BusyBooks owns literal text matching and uses the
publication document/range APIs to obtain navigation CFIs. The upstream project documents both renderer
interfaces and has no stable release/API promise; a pinned vendored revision
avoids an unreviewed runtime update. EPUB 2 and 3 use this loader. FB2 and comics
construct book objects through its documented book interface and share Foliate
mounting, navigation and layout. Its demo, generic format dispatch and browser
ZIP loader are not application dependencies.

PDF uses [Mozilla PDF.js](https://mozilla.github.io/pdf.js/getting_started/)
5.5.207, build `527964698` (Apache-2.0), directly rather than Foliate's
experimental PDF adapter. Worker code, CMaps, standard fonts, image/color WASM,
fallback scripts, ICC resources and their licenses are local assets. The adapter
uses actual PDF pages, text layers, page labels, outline, destinations and
PDF-coordinate highlight rectangles. Canvas rendering is for PDF pages only.
A retained hidden Split pane pauses application-scheduled PDF layout: BusyBooks
quiesces existing navigation and appearance work while the native view still
produces frames, then hides it. Resize requests coalesce until native visibility
and the acknowledged pane bounds return. Hidden flush/export preserves the last
settled PDF source rather than deriving coordinates from hidden DOM geometry.
This uses the engine's normal display render tasks without changing PDF.js.
Publication search yields through the application event loop and can finish
while the native view is hidden; it does not wait for animation frames.

Both engines run in the native desktop hosts described below. Controlled
adapter tests, native engine probes and full application acceptance have
different scopes; see [development tools](../../tools/README.md) and
[known issues](known-issues.md).

## Supported inputs

| Input | Reader and durable identity |
| --- | --- |
| PDF | PDF.js; SHA-256 of original bytes; PDF page/text geometry |
| EPUB 2/3, DRM-free `.kepub.epub` | Foliate EPUB loader; original bytes and EPUB CFIs |
| `.fb2` | FictionBook XML; semantic `fb2`; original XML bytes |
| `.fb2.zip`, `.fbz` | Exactly one eligible FB2 document; semantic `fb2`; complete original ZIP bytes |
| `.cbz` | Shared image-comic reader; complete original ZIP bytes |
| `.cbr` | Shared image-comic reader with bundled UnRAR; complete original RAR bytes |

Suffix recognition is case insensitive and checks `.fb2.zip` first; content
validation follows suffix recognition. Generic ZIP/RAR/XML, standalone `.kepub`,
DTBook/DAISY, audio and protected content are outside the input profile. Kobo
accounts and publication conversion are not part of reading.

Comic pages support static baseline/progressive JPEG, RGB/RGBA/grayscale PNG
and lossy/lossless WebP. Animated pages and other encodings, including GIF, BMP,
TIFF, AVIF and SVG, fail explicitly without dropping or renumbering pages.
Corrupt headers fail preparation; later decode errors fail the page operation.
Opening requires a decoded, laid-out initial page. Optional ComicInfo supplies
title, creator roles, series, language, cover, direction, wide-page and bookmark
metadata; enumerated images determine page count. Resource budgets are in
[storage.md](storage.md#publication-resource-budgets).

## RAR decoding

The bundled UnRAR 7.21 worker supports RAR4/RAR5 stored, compressed and solid
archives. CRC/data corruption, unsafe or duplicate paths, links, encryption and
multipart input are rejected. RAR4 non-ASCII filenames need an unambiguous
Unicode field; the application does not guess an OEM codepage. SFX, other RAR
generations, dictionaries above 256 MiB, unsupported decoder features, passwords
and volume acquisition are outside the supported profile.

The decoder runs in a separate killable process with a 768 MiB memory limit,
three-minute deadline and 25 ms cancellation polling. Header preflight checks
retained/discarded budgets and free space before extraction; a second pass
streams and verifies data/CRC. Numeric staging paths prevent archive-controlled
extraction paths. Cancellation kills an active solid decoder and removes staging.

The unmodified source archive, checksum and redistribution terms are documented
in [UnRAR provenance](unrar-provenance.md). Complete licenses and
acknowledgements ship under `share/licenses/unrar`. UnRAR permits RAR handling
and redistribution but prohibits developing a RAR-compatible archiver or
recreating the proprietary compression algorithm. BusyBooks' own code remains
Apache-2.0. Libarchive was rejected as the backend because its
RAR4 solid handling failed the representative fixture.

## Dependency provenance

Distributed third-party files are byte-identical to their official pinned
sources. BusyBooks does not maintain vendor patches or replace engine methods
at runtime. Application loading, metadata and presentation integration remains
separate from those implementations.

[`tools/vendor-manifest.json`](../../tools/vendor-manifest.json) records the
official source, immutable revision or release, upstream file path and SHA-256
for every distributed vendor file. Git-sourced files also record their upstream
blob identity. Its baseline was established against official Git objects and
release archives, rather than by hashing a locally modified vendor tree.

| Dependency | Verified official baseline |
| --- | --- |
| Foliate.js | Commit `78914aef4466eb960965702401634c2cb348e9b1`, tree `72c695f2511bcfc0e3dc37385b81daa5f6fe6930`; all twelve distributed files, including licenses and README |
| PDF.js | Official `pdfjs-5.5.207-dist.zip`, SHA-256 `b37ad762eb7c16fccbf09452c4386e910cc86c9cb736843b77440ac373c6f046`; text-layer stylesheet from source commit `5279646985f4744386a9fe3cf61b28bf1ff88d6e` |
| UnRAR | Official `unrarsrc-7.2.6.tar.gz`, SHA-256 `d1afa67ef4121ebc5986815699e05db0ce8648499e5dca854f282a4c3f72c003`; original license and acknowledgement bytes |
| WebView2 SDK | Official Microsoft NuGet package `1.0.3537.50`, SHA-256 `5ea526bbd728adda0da4d31219267e96460494a427e4894c4e09d9f320f4b9aa`; verified by CMake before extraction |

`tools/verify_vendor.py` checks exact inventory and bytes, rejecting modified,
missing, unexpected or linked vendor files. It accepts no vendor-patch exception
list. Git attributes disable text conversion in vendor trees so Windows
checkouts preserve upstream bytes, including original notice line endings.
Application-owned provenance documentation lives outside vendor trees; every
file under those trees must have verified upstream provenance.

CI and packaging run the same offline check against repository files and the
actual Linux/Windows release bundle. The build-tree check also compares the
complete extracted UnRAR and WebView2 SDK inputs with their verified archives,
detecting build-time rewriting. Source archives are checked before extraction;
packaged reader assets and notices are checked after the build. Neither normal
reading nor normal verification requires network access.

When establishing or changing a baseline, obtain the exact sources from their
official URLs and use `--upstream SOURCE=PATH` to repeat the independent
comparison. The verifier never downloads dependencies or replaces a baseline
with checksums of the current tree. See [development tools](../../tools/README.md#upstream-integrity)
for commands. Original licenses and notices remain alongside the resources;
fixture/probe code is application-owned and separate from distributed engines.

## Host and locations

Linux embeds WebKitGTK 4.1 in the reference GTK overlay. Windows embeds a real
WebView2 child HWND using Microsoft's SDK 1.0.3537.50 and Evergreen runtime.
Flutter owns routing, controls, dialogs and state. Native surfaces report bounds,
selection, metadata, content locations, search results and acknowledgements over
BusyBooks-owned channels. A modal/route observer hides the child surface while
Flutter popups/dialogs are presented. Focus returns through explicit commands.
Both hosts forward launch requests to the existing instance of the same profile.
Linux uses GApplication command-line delivery; Windows uses a profile-specific
mutex/window property and bounded WM_COPYDATA delivery.
Linux's application-owned chrome channel retains a copy of the real GTK pointer
event for the public `gdk_window_show_window_menu()` operation. It does not call
or rewrite Yaru's window-menu implementation. This event-ownership boundary does
not resolve the separately documented intermittent Linux shutdown abort.

Reflowable EPUB locations use engine CFIs, never generated screen-page numbers.
The same CFIs are used for selections, highlights, jumps and reopen. Publisher
print-page references are labeled separately. Fixed-layout text uses CFIs when
text exists. `fixed_layout_integration.mjs` combines the renderer's public
`getContents()` results with separately retained document indices and upstream
Overlayer instances. It never replaces the renderer method. Single-page and
centered-page presentation use application-supplied book rendition metadata;
section order and CFI bases stay unchanged. Changes of spread/direction or the
active side use the public View lifecycle where the pinned renderer cannot
retain the new side through resize. Application-owned fixed-layout history
survives that lifecycle, and failed loads do not commit a new active location.
DOM Range selection and scrolling apply resolved original CFIs after navigation;
standard host CSS keeps overflowing artwork reachable in both directions.
`tools/fixed_layout_probe.mjs` exercises this composition with the actual
unmodified renderer and a controlled DOM. Native selection, overflow and layout
acceptance require the separate native probes.

`epub_integration.mjs` supplies Foliate's documented loader and an application-owned
book object. It adapts in-memory package metadata, document types and resource
references at those boundaries while retaining original itemref IDs, section
order and document structure. It does not copy or replace Foliate's implementation.
Sanitized section descriptors belong to the application; dependency methods and
prototypes are not mutated. Required-load errors are retained separately because
the pinned View can swallow navigation errors; cleanup failure cannot replace
the original opening error.

EPUB 2 inspection accepts an OPF 2 package and reuses NCX, nested navigation,
page lists, guide references and older metadata/cover handling. Image covers and
XHTML cover pages are distinguished. UTF-8 and UTF-16 XML use the same decoding
rules in inspection and rendering. Manifest fallback chains retain original
spine CFIs while mapping navigation/resource destinations to the supported
target; missing targets and cycles fail clearly. `dtbook.mjs` adapts EPUB-contained
DTBook to sanitized XHTML while preserving its element tree, IDs, links, notes,
images, stylesheet references and page markers. It does not open standalone DAISY.
EPUB-contained `text/x-oeb1-document`/`text/x-oeb1-css` aliases are normalized;
`fallback-style` XML islands retain their namespaces and IDs in a deterministic
XHTML shell using the manifest stylesheet. This same tree drives search and CFI
resolution. Normative fixture/schema checks and EPUBCheck profile exceptions
are documented in [fixture provenance](../../test/fixtures/formats/PROVENANCE.md#epub-2-validation).
Spine resolution continues through intermediate raster images to a content
document; embedded-resource resolution can still stop at those images. The
PDF → PNG → XHTML fixture checks original spine CFIs and navigation aliases.

FB2 inspection/preparation validates FictionBook's namespace and decodes UTF-8,
UTF-16 or Windows-1251. ZIP wrappers must contain exactly one eligible FB2 file;
recognized filesystem sidecars are excluded after archive integrity validation.
`fb2_book.dart` creates a bounded, sanitized, deterministic section tree once.
`prepared_book.mjs` uses that exact tree for rendering, search, selection,
narration and range resolution. The semantic format remains FB2. All emission
paths share a version-1 FB2 locator with the stable `body:N/part:N` identity,
section index and validated CFI. Footnote documents use the same structure and
loader, including embedded images, backlinks and restoration of note annotations.
Sections without source IDs receive deterministic, collision-free IDs in both
the canonical XHTML and contents tree. This adds attributes without changing
the element/text structure, so existing version-1 CFIs remain valid.
Validation follows the [CFI grammar](https://w3c.github.io/epub-specs/epub33/epubcfi/),
including valid empty/offset-only relative endpoints and virtual step 0, while
checking bounds, escaped assertions, required root paths and format/index identity.

CBZ and CBR share `comic_book.mjs` and Foliate's fixed-layout renderer. Only
archive decoding differs. ZIP streams entries to owned files; a bundled UnRAR
7.21 worker decodes RAR4/RAR5, including common solid archives. It is a separate,
killable process with bounded memory/output and no archive-controlled extraction
paths. License and unsupported profiles are described under
[RAR decoding](#rar-decoding). No external executable
is searched on PATH, and no decoder is downloaded at runtime.

Comic page identity is the SHA-256 of its original logical archive path, ordered
by numeric runs and Unicode scalar values with an exact-name tie breaker. Case
distinctions survive Windows caching. ComicInfo is optional; enumerated pages
determine the count. Static JPEG, PNG and WebP are supported. Bad/unsupported
pages fail rather than disappearing and renumbering saved annotations. Image
orientation defines intrinsic dimensions and normalized region geometry. The
reader explicitly revokes departed page Blob URLs, cancels pending loads and
retains at most two full pages after navigation (old/new spreads coexist while
loading). Thumbnail scheduling/cache bounds
remain shared; only bounded thumbnail previews cross the native channel.
Recognized filesystem metadata (`__MACOSX` paths, `._*` sidecars and `.DS_Store`)
is excluded before page ordering and ComicInfo index application. Archive path,
integrity and output-limit checks still cover those entries.

PDF stores page identity/reference and PDF-coordinate position/selection
geometry. Search maps original-text offsets across PDF text items back to
text-layer offsets. Resizing,
zoom and rotation regenerate viewports without changing saved geometry. The
annotation sidebar and Markdown export share a comparator using spine/CFI order
or PDF/comic page identity and text/region offsets. Actual rendered attachment, boundary selection and
native accessibility require execution, not round-trip storage tests.

## Publication search matching

`literal_search.mjs` owns the same literal, case-insensitive, non-overlapping
substring contract as BusyMark's Unicode source matcher. Regex-looking text is
escaped. Typed whitespace is preserved. Matching uses Unicode simple case
folding without locale-dependent conversion, accent removal or normalization;
precomposed and combining spellings remain distinct literal text. Supplementary
characters retain their original UTF-16 range boundaries. Case mappings such as
Greek final sigma and Kelvin sign follow the Unicode regular-expression engine;
full expansions such as sharp S to `ss` are not introduced.

EPUB/FB2 scan sanitized publication text nodes through Foliate's text walker,
`sections.createDocument`, `getCFI` and `getProgressOf` interfaces. Inline markup
does not split phrases, and original DOM ranges produce existing EPUB and FB2
locators. PDF uses the same matcher on logical text assembled from PDF.js text
items; an offset map removes synthetic end-of-line separators when selecting
text-layer ranges. Structured excerpts retain the exact original matched text.
Search never searches raw XML or moves the reading position.

A scan counts every occurrence while transferring only a bounded window of at
most 500 rows (200 by default). Requests carry reader/session and query revision
ownership; obsolete events are ignored. Occurrence navigation can request another
window without retaining all publication ranges. Progress, completion, cancellation
and failure remain distinct; a partial failed scan is incomplete. Search is
serialized to retain native cancellation ordering. Each dense page/chapter yields
periodically so a replacement or cancellation can interrupt it.

Text availability is a publication capability, separate from renderer readiness
and current-page text. PDFs always search all pages; blank or image-only pages
never disable searching a text body elsewhere. A wholly scanned PDF can finish
with zero occurrences. Comics have no Book Text capability. Native rendering,
actual selection alignment and Windows behavior require their own runtime checks;
`tools/literal_search_probe.mjs` tests the matching/protocol contracts under
controlled APIs.

## Shared typography capabilities

The active adapter reports behavior capabilities for font-family replacement and
text metrics after inspecting the opened layout. Shared preferences and controls
use those capabilities; loading/failed readers report none. Reflowable EPUB and
FB2 support typography. Fixed-layout EPUB, PDF and comics preserve original fonts.
Comic capabilities enable page navigation, thumbnails and region notes while
disabling publication text search, selection, dictionary and narration. Comic
view defaults are separate from PDF defaults; FB2 uses reflowable defaults.
Native discovery, accurate raster previews, private local FontFace aliases,
unavailable choices, persistence and reflow ownership are documented in
[typography.md](typography.md). Font application adds no publication-controlled
file endpoint or remote permission and changes no vendored implementation.

## Local resource boundary

The worker validates publication/archive metadata, integrity and resource limits before publishing
a disposable resource cache from the verified original. Original publication names remain in a manifest;
physical resource filenames are SHA-256 hashes of those names, preserving case
distinctions on Windows and avoiding encoded/reserved-path extraction. Foliate
receives its documented loadText/loadBlob/getSize loader. The cache retains
original paths and bytes; the supplied loader maps its own temporary URI aliases
to those exact resources and adapts package metadata and safe document text in
memory. Aliases never become book identities, saved destinations or archive
paths. DTBook/XML-island adaptation and fallback selection do not create stored
converted books. Cache data is regenerable and excluded from backups.

Books cannot silently fetch network data. Linux uses `busybooks://reader/` with
a local-only CSP; Windows intercepts every WebView2 resource request and serves
only the owned virtual origin. Book scripts, active embeds, forms, event-handler
attributes and script URLs are stripped before documents become blobs. CSP
blocks inline book scripts, remote fonts/images/styles, objects and form actions.
PDF JavaScript evaluation and XFA execution are disabled. External links use explicit Flutter confirmation and the normal external URL
launcher. Look Up uses explicit Flutter network consent and an application-owned
Wiktionary service; only the term and necessary API parameters leave the app.
Definitions are native selectable text in the owned popover. Open Full Entry is
a separate, deliberate external action. Neither workflow changes the publication
CSP or resource handlers. No cloud service participates in core reading.

Vendor file hashes are recorded in `tools/vendor-manifest.json`. Updating an
engine requires re-running native behavior, resource, license and packaging
checks; changing the manifest alone does not establish compatibility.

## Direct-file workspace integration

Preparation returns `path` (the original publication), `publicationPath` (the
renderer input) and `cacheDirectory` (the owned disposable resource directory).
Both native hosts receive this descriptor and a reader `session`. For PDF,
`publicationPath` names the verified, content-addressed `publication.pdf` snapshot
in the cache; `/publication` serves that snapshot, so replacing the original
pathname cannot change the open renderer's bytes. EPUB, FB2 and comic book-index
and resource requests serve the verified cache through the same endpoints.
The adapter reports its session with every event so a replaced surface
cannot attach positions to the next book. Obsolete native initialization futures
also cannot close or replace the active reader; WebView2 initialization is
serialized and close cancels a pending result. Reading data remains keyed by content
SHA-256; generated URLs and resource-cache locations never become identities.

The worker validates the original before every prepare, and cache preparation
checks the original bytes against the expected identity. A cache cannot replace
a missing original. File changes trigger fingerprint revalidation; missing or
changed originals hide the surface and preserve reading data for Locate/Retry.
Engine metadata is collected as part of normal direct reading.

## Reading workspace integration

See [reading-workspace.md](reading-workspace.md) for the shared header/sidebar,
owned Flutter popovers, selection action/result protocol and navigation model.
Content CSPs and resource handlers remain restricted. Footnotes are resolved
through Foliate's section/anchor API and sanitized before presentation; local
images use the existing publication loader, without adding a blob/network fetch
permission. PDF fits use each page's intrinsic geometry/rotation.

Reading, Notebook and Split share one book workspace, one reader session and one
Notebook editing state. Split allocates the reader on the left and Notebook on
the right using application-owned layout, with a constrained adjustable divider.
Standalone Notebook suspends its reader; Split retains an operational reader,
including when the approved narrow layout temporarily shows only one pane.
Native WebKitGTK/WebView2 bounds follow the actual visible reader pane after
sidebar allocation and display scaling. Visibility/focus intent is separate from
geometry, and native reveal requires a current book/session bounds acknowledgement.
Hidden reader panes cannot receive input or accessibility focus.

Publication focus notifications contain only a bounded session and trusted input
source, never a command or navigation destination. The controller confirms actual
native focus and its focus revision before accepting them, so delayed input cannot
take editing ownership from Notebook. Resizing updates selection geometry around
the same original source anchor without requesting another selection popover.
This uses supported engine APIs, application events and native-host composition;
no renderer method, prototype or dependency implementation is replaced.

PDF geometry relayout retains the active selection in application-owned logical
memory before rebuilding its text-layer DOM. Original UTF-16 endpoints, page
references, represented pages and direction are bound to the publication and
renderer session plus the current selection intent. Only those represented pages
are rendered and temporarily pinned for restoration; original text and endpoint
topology must still agree. A changed book/session, navigation, deliberate clear or
replacement, or failed layout abandons obsolete work. Restoration uses public DOM
selection APIs, updates only its presentation rectangle, and neither focuses the
reader nor reopens a selection popover. It preserves a multi-page range and its
direction where supported, without adding text from previously unloaded gaps.
Reading/Split transitions, divider/sidebar allocation and collapsed-pane recovery
use the same geometry path. Stored PDF-unit annotation segments, highlights and
navigation locations remain unchanged. Appearance changes deliberately retain
their existing selection policy rather than impersonating geometry-only work.

`test/fixtures/mixed-pages.pdf` adds eight deterministic pages with different
sizes, orientations and intrinsic rotation (4,593 bytes). Use it alongside
text.pdf and image-only.pdf for fit/zoom/rotation checks. Executable pure geometry
checks do not establish native text/canvas alignment. Native checks are described
in [development tools](../../tools/README.md).

## Selection search and online lookup

Search in This Book captures the complete selection, preserving literal
whitespace, and its book/session
before the protected popover handoff. It explicitly reveals the existing header
search and temporary Book Text sidebar session, synchronizes the editable field,
and starts an immediate search revision. It does not submit or navigate an existing result.
Selection in reflowable EPUB, text PDF and an EPUB footnote uses the same captured
passage. Results, cancellation, navigation history, Return, positions and
completion remain owned by the existing engines/controller.

Look Up from the selection and Dictionary from Book Actions use the same consent
and lookup path. Selection alone makes no request. The primary application makes
a bounded HTTPS request to English Wiktionary's
`GET /api/rest_v1/page/definition/{term}?redirect=false`; the whole word or phrase
is one URI-encoded path segment. Requests have a ten-second total deadline, a
one-MiB response limit, shape/MIME validation and bounded same-source redirects.
Obsolete requests are closed where possible and ignored by book, reader session,
presentation, term and request revision. Dismissal (including native outside
click/deactivation), replacement, book switch and hiding/leaving the reader invalidate the
lookup. Results update the existing presentation without reopening or focusing it.
Keyboard Escape/Close uses the existing focus return. Draft capture must succeed
before selection actions can replace or dismiss an editor.

The adapter consumes English Wiktionary's experimental `definition/0.8.1`
response: language keys map to lists of sections with `language`,
`partOfSpeech`, and `definitions[].definition` HTML fragments. The
[REST documentation](https://www.mediawiki.org/wiki/Wikimedia_REST_API) and
[OpenAPI description](https://en.wiktionary.org/api/rest_v1/?spec) describe the
service; unsupported response shapes receive explicit feedback.
Empty senses occur. The `en` key can include Translingual material; `other` can
include named languages. The UI uses actual section labels, never assumes the
book's language, and identifies English Wiktionary as the source.

The native preview strips HTML and decodes entities without executing content or
fetching fragment resources. It displays at most eight sections, two nonempty
senses per section and 700 Unicode characters per sense, with an explicit excerpt
notice. Definitions are in English; term languages and senses may differ from the
book. This is not automatic language detection. Established phrases with entries
are supported; arbitrary passages and unsupported entries can have no usable
definition. Selections above 256 Unicode characters or containing control
characters receive an explicit limitation message without being shortened or
sent. Missing, offline, timeout, unavailable and malformed/unsupported replies
have distinct messages; transient failures offer Retry. No browser opens as an
error fallback. Open Full Entry appears only when a source entry is known.
