# Reader implementation and proof boundary

EPUB uses [Foliate.js](https://github.com/johnfactotum/foliate-js) pinned to
`78914aef4466eb960965702401634c2cb348e9b1` (MIT). Its EPUB loader,
reflow paginator, fixed-layout renderer, CFI resolver, text walker, search and
overlayer are used directly. The upstream project documents both renderer
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

These are existing rendering implementations, not a new parser/layout engine.
Their browser interfaces permit both native hosts. Linux CI run
[39312939311](https://github.com/albert-gee/busybooks/actions/runs/39312939311)
at `fd1aa90a1aa6a3a4e6138b344f40a8f3451790ad` executed three real WebKitGTK
surfaces under Xvfb: reflowable EPUB, fixed-layout EPUB and text PDF each reported
`opened=1 location=1 search=1`. This is smoke evidence only. It does not establish
selection, rendered annotation attachment, accessibility, image-only PDF or the
full application workflows. Windows tests failed before compilation in that
run; WebView2 execution remains unverified. Current Linux format acceptance and
the exact remaining Windows/Snap gates are recorded in
[format-verification.md](format-verification.md).

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

Reflowable EPUB locations use engine CFIs, never generated screen-page numbers.
The same CFIs are used for selections, highlights, jumps and reopen. Publisher
print-page references are labeled separately. Fixed-layout text uses CFIs when
text exists. The adapter supplies upstream Overlayer instances and content
indices missing from Foliate's fixed-layout `getContents()` result. Local
renderer corrections let a requested single-page view override a publisher spread,
retain the active side on same-spread jumps, and honor resolved text ranges for
selection, scroll and resume at zoom. `tools/fixed_layout_probe.mjs` exercises
these navigation paths against the actual renderer with a controlled DOM; it
does not establish native selection or layout acceptance.
The two modified vendor files are `epub.js` (manifest fallbacks, DTBook, EPUB 2
MIME aliases and styled XML islands) and `fixed-layout.js` (these existing fixes, safe failed navigation and
direction rebuilding). All other Foliate files remain at the recorded revision.

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
are documented in [format-verification.md](format-verification.md).

FB2 inspection/preparation validates FictionBook's namespace and decodes UTF-8,
UTF-16 or Windows-1251. ZIP wrappers must contain exactly one eligible FB2 file.
`fb2_book.dart` creates a bounded, sanitized, deterministic section tree once.
`prepared_book.mjs` uses that exact tree for rendering, search, selection,
narration and range resolution. The semantic format remains FB2. All emission
paths share a version-1 FB2 locator with the stable `body:N/part:N` identity,
section index and validated CFI. Footnote documents use the same structure and
loader, including embedded images, backlinks and restoration of note annotations.

CBZ and CBR share `comic_book.mjs` and Foliate's fixed-layout renderer. Only
archive decoding differs. ZIP streams entries to owned files; a bundled UnRAR
7.21 worker decodes RAR4/RAR5, including common solid archives. It is a separate,
killable process with bounded memory/output and no archive-controlled extraction
paths. License, unsupported profiles, measured limits and cancellation evidence
are in [format-verification.md](format-verification.md). No external executable
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

PDF stores page identity/reference and PDF-coordinate position/selection
geometry. Search maps normalized excerpts back to text-layer offsets. Resizing,
zoom and rotation regenerate viewports without changing saved geometry. The
annotation sidebar and Markdown export share a comparator using spine/CFI order
or PDF/comic page identity and text/region offsets. Actual rendered attachment, boundary selection and
native accessibility require execution, not round-trip storage tests.

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
receives its documented loadText/loadBlob/getSize loader, with original paths
and bytes. This is not publication conversion. Cache data is regenerable and is
excluded from backups.

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

Both native hosts receive `path` (the original publication), `cacheDirectory`
(the owned disposable publication resource directory) and a reader `session`. They no
longer derive cache locations from a private book-copy directory. `/publication`
serves the original PDF; EPUB book-index/resource requests serve the verified
cache. FB2/comic book-index and resource requests use these same endpoints. The adapter reports its session with every event so a replaced surface
cannot attach positions to the next book. Obsolete native initialization futures
also cannot close or replace the active reader; WebView2 initialization is
serialized and close cancels a pending result. Reading data remains keyed by content
SHA-256; generated URLs and resource-cache locations never become identities.

The worker validates the original before every prepare, and cache preparation
checks the original bytes against the expected identity. A cache cannot replace
a missing original. File changes trigger fingerprint revalidation; missing or
changed originals hide the surface and preserve reading data for Locate/Retry.
The old metadata-only import-validation path has been removed. Engine metadata
is collected as part of normal direct reading.

## Reading workspace integration

See [reading-workspace.md](reading-workspace.md) for the shared header/sidebar,
owned Flutter popovers, selection action/result protocol and navigation model.
Content CSPs and resource handlers remain restricted. Footnotes are resolved
through Foliate's section/anchor API and sanitized before presentation; local
images use the existing publication loader, without adding a blob/network fetch
permission. PDF fits use each page's intrinsic geometry/rotation.

`test/fixtures/mixed-pages.pdf` adds eight deterministic pages with different
sizes, orientations and intrinsic rotation (4,593 bytes). Use it alongside
text.pdf and image-only.pdf for fit/zoom/rotation checks. Executable pure geometry
checks do not establish native text/canvas alignment. Native acceptance remains
listed separately in [format-verification.md](format-verification.md).

## Selection search and online lookup

Search in This Book captures the complete trimmed selection and its book/session
before the protected popover handoff. It explicitly reveals the existing header
search and Search Results sidebar, synchronizes the editable field, and starts an
immediate search revision. It does not submit or navigate an existing result.
Selection in reflowable EPUB, text PDF and an EPUB footnote uses the same captured
passage. Results, cancellation, navigation history, Return, positions and
completion remain owned by the existing engines/controller.

Look Up from the selection and Dictionary from Main Menu use the same consent
and lookup path. Selection alone makes no request. The primary application makes
a bounded HTTPS request to English Wiktionary's
`GET /api/rest_v1/page/definition/{term}?redirect=false`; the whole word or phrase
is one URI-encoded path segment. Requests have a ten-second total deadline, a
one-MiB response limit, shape/MIME validation and bounded same-source redirects.
Obsolete requests are closed where possible and ignored by book, reader session,
presentation, term and request revision. Dismissal (including native outside
click/deactivation), replacement, book switch and leaving Reading invalidate the
lookup. Results update the existing presentation without reopening or focusing it.
Keyboard Escape/Close uses the existing focus return. Draft capture must succeed
before selection actions can replace or dismiss an editor.

The [official REST documentation](https://www.mediawiki.org/wiki/Wikimedia_REST_API)
links the experimental definition endpoint on English Wiktionary. Its
[live OpenAPI description](https://en.wiktionary.org/api/rest_v1/?spec) currently
contains an older `usages` schema. Public requests on 2026-10-22 verified the
actual `definition/0.8.1` JSON: language keys map to lists of sections with
`language`, `partOfSpeech`, and `definitions[].definition` HTML fragments.
`cat`, `café`, and `ice cream` succeeded; a fabricated missing term returned 404.
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
