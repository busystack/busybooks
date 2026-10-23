# Format expansion: profiles and verification

This record covers the 2026-10-23 implementation based on
`79af51228cd32e3b5669135a52e6120aa6498207`. Executed results are recorded in
[format-results.json](format-results.json). Local raw logs and screenshots live
under `evidence/formats-20261023/` (ignored build evidence). Fixture provenance
and byte hashes are in [test/fixtures/formats](../../test/fixtures/formats/PROVENANCE.md).

## Supported profile

| Input | Reader and persistent identity |
| --- | --- |
| PDF | Existing PDF.js 5.5.207; original bytes; existing page/text anchors |
| EPUB 2/3 | Pinned Foliate EPUB loader; original bytes; existing EPUB CFIs |
| `.fb2` | Genuine FictionBook XML/namespace; semantic `fb2`; original XML bytes |
| `.fb2.zip`, `.fbz` | Exactly one eligible FB2 document; semantic `fb2`; complete original ZIP bytes |
| `.cbz` | Image comic; complete original ZIP bytes |
| `.cbr` | Same comic reader; complete original RAR bytes |

Suffix recognition is case insensitive and checks compound `.fb2.zip` first.
An eligible suffix is followed by content validation. Generic ZIP/RAR/XML are not
accepted or registered. Linux's case-sensitive chooser receives bounded ordinary
suffix case variants. DRM-free `.kepub.epub` uses EPUB; standalone `.kepub`, Kobo
accounts and a separate renderer are excluded. No additional legacy, audio,
acquisition or conversion format is enabled. Protected content remains unsupported.

EPUB 2 tests use genuine OPF 2/NCX, nested contents, spine/internal destinations,
pageList references, guide, legacy metadata, image and XHTML-page covers, relative
images/styles/fonts and UTF-16 XML. The version-renamed EPUB 3 fixture was removed.
EPUB-contained DTBook uses a scoped sanitized adaptation retaining structure, IDs,
notes/backlinks/images/page markers. Manifest fallbacks retain original spine
CFIs and map destinations to the supported content. Missing targets and cycles
fail explicitly. EPUB 2's deprecated XHTML/CSS MIME aliases are normalized inside
the package. XML islands with `fallback-style` retain their original vocabulary,
namespaces and IDs inside a deterministic XHTML shell, shared by rendering,
search and CFIs; the referenced manifest CSS supplies their presentation.
XML entity declarations and external DTD fetching are not
enabled. Standalone DTBook/DAISY and audio are outside the input profile.

Seven EPUB 2 fixtures independently pass 39 OPF Relax NG, NCX/DTBook DTD and
content-schema checks using EPUBCheck 5.4.0's official schemas. EPUBCheck reports
no errors for five of these. The UTF-16 fixture records its UTF-8-only `HTM-058`
lint; the stylesheet-only XML fixture records `OPF-032`/`OPF-043`. These are
explicit checker-profile exceptions: [OPS 2.0.1 sections 1.4.1.2–4](https://idpf.org/epub/20/spec/OPS_2.0.1_draft.htm)
permit UTF-16 and [OPF 2.0.1 section 2.3.1.2](https://idpf.org/epub/20/spec/OPF_2.0.1_draft.htm)
permits `fallback-style` without `fallback`. Their actual XML trees still pass
independent schemas/DTDs and native rendering/restart. Expected warnings record
deprecated MIME types and a recommendation to use UTF-8. No unrelated errors
are suppressed. Two DRM-free Kobo-style fixtures exercise EPUB 2 and EPUB 3.

FB2 supports UTF-8, UTF-16 LE/BE and declared Windows-1251 with one inspection/
preparation decoder. Unsupported encodings fail intelligibly. Nested sections,
paragraphs, emphasis, poems, citations, tables, embedded images, internal links
and additional note bodies use one deterministic sanitized section tree for
rendering, search, selection and locators. Unusable optional images/covers do not
discard readable text. Edited metadata retains precedence.

FB2 locators are `{kind:fb2, version:1, section:body:N/part:N, index, cfi}`.
All emission paths share one constructor. Persistent validation accepts valid
empty/offset-only relative CFI endpoints and virtual step 0; native title-only
sections exposed the earlier rejection. Bounds, escaped assertions, required root
paths and format/index mismatches remain checked. Annotation ordering collapses
ranges against their common path rather than mixing start/end digits. See the
[CFI grammar and virtual-element requirements](https://w3c.github.io/epub-specs/epub33/epubcfi/).

Comics support static baseline/progressive JPEG, RGB/RGBA/grayscale PNG and
lossy/lossless WebP. Animated pages and other image encodings, including GIF, BMP,
TIFF, AVIF and SVG, are rejected without silently dropping or renumbering pages.
Corrupt headers reject preparation; later browser decode errors reject the page
operation while retaining identity/order. Opening requires a decoded, laid-out
initial page. Windows codec execution remains a gate.

Page ordering compares ASCII numeric runs by value, then lowercased Unicode
scalar values, then the exact name; it uses no OS/locale collation. Nested paths,
leading zeros and case-distinct Unicode names are fixtures. Optional validated
ComicInfo supplies title, creator roles, series, language, cover, RTL, wide-page
and bookmark information. Enumerated images determine page count. Intrinsic
orientation defines dimensions and normalized region coordinates.

Comic locators contain `{kind:comic, version:1, format:cbz|cbr, page, pageId}`.
`pageId` hashes the exact logical archive path. Optional `position:[x,y]` and
`region:[x,y,w,h]` use finite normalized oriented-image coordinates; regions must
have positive dimensions contained in one image. Page bookmarks deduplicate
independently of regions. Fonts, zoom, pixels and temporary URLs are not durable
identities. SQL schema 2 and logical backup schema 3 are unchanged.

## RAR backend and redistribution

The shipped backend is official **UnRAR 7.21**, statically linked into the
separate `busybooks_comic_archive` helper. Source:
[`unrarsrc-7.2.6.tar.gz`](https://www.rarlab.com/rar/unrarsrc-7.2.6.tar.gz), SHA-256
`d1afa67ef4121ebc5986815699e05db0ce8648499e5dca854f282a4c3f72c003`.
CMake checks/extracts the local unmodified archive and builds its RARDLL/UNRAR
object set. No external `unrar`, PATH lookup, shared RAR library, compressor or
runtime download is required. Probes use an explicit development override;
installed reading finds the sibling bundled helper.

Libarchive 3.8.10 was evaluated first: a RAR4 solid fixture failed, so it was not
selected or redistributed. UnRAR passes exact-byte RAR4/RAR5 stored, compressed
and solid extraction and sequential/distant backward/forward reader navigation.
CRC/data corruption, unsafe/duplicate paths, links, encrypted headers/data and
multipart inputs fail. RAR4 non-ASCII filenames without an unambiguous Unicode
field are rejected rather than guessed using an OS-specific OEM codepage. SFX,
other generations, dictionaries above 256 MiB, unsupported decoder features,
passwords and volume acquisition are outside the qualified profile. This does
not claim every feature of every RAR variant.

UnRAR's own license permits free RAR handling and redistribution inside other
software and prohibits recreating the proprietary compressor or developing a
RAR-compatible archiver. It is a separately licensed dependency. Complete terms,
the required paragraph and acknowledgements are retained in `native/vendor/unrar`,
the wrapper comments and installed `share/licenses/unrar`. BusyBooks' own code
remains Apache-2.0. See [NOTICE](../../NOTICE) and
[vendor provenance](../../native/vendor/unrar/README.md).

## Resource and ownership limits

| Resource | Limit / behavior |
| --- | --- |
| Original source | Comics 1 GiB; EPUB/PDF/FB2 retain 256 MiB |
| Comic archive | 20,000 entries; 64 MiB actual bytes per entry; 4 GiB aggregate output |
| Comic images | 1–10,000 pages; 16,000 pixels per side; 32 × 1024 × 1024 decoded pixels per image |
| Comic metadata | ComicInfo 1 MiB; aggregate logical names 4 MiB; bounded individual metadata strings |
| RAR process | 768 MiB memory; dictionary 256 MiB; three-minute deadline; cancel polling 25 ms |
| FB2 XML | 64 MiB; depth 128; 500,000 XML events/attributes; 256 attributes per element; 262,144 UTF-16 units per tag; 10,000 sections |
| FB2 binaries | 2,048 resources; 24 MiB encoded base64 per resource; 64 MiB encoded aggregate; bounded decoded dimensions/pixels |
| Prepared section / index | FB2 section 32 MiB; complete FB2/comic descriptor 16 MiB |
| Retained full comic pages | Two after navigation; old/new spreads coexist during a transition; obsolete image/document Blob URLs revoked; pending reads aborted on close |
| Thumbnails | Two tasks; window twelve; 240×320 preview; 32 previews / 8 MiB native cache |
| Existing EPUB ZIP | Original 256 MiB; entry 256 MiB; aggregate 1 GiB; 20,000 entries; not raised |
| Existing backup | 100,000 combined records; 128 MiB encoded manifest; unchanged |

ZIP comics use a file-backed index and stream stored/deflated chunks with actual
size/CRC checks. RAR callbacks stream to numeric owned staging filenames; archive
names never become output paths. Logical names map to hashed physical filenames,
preserving case distinctions on Windows. No full comic archive decompression
buffer is retained. Links, unsafe paths, duplicates, encryption and multipart
archives are rejected.

Opening validates/hashes the complete original before trusting a warm cache.
The stat-bound single-use inspection token avoids duplicate work only within
that owned sequence. Expected identity is checked before preparation. Versioned
`fb2-v1`/`comic-v1` caches publish complete staging before the index; interrupted
owned staging is cleaned on startup. Worker cancellation, native session IDs and
controller revisions reject replaced/late results. RAR cancellation kills an
active solid decoder while bytes are still being produced.
The native store's control channel also interrupts an active solid open; its
staging is removed and an existing private note remains intact. Failed replacement
inspection invalidates the previous disposable token, forcing fresh preparation
rather than reusing deleted staging.

Backup remains reading data only: collections/references, positions, notes,
annotations, settings and edited metadata. Original files, generated HTML,
extracted pages, thumbnails and caches stay excluded. Compressed FB2 export
reproduces exact original bytes with `.fb2.zip`/`.fbz`; Move/Locate and multiple
collection references retain shared SHA identity.

The 1 GiB cap was chosen after preparing a 290,794,372-byte stored CBZ with 42
deterministic 1280×1800 entropy PNG pages, exceeding the former 256 MiB limit.
The compiled probe used about 55 MiB peak RSS and 8.8 seconds for preparation;
exact final figures are in the JSON record. This is measured evidence, not a
claim about every maximum-size book. JIT/compiler memory is not release-runtime
memory.

## Executed Linux acceptance

Host: Ubuntu 24.04.5 x64, GTK 3.24.41, WebKitGTK 2.52.6, actual X11 desktop.
Flutter 3.47.5/Dart 3.13.4 and dependency versions remain pinned. Tests use copied
CC0 fixtures and disposable profiles. CI also runs the engine matrix through
Xvfb; that configuration alone is not interactive desktop acceptance.

`probe_linux_formats.sh` exercises real WebKitGTK against 22 publications:
OPF 2/UTF-16/DTBook/MIME aliases/styled XML/two KEPUBs, five FB2
representations/encodings, stored/deflated CBZ, the codec matrix, all six RAR
profiles and the 120-page comic. Twelve text cases
repeat after saving native ranges/annotations in the Dart store, deleting caches
and restarting at changed typography/window size. FB2/DTBook notes include images,
backlinks and annotation restoration. Every emitted anchor passes the persistent
Dart validator. Two further runs require missing/cyclic fallback rejection.
The final matrix reports 34 passing native proofs and 2,155 validated locators,
including the cache-deletion/restart phases.
Supplementary FB2/DTBook runs also persist annotations inside note bodies, delete
caches and restart at those exact note ranges. Selected text-assistance passages
are checked through the real renderer API. Returning from notes now synchronizes
the native selection even when the iframe's range is unchanged and the browser
emits no `selectionchange`; this prevents read-aloud from receiving page text
while a passage remains visibly selected. Native EPUB 3 typography/selection and
fixed-layout/PDF controls pass again after this correction.

Comic proof visits every page, jumps backward, changes zoom/spread/direction,
checks oriented dimensions, creates/adjusts/confirms/cancels regions by keyboard,
checks painting/hit testing/restoration, thumbnails, history and artwork colors.
Normal dragging pans zoomed artwork even when the drag starts over a saved region;
clicking or keyboard activation still opens that region's editor.
The long traversal samples at most two retained full pages after navigation.
RSS near page 10, page 60 and
the end decreases instead of growing per visited page. Final samples, navigation
timings and first usable page are in JSON. Text search is never fabricated for
comics or image PDFs.
The first-page engine clock begins after preparation; a separate cold 120-page
run records preparation and first-page clocks independently. Whole-application
opening timings are recorded by the bundle probe below. No maximum-size or
hardware-independent latency claim is made.

`probe_linux_opening.py` starts the actual release bundle, then forwards 16
relative paths from another working directory to the existing instance. All 17
openings require an `opened` timestamp and saved typed location in real SQLite.
It includes text/image PDFs and EPUB 3 reflowable/fixed layout. This exposed the
pinned GTK plugin consuming command-line events before BusyBooks' class handler;
BusyBooks now registers first and retains one input owner.

The rebuilt application also received actual keyboard/pointer input: CBR reading,
Go To, sidebar thumbnails, native view/annotation menus, page bookmarks/page
notes, region creation/editing, native editor focus, Escape, Notebook grouping/
Show in Reading, restart/cache deletion and Notebook with a missing original.
Private notes/geometry were checked in the disposable database. FB2 opened through
the real GTK chooser and its initial position was confirmed saved. Reproduced
large-region popover clipping and hidden-WebKit keyboard ownership were fixed:
the editor anchors to the visible region center, and hiding the reader returns
GTK focus to the main view without activating an inactive app. Notebook retains
a focus target for its commands. Comic text search is absent from the header,
menus and sidebar switcher; Notebook search remains available.

Storage/move/cache/order, reader logic/startup/sidebar/fixed-layout, typography,
dependency/localization/format/analysis, full Flutter and package results appear
separately in JSON. Protected failed-save/retry/deletion/stale-session region
workflows use controlled store/channel tests; no live desktop disk failure is
claimed. Existing native typography and pointer-routing probes were rerun. No
publication CSP or network permission was expanded.

## Remaining release gates

**Windows WebView2:** no Windows desktop/VM, MSVC host or WebView2 runtime was
available. Runner/helper/CMake/installer changes have not been compiled or run
here. Run Windows CI, then install the offline package on Windows 10/11 and check
every new format/codec, RAR4/5 profiles/cancellation/distant jumps, page/region
notes/restoration, text selection/footnotes, native menus/popovers, keyboard/focus,
100/125/150% DPI, associations/drops/forwarding, missing/changed originals,
Move/Locate, exact original export, backup/restore and offline operation. Verify
the helper and complete licenses in the installed package. Linux/Chromium results
do not establish this gate.

**Installed strict Snap:** snapd and GNOME/core24 bases are present, but
Snapcraft/LXD/Multipass tooling and an installed BusyBooks Snap were unavailable.
The strict recipe/complete CMake bundle include the helper and licenses without
a new interface or runtime download. An installed strict-Snap build/run has not
been demonstrated. Build the actual recipe, install its local artifact, check
interfaces and run format/note/cancellation/file-opening checks in Home and
permitted removable-media paths. Verify packaged WebKit/SQLite/speech/decoder
resources offline. Portable bundle success does not establish confinement or
installed-Snap behavior. No Snap was published or confinement relaxed.

These two gates remain explicitly unverified. No push, merge, publication or
production-profile testing was performed.
