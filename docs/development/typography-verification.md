# Local font selection verification

This document retains the typography work's historical results. The later
format expansion changes two pinned Foliate files without changing its revision;
its fresh native typography regressions and current vendor hashes are recorded
in [format verification](format-verification.md) and `tools/vendor-manifest.json`.

This change started at `96b7a14` on a clean `feat/busybooks` worktree. Repository
instructions and the existing preferences, storage, reader, popover and backup
paths were read before editing. No applicable AGENTS.md was present. Verification
uses official Flutter **3.47.5**, bundled Dart **3.13.4** and the existing lockfile.
The 214 vendored-file hashes match `tools/vendor-manifest.json`; no vendored
engine, Dart dependency, SDK or reference application was changed.

The original family-selection checks below did not cover three Priority B review
defects. The [review corrections](#priority-b-review-corrections) supersede the
original weight, specialist-capture and cancellation conclusions.

## Findings and implementation boundaries

The existing callback-driven `ReadingAppearanceControls` already serves Settings
and the native reader popover. Persistence belongs to the primary controllers,
not those controls. The old font allowlist admitted only generic categories and
Noto Serif/Sans; settings, book records and backup validation needed the same
extension. That existing path now carries tagged literal family identities.
The popover has its own Flutter engine: both engines register the font channel,
with a process-owned native catalogue rather than an assumed shared provider.

The opened renderer supplies separate font-replacement and text-metric
capabilities. Tests exercise those capabilities independently of format names.
Fixed layout, PDF, loading and failed readers reject unsupported font paths.
Settings offers shared reflowable defaults without an open book and retains its
separate PDF defaults. [typography.md](typography.md) describes the contract.

Native investigation corrected two resolution assumptions. Pango description
syntax treats commas as family separators; a private Fontconfig string
substitution preserves literal punctuation. WebKitGTK's FreeType local-face
lookup needs family identity and actual weight/style before full/PostScript
alternatives. Registering a missing bold/italic face as though it existed would
suppress browser synthesis; actual native face metadata now prevents that.
Private aliases isolate an installed family from embedded publication fonts.

Related regressions uncovered during the workflow were also corrected: restoring
a section-only CFI must not construct a nonexistent text range; renderer
navigation during reflow must retain an existing selection; native GTK Escape
must return from the chooser to Appearance; and an empty, committed IME range
must permit keyboard activation. Async catalogue updates retain the actual Close
action, extending the existing lookup focus fix. No vendor patch was necessary.

## Automated checks

The final complete Flutter run passed **329 tests**, with **one skipped** opt-in
live Wiktionary contract test. All deterministic dictionary, selected-text
search, popover action/focus, annotations/protected drafts, navigation, preferences,
storage and backup cases ran. Formatting checked 121 Dart files with no changes;
static analysis reported no issues. Offline lockfile enforcement and localization
generation passed for both existing locales, English and German.

New deterministic coverage includes Unicode/punctuation/literal-generic
identities, invalid and unavailable saved names, SQLite restart and backup
restore, availability refresh, aliases and distinct family identities, coalesced
requests, stale replies, failure/retry, 10,000-family lazy lists, IME editing,
keyboard activation/cancellation, selected semantics, delayed Close activation,
bounded scaled layouts, late previews, publisher/default/reset behavior, renderer
and storage failures, A→B→C ordering, navigation and book/view/shutdown ownership.

The complete Node reader probe passes, including the existing startup, PDF
selection, outline/navigation and sidebar probes and the new typography data,
CSS escaping, independent capability and ownership checks. Broader real-storage
probes passed: 88 storage checks, 64 cross-filesystem move/recovery checks, four
cache resources and five annotation-order checks. These supplement rather than
replace native rendering checks.

## Actual Linux rendering and interface

Host: Ubuntu 24.04.5, GTK 3.24.41, Pango 1.52.1, WebKitGTK 2.52.6, X11.
`bash tools/probe_linux_typography.sh` passed all three publication runs. Its
temporary Fontconfig collection contains existing licensed Noto Serif and
Liberation Sans resources plus a renamed Noto derivative,
`BusyBooks "Ä", \ Serif`. Notices accompany those disposable resources; no new
font binary enters the repository or release bundle.

The production Pango backend enumerated three families, resolved twelve requested
face variants and produced distinct native PNG samples. In actual Foliate
iframes, private `FontFace.load()` calls succeeded. Canvas glyph rasters differed
between Noto Serif and Liberation Sans; the sample's measured widths were
344.03894 and 322.88672 pixels. The renamed derivative matched its Noto source.
The probe draws in the publication's document, so its font set participates in
the measurement. Neither a stored string, a computed family property nor
`document.fonts.check()` is accepted as proof of resolution.

Native assertions cover regular/bold/italic raster differences, heading hierarchy,
code exclusion, multilingual/directional chapter transitions, footnotes,
publisher-important rules and an embedded serif font claiming the installed
Liberation Sans name. Publisher restoration returns the original raster. Durable
CFIs remain displayed, history gains no typography entries, and highlight hit
testing, text selection, search and read-aloud underlines retain their anchors.
Rapid selections, navigation during reflow and publisher restoration during an
update pass. Fixed-layout EPUB preserves authored typography; PDF preserves page
and text-layer content. Both reject font replacement. The existing native engine
probe also passes opening/location/search for reflowable EPUB, fixed EPUB and PDF.
The GTK input-routing probe passes Welcome/chrome/book/resize/modal/teardown.
Its test now counts physical presses once, ignoring GTK's additional double/triple
notifications, so desktop click intervals do not alter its counters.

The built application was exercised with disposable reading profiles and fixture
books. Screenshots of the real GTK/Flutter interface were inspected in light and
dark themes, at the 640×560 minimum window, at 2× display scaling, and at 1.5×
text scaling. The text-scale run used a private session bus and keyfile settings;
the desktop portal returned 1.5 without changing the user's desktop preferences.
The chooser stays bounded and scrollable, with Close/search available. Family
labels keep the interface font; native samples show the candidate.

In both the reader's transient engine and Settings' primary engine, search and
preview worked. Browsing did not write a book appearance; keyboard activation
applied a named family and returned to Appearance. Escape returned focus to Font
Family; Enter reopened it. Liberation Sans survived a clean restart; selecting
Noto Serif retained unrelated appearance values. Publisher mode restored the
publication and kept Noto remembered. Explicit Save as Reading Defaults carried
that choice to Settings while the existing PDF defaults remained separate.

On the isolated accessibility bus, AT-SPI exposed Close/Refresh actions, the
focused Search fonts field, the sample description, and named/generic rows.
The Noto Serif row reported SELECTED and included Current selection; neighboring
rows were unselected. Widget semantics also verify names, selected states and
activation actions. An end-to-end Orca speech session was not performed.

Local, ignored evidence is in `evidence/named-fonts/`, including
`flutter-suite-accepted.log`, `native-typography-complete.log`,
`native-engines-complete.log`, `native-input-complete.log`, native AT-SPI JSON,
`ui-named-preview-dark.png`, `ui-keyboard-applied-light.png`,
`ui-publisher-restored-light.png`, `ui-restart-light.png`,
`ui-settings-chooser-light.png`, `ui-narrow-settings-chooser.png`,
`ui-scale2-chooser.png` and `ui-text15-selected.png`.

## Packaging and remaining platform checks

The Linux release is built with the pinned SDK. Local packaging uses the existing
reproducible tar/gzip procedure and a SHA-256 sidecar; it is not installed,
published or pushed. The bundle includes the adapter module and existing font
resources, without deterministic test fonts, native preview PNGs or fixture books.
Package inspection checked 267 files and 15 existing font resources; the adapter
copies match source and all native shared-library dependencies resolve. Artifact:
`build/distributions/busybooks-0.1.0-linux-x64.tar.gz`, SHA-256
`d46f6034bd93c4bbae2f93988a5a7ceb470c8c635ef356a059549f3737072a06`.

Windows has a real DirectWrite local-only collection implementation and
DirectWrite/Direct2D/WIC samples, including worker/COM disposal and channels on
both engines. A native stock-family probe and its build/run steps are included in
Windows CI. They were **not executed here**. This Linux host rejects
`flutter build windows`; MSVC/Windows SDK compilation, native backend execution,
WebView2 glyph resolution/collisions, chooser runtime, UI Automation and Windows
DPI/focus remain unverified. Linux results do not establish Windows acceptance.

`snap list busybooks` reports no installed BusyBooks Snap. Strict-Snap runtime,
its accessible font catalogue and native chooser are therefore unverified. No
Snap was installed and confinement was not changed. The existing Snap definition
is unchanged; discovery sees only families accessible inside the running
environment. No claim is made about fonts outside that confinement.

## Priority B review corrections

The review starts at `b5899e8` on a clean tree. Independent reproduction found:

- Production registration in Chromium exposed only two distinct rasters for the
  five existing weight choices. Direct installed-family rendering differed at
  each weight; 300/500/600 also failed to match their direct native references.
- The actual Foliate section-loading order captured the replacement family for
  a normal-priority specialist span in a newly navigated chapter. The earlier
  fixture's publisher-important rules masked this ordering defect.
- A delayed font load followed by cancellation retained the candidate's glyphs
  and emitted a successful acknowledgement. The existing controller test only
  checked that its book write had been cancelled.

Both native resolvers now retain actual OpenType weights and normal/italic face
identities across CSS 100–900 matches. Full/PostScript identities precede WebKit's
family fallback. An isolated family with ten generated normal/italic faces tests
all five existing controls against direct installed-family glyphs. The derived
faces use distinct existing licensed Noto/Liberation outlines and explicit weight
metadata; they are deterministic test resources, not a production font bundle.
Original notices accompany them. No developer-installed Lato is required.
Chromium now reports **five distinct rasters**, with normal and italic references
matching for 300, 400, 500, 600 and 700. WebKitGTK passes the same comparisons;
native preview PNGs also differ for all five weights. The shared preview forwards
and refreshes its body weight. Missing faces remain missing and emphasis can be
synthesized rather than mislabeled.

Foliate's pre-load stylesheet now contains only metrics/colors; family replacement
uses the controlled properties after specialist capture. Separate native runs
pass new-chapter and genuine cold-open saved-customization cases, subsequent
family changes and publisher restoration. No vendored file changed.

Font preparation retains active faces until activation. Cancellation restores the
settled appearance and returns a cancelled result. The controller re-reads its
committed appearance after the pending write settles, waits for renderer
reconciliation and then reveals the retained reader. SQLite-backed controller
tests check A/B hide/return, late results, a newer C choice and failed-return
retry without a spurious book override. Complementary actual WebKitGTK tests use
the committed preference read back from SQLite and compare body/footnote glyphs,
the logical CFI and navigation history. They delay font loading and post-style
layout separately, navigate during cancellation, and complete rollback after a
newer selection has succeeded. Old work cannot replace that selection.

The complete corrected Flutter suite passes **334 tests**, with the same one
optional live Wiktionary test skipped. Formatting and analysis pass. The complete
Node reader probes and seven native typography runs pass, including ordinary
reading/selection/annotations/search/narration/footnotes and unchanged fixed/PDF
font rejection. Chromium uses a disposable headless browser profile and the same
native resolution JSON/production registration. Linux release/native smoke
results are recorded with the local evidence under
`evidence/typography-corrections/`; no temporary pub-cache paths are left in the
project's package configuration. Flutter 3.47.5, Dart 3.13.4, lockfile and vendored
hashes are unchanged. Windows compilation/runtime and installed strict-Snap
acceptance remain unverified on this Linux host; Chromium does not establish
WebView2 or UI Automation acceptance.

The corrected GTK release was also exercised interactively with the isolated test
collection and a disposable profile. The named-family sample, explicit activation
and existing Light/Regular/Medium/Semibold/Bold menu worked. Selecting Medium
changed the body glyphs while the specialist span retained its authored family;
SQLite held the selected family, weight 500 and publisher=false. Screenshots were
inspected (`ui-weight-preview.png`, `ui-weight-menu.png`,
`ui-medium-applied.png`), and shutdown completed successfully. The existing native
engine opening/location/search and GTK input-routing probes also pass.

The rebuilt Linux archive excludes test fonts/publications and its adapter
copies match source. The current local artifact is
`build/distributions/busybooks-0.1.0-linux-x64.tar.gz`, SHA-256
`9b29bdb4f02b4702a5a8bff6efc4f56bcf46aea6c68a0391fc086f6c72d564ff`.
The earlier archive hash above describes the original implementation.
