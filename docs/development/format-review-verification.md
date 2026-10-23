# Format review corrections

This follow-up starts from clean `feature/book-formats` commit `852bd74` and
addresses the five reproduced defects. The original format implementation and
package records remain in [format-verification.md](format-verification.md).
Current machine-readable results are in
[format-review-results.json](format-review-results.json). Raw execution logs are
retained locally under `evidence/formats-review-20261023/` (ignored evidence).
All publication/profile work uses generated CC0 fixtures and disposable profiles.
The implementation and regression harnesses are committed locally as `90347f6`.

## Corrected behavior

1. Fixed-layout pages use auto margins to center a fitting page or spread. When
   artwork exceeds the viewport, those margins become zero, preserving the
   reachable starting edge. The container uses physical left-to-right geometry;
   reading direction still controls the renderer's spread/page order. Numeric
   zoom no longer puts the left edge outside the scrollable area.
2. EPUB spine fallback resolution requires a content document, continuing
   through intermediate raster resources. Embedded-resource resolution can
   still use those images. Original spine itemrefs, CFI prefixes and all fallback
   navigation aliases remain attached to the selected XHTML. This follows the
   PDF → PNG → XHTML example in [OPF 2.0.1 section 2.4](https://idpf.org/epub/20/spec/OPF_2.0_latest.htm#Section2.4).
3. FB2 sections without IDs receive deterministic IDs shared by the canonical
   XHTML and contents entries. All authored IDs are reserved first, including
   later IDs, and collisions receive deterministic suffixes. Only attributes
   change: section boundaries, element order and text nodes remain unchanged,
   preserving version-1 locations without the new ID assertions.
4. Comic discovery excludes `__MACOSX` path components, `._*` basenames and
   `.DS_Store` before image classification, ordering, counting and ComicInfo
   index application. These entries still undergo archive path, duplicate,
   output-limit and integrity validation. The same handling serves CBZ and CBR.
5. Comic locators accept only `kind`, `version`, `format`, `page`, `pageId`,
   `position` and `region`. Incompatible or unknown fields reject restore before
   writes. Comic annotation comparison always finishes within the comic branch,
   so stray PDF fields in formerly accepted records cannot break sorting or
   Markdown export.

`fb2-v2` and `comic-v2` disposable cache directories regenerate older prepared
contents/page lists. Descriptor and locator versions remain 1. Startup cleans
interrupted staging in both cache generations. Original validation and SHA-256
verification still precede preparation, including warm-cache opens. No SQL
migration, replacement publication, dependency update or additional format was
introduced. Foliate stays at `78914aef4466eb960965702401634c2cb348e9b1`;
only its already-patched `epub.js` and `fixed-layout.js` change, with updated
hashes in `tools/vendor-manifest.json`. PDF.js is unchanged. The bundled RAR
backend remains UnRAR 7.21 with its existing redistribution notices and limits.

## Regression evidence

The focused Flutter regressions exercise cache regeneration with an existing FB2
CFI, collision-free unnamed chapters, sidecars with ComicInfo and corrupt CRC,
comic field validation, and the real SQLite backup/restore path. The restore test
contains two regions at the same location and `point: []` on one. Restore rejects
the complete incoming backup; existing PDF notes survive reopening. A valid
restore exports both notes. A directly seeded record simulating the old version
also sorts and exports successfully.

`tools/format_review_native_proof.js` runs against the actual reader assets and
unchanged CSP in both Chromium and Linux WebKitGTK. Comic cases cover CBZ and
solid RAR5 CBR, LTR/RTL, single/spread, numeric zoom 50%, 150% and 300%, first,
last, wide, oriented and mixed-size pages, all four corner regions, and viewport
resizing. Each comic phase performs 336 region navigations across every fixture
page and asserts the actual region rectangle lies in the usable viewport. It
also verifies fitting-page centering.
For the reported 600 × 900 artwork at 300% in an 800-pixel viewport, the page is
1,800 pixels wide and its starting edge is 0, in both directions. Chromium's
non-overlay scrollbar leaves 785 usable pixels; WebKitGTK leaves 800.

The EPUB case distinguishes spine and embedded-resource endpoints, exercises
PDF/PNG/XHTML navigation aliases, decodes the embedded image, retains original
CFI prefix `/6/4` and resolves publisher page 17. The FB2 case navigates all three
distinct chapter destinations and saves three distinct typed outline CFIs. It
also resolves a legacy CFI without generated ID assertions at two font sizes.
The two text cases restore the exact selected passage after cache regeneration.

The Linux script repeats all four publications after saving renderer-produced
locations and annotations to the real database, closing the store, deleting
caches, reopening SQLite and revalidating the original. Restored comic region
notes must paint and remain visible at 300% RTL spread; restored FB2 outline
entries must resolve to the same distinct chapters. Private note text is removed
from the annotation projection sent to the renderer. Every emitted location is
checked by the production Dart validator.

The new fallback fixture independently passes EPUBCheck 5.4.0 and EPUB 2 schemas
with no errors or warnings. Across eight fixtures, 44 independent schema/DTD
checks pass. The pre-existing UTF-16 HTML lint and stylesheet-only XML profile
exceptions remain precisely scoped as recorded in the original verification;
the new fixture adds no exception. Fixture provenance and byte hashes are in
[PROVENANCE.md](../../test/fixtures/formats/PROVENANCE.md) and `SHA256SUMS`.

## Executed checks

Host: Ubuntu 24.04.5 x64, GTK 3.24.41, WebKitGTK 2.52.6, actual X11 desktop;
Chromium uses the installed Google Chrome and Node 24.15.0. Flutter 3.47.5 and
Dart 3.13.4, the lockfile and dependency versions remain unchanged.

| Check | Result |
| --- | --- |
| Enforced offline dependency resolution; localization generation | Passed |
| Dart formatting (133 files); Flutter analysis | Unchanged formatting; no issues |
| Full Flutter suite | 349 passed; one existing opt-in live Wiktionary test skipped |
| Five focused storage/preparation/restore regressions | Passed |
| EPUB 2 independent conformance | Eight fixtures; 44 schema/DTD checks |
| Chromium actual reader review | Four proofs; 672 comic corner-region navigations |
| WebKitGTK actual reader review and real-store/cache restart | Eight proofs; 1,344 comic corner-region navigations; 1,613 validated locators |
| Existing Linux engine smoke matrix | 20 publications; text and image capability checks passed |
| Existing native typography controls | Seven WebKitGTK proofs and one Chromium raster proof passed |
| Storage, cache, ordering and cross-volume Move probes | Passed (88 storage checks; 64 Move checks) |
| Format contract/resource probes | 153 format checks; cancellation and retained-note checks passed |
| Reader logic, startup, fixed-layout, sidebar and comic interaction probes | Passed |
| Fixture hashes and pinned vendor hashes | All fixture hashes and 218 vendor hashes match |
| Pinned Linux release build | Passed |

The new review probes run in Linux CI alongside the existing native suites.
Chromium execution is conditional on the runner's installed Chrome. These are
local results; no CI run, push, merge or publication was performed.

## Rebuilt Linux package

`build/distributions/busybooks-0.1.0-linux-x64-formats-review.tar.gz` is the new
portable artifact. Its SHA-256 is
`2d8d6eee084dbfd4d9ec9b8a262c788eccb9ad6074b9474e19a137029186ff22`.
The previous artifact and its historical checksum record are preserved.

After extraction to an unrelated disposable directory, all 224 reader assets
match the current sources, the RAR helper is executable with its full license,
and neither executable has unresolved runtime libraries on this host. The
extracted decoder passes all 16 RAR qualification checks; the extracted MIME
database recognizes eligible suffixes without claiming ordinary ZIP/RAR.

The actual extracted application opens all 19 fixture publications in one
primary process, including the two new regression fixtures, EPUB 3 reflowable/
fixed layout, text/image PDF, compressed FB2 and both RAR generations. Each
opening requires a renderer-opened timestamp and saved typed location in real
SQLite. Eighteen relative-path launches forward from another working directory;
complete original bytes remain unchanged. This establishes Linux bundle
execution on this host, with the platform limits below.

## Remaining platform gates

Windows WebView2 interaction, installed runtime/codecs, focus/popovers and
packaged file opening still require an actual Windows host. No Windows host,
MSVC or WebView2 runtime is available here. Chromium results do not establish
WebView2 acceptance.

An installed strict-Snap run still requires snapcraft and an available strict
Snap build/install environment. BusyBooks is not installed as a strict Snap on
this host; snapcraft, LXD and multipass are unavailable. The Linux bundle and
source confinement configuration do not establish that acceptance. These two
gates remain open separately from the five corrected defects.
