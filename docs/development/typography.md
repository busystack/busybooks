# Shared reading typography and local fonts

Reflowable EPUB 2/3 and FB2 use these same preferences, local-font controls and
durable reflow/selection safeguards. FB2's deterministic prepared tree is shared
by rendering, search and CFI resolution. Comics report no typography capability
and retain artwork colors; their zoom/spread/direction defaults are separate from
PDF defaults. See [format verification](format-verification.md) for the format
matrix, cache-deletion/restart attachment checks and remaining platform gates.

Font preferences belong to the reading system. `FontChoice` and
`TypographyCapabilities` in `lib/src/core/typography.dart` contain no format or
engine names. The existing appearance map, settings writer, book records and
backup validators remain the serialization boundaries. Generic choices retain
the strings `serif`, `sans-serif` and `monospace`; literal families use
`{"family":"…"}`. Existing named strings, including Noto Serif/Sans, normalize to
that representation. A literal family named “serif” remains distinct from the
generic category. Names retain Unicode and punctuation, are limited to 256
UTF-16 units and reject controls, malformed surrogates and surrounding whitespace.
No installed-font allowlist participates in storage or restore.

The actual adapter reports font-family replacement and text-metric capabilities.
Foliate's opened publication/layout determines those capabilities: reflowable
content supports customization; fixed layout and the PDF renderer report none.
The controller exposes no typography capabilities before readiness or after a
fatal error/suspension. Both controller and adapter reject unsupported updates.
Appearance consumes these capabilities, rather than deriving reflowability from
`!fixed` or a filename. Settings offers shared Reflowable Reading Defaults and
its existing separate PDF defaults without an open publication. No future-format
entries or renderer plugin framework are introduced.

## Discovery, resolution and preview

`ReadingFontService` separates catalogue, resolution and preview requests. Native
channels are registered on **both** Flutter engines. Dart containers/caches are
not assumed to be shared; the native catalogue is process-owned, cached for one
minute and serialized/coalesced across engines. Dart also coalesces concurrent
loads. Refresh explicitly rebuilds the catalogue; stale replies cannot replace a
newer result. Discovery failure, no matching search results and an unavailable
saved family have different presentation states. Generic categories remain
usable during catalogue failure. Rows are lazy; opening the chooser does not
load every font file or create a book override.

Linux uses private worker-owned PangoCairo font maps and
[Pango family enumeration](https://docs.gtk.org/Pango/method.FontMap.list_families.html).
PangoFc/Fontconfig validate the actual matched family and provide local family,
full-face and PostScript identities. The array returned by enumeration is freed;
font maps, contexts, fonts, layouts and Cairo resources have scoped ownership.
The implementation uses APIs available since Pango 1.48 (the verified host has
1.52.1). A private
[Fontconfig substitution callback](https://docs.gtk.org/PangoFc/method.FontMap.set_default_substitute.html)
passes literal family strings without Pango's comma-separated description syntax.
It changes neither global Fontconfig configuration nor files. Closed channel
owners suppress replies and drain active native work before engine disposal.

Windows uses `IDWriteFactory3` and
[GetSystemFontCollection(FALSE, …)](https://learn.microsoft.com/en-us/windows/win32/api/dwrite_3/nf-dwrite_3-idwritefactory3-getsystemfontcollection),
explicitly excluding downloadable fonts. An English family identity (first
available identity when English is absent) is stored separately from the
localized display name. DirectWrite groups the family's localized aliases and
faces; similar display names are not merged. Matching faces provide
[local face identities](https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritefont-getinformationalstrings).
A joined worker owns COM/DirectWrite/Direct2D/WIC resources; replies return to the
Flutter platform thread through an owned message window. No downloader is used.

The sample is a bounded native PNG: Pango/Cairo on Linux, DirectWrite/Direct2D/WIC
on Windows. Application labels keep the existing interface typeface. The sample
uses the resolved local family, short localized prose/digits/punctuation and
separate body-weight, relative-bold and italic lines, with bounded size/spacing. It does not
rely on Flutter's preferred `fontFamily` to establish availability. PNG bytes are
transient, capped and discarded with their owning preview. Locale, dimensions,
scaling, candidate and theme changes supersede earlier work. Closing the chooser
or native popover invalidates that work without focusing or reopening anything.

The reader registers private, random FontFace aliases using only validated native
local sources. Full/PostScript face identities precede the family alternative
needed by WebKitGTK's FreeType port. Chromium must resolve the actual face before
that family alternative. `FontFace.load()` must succeed. An embedded
publication font with the same public family name cannot capture the private
alias. Real missing faces are not labeled as bold/italic: the browser can
synthesize emphasis from the regular face when needed. Per-character fallback
remains available for scripts the chosen family does not cover.

Both resolvers request normal/italic matches across CSS weights 100–900, covering
the existing 300/400/500/600/700 controls and relative bold. Face metadata retains
the actual matched OpenType weight (validated from 1–1000); repeated matches are
coalesced during registration. Linux uses
[FcWeightToOpenTypeDouble](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-devel/)
with Fontconfig 2.13+; Windows uses `IDWriteFont::GetWeight()` and excludes
simulated faces. A family with fewer installed weights keeps those real weights
rather than relabeling them. Preview receives the body weight and uses the same
relative-bold mapping as CSS. No new weight controls or OpenType options are added.

[`document.fonts.check()` is not an existence test](https://drafts.csswg.org/css-font-loading/).
The native catalogue/match, local-face loading and native glyph tests establish
the path. Family names enter CSS only through validated string serialization and
controlled property APIs. Quoted literal names and
[unquoted generic keywords](https://www.w3.org/TR/css-fonts-4/) remain distinct.
No font filesystem endpoint, remote font permission, font importing, downloads,
new font bundle or font binaries in reading-data backups/caches are added.
Discovery reflects the fonts accessible to the process, including its confinement;
it does not promise fonts outside a Snap's environment.

## Appearance, persistence and reflow

One searchable chooser is embedded in Settings → Reading's advanced Appearance
controls; the compact native reading popover links to it.
Search keeps ordinary editing and IME composition. Search/candidate traversal
updates only the sample; activation applies through the primary controller (or
existing Settings writer). A committed, empty composition range is not treated
as active IME text. Enter can activate the matching candidate; Escape/Close
cancels browsing. Generic categories, installed families, current selection,
loading, Retry and no-match states use the existing themed controls. Stable row
and action identities preserve keyboard activation through async updates.

Publisher mode is stated explicitly. Choosing a family leaves that mode through
the existing typography callback; browsing does not. Returning to publisher mode
removes family overrides while retaining the remembered choice. Inline family
properties are restored exactly, including priority. Headings keep their sizes
and hierarchy; emphasis keeps weight/style. Code, math, SVG, symbols and marked
specialist fonts keep their original families. Newly loaded sections and
reflowable footnotes use the same resolved family.
The stylesheet passed to Foliate contains no replacement-family rule. Foliate
installs it before its section-load notification, so specialist families can be
captured from the publication before controlled inline overrides are applied.
This also covers cold opening with saved customization. Later font changes reuse
those originals; publisher restoration disables their protection stylesheet.

An unavailable saved name is retained. Its effective local serif fallback is
resolved separately and advanced Appearance explains that fallback when custom
typography is active. Availability refresh never overwrites a preference. Settings
explicitly selects the current-book or application-default scope. Selecting a
font writes only that scope. Reset Book Appearance clears the book's override;
resetting application defaults restores the existing defaults. Other explicit
book settings remain independent.
Settings save failure rolls back its own optimistic reading-default revision.

The controller serializes appearance writes, captures revisions/default targets
and waits for correlated renderer results. Failed rendering leaves committed
preferences intact; failed book writes restore the committed renderer choice and
use existing warning/action feedback. Newer selections release obsolete waiters;
book/view changes, fatal errors and shutdown invalidate old work. A delayed
activation cannot close a subsequently opened chooser.

Candidate faces are prepared without removing the visible family's faces or
publishing candidate preferences. Cancellation restores the previous settled
snapshot if styles have already changed, reports cancellation rather than
success, and captures the current passage after any user navigation. A newer
selection supersedes delayed loads and rollback. Footnote installation checks
the same appearance ownership. After a pending change was hidden, the controller
reconciles the retained renderer from the committed book record and awaits its
result before revealing it. A failed reconciliation retains a recoverable hidden
surface and reports feedback; the next return can retry.

Reflow captures the durable CFI, awaits local faces and `FontFaceSet.ready`, then
uses Foliate's public render/layout and renderer navigation interfaces. It does
not use an arbitrary sleep, a generated page number or `view.goTo()` history
insertion. Section-only CFIs have no text range and restore by their durable
section identity; full CFIs retain their in-document anchor. Resize/relocation
callbacks keep the original logical anchor/progress pinned until user navigation.
User navigation supersedes restoration. Existing selections are restored without
requesting focus or presenting another selection popover. Highlights and
read-aloud underlines repaint against their existing anchors. Completion policy,
annotation storage, search, dictionary, note drafts and original-file ownership
remain with their existing owners.

The advanced local-family chooser is in Settings → Reading. Escape returns from
the chooser to Font Family and disposes its bounded preview. The compact reading
popover links to these settings and no longer contains a separate native font
chooser or its former GTK/Windows Escape channel. This changes presentation only;
font identity, preference ownership and renderer apply/cancellation stay unchanged.

## Reproduce and platform evidence

Use official Flutter 3.47.5 / bundled Dart 3.13.4 and the existing lockfile.
No SDK, dependency or vendored-engine revision was changed. Relevant commands:

```sh
flutter pub get --offline --enforce-lockfile
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test tools
flutter analyze
flutter test --no-pub
node tools/reader_logic_probe.mjs
bash tools/probe_linux_typography.sh
bash tools/probe_linux_engines.sh
bash tools/probe_linux_input.sh
flutter build linux --release --no-pub
```

The typography probe creates an isolated temporary Fontconfig collection from
existing licensed Noto and Liberation resources. It creates a renamed OFL
punctuation/Unicode family and a publication whose embedded serif face claims an
installed sans-family name. Required notices accompany those disposable files;
they never enter the release bundle. It executes actual Pango preview generation,
Foliate/WebKit glyph rendering, emphasis, hierarchy, code exclusion, durable
passages/history, highlights, selection, search, narration anchors, footnotes,
chapter direction, rapid updates and publisher restoration. Fixed-layout and PDF
passes reject replacement and check their page/text content. Deterministic Dart
fixtures do not depend on a developer's installed collection.

Current execution details and screenshots are recorded in
[typography verification](typography-verification.md). Windows has a real native
implementation and a separate stock-desktop backend probe:

```powershell
flutter build windows --release
cmake -S tools/native_font_probe -B build/native-font-probe
cmake --build build/native-font-probe --config Release
./build/native-font-probe/Release/busybooks_native_font_probe.exe
```

That backend probe establishes DirectWrite discovery and native raster samples
when run on Windows. It does not establish WebView2 rendering, chooser focus,
DPI/monitor placement or accessibility. Those require the actual Windows app.
