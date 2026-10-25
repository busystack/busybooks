# Stored comic locator upgrade

This follow-up starts from `b36f6fb`. The previous correction made sorting and
Markdown export safe and rejected malformed incoming locators, but left existing
stored `point` fields in place. Ordinary note/color updates and reading-data
backup then failed when they revalidated those existing records.
The repair, fixtures and regressions are committed locally as `78b234d`.

The worker now removes that unused PDF field from otherwise valid version-1
comic locations before initialization completes. The repair operates only on
the current `reading-data.sqlite`, under its existing profile lock, in a single
transaction and batches of 32 candidate records. It includes annotations,
current positions and outline destinations because backup validates all of them.
There is no schema bump, external-file inspection or historical importer.

Only `point` is removed. Every repaired record must pass the unchanged full book
or annotation validator before it is written. Annotation IDs, book ownership,
quoted/private text, color, timestamps, page IDs, position and region geometry
remain unchanged. Unaffected rows remain byte-identical. Unknown locator
versions and invalid geometry are left intact rather than guessed. A failed
write rolls back the entire repair; reopening retries it. Incoming books,
annotations and backup manifests still use the strict validators unchanged.

## Transition regression

The fixtures come from the actual previous implementation's closed database.
Provenance, regeneration instructions and SHA-256 hashes are in
[reading-data fixtures](../../test/fixtures/reading-data/PROVENANCE.md).

1. `852bd74` restores the affected CBZ/CBR records, edits two notes/colors and
   creates a backup successfully. Its closed schema-2 database is snapshotted.
2. `b36f6fb` opens the same profile and reproduces both edit and backup failures
   with `Invalid reading data: comic locator fields`.
3. The corrected store opens that profile and persists the minimal repair.
   Backup succeeds immediately with missing originals, before any edits.
4. Separate note and color edits succeed for region and page notes in both
   comic formats. A new data-only backup restores into a fresh profile with
   exact expected identities, text, page/region geometry and edits.
5. A second reopen leaves the stored JSON unchanged. PDF coordinates and quoted
   text, plus unaffected same-region notes, remain intact throughout.

Further regressions reject the actual previous backup atomically, including an
annotation-only malformed case after valid book records. Existing repaired data
remains unchanged on failed restore. Invalid image geometry and an unknown
locator version remain unrepaired. A 40-note extension crosses the repair batch
boundary; a trigger rejects a late update, proving all earlier repairs roll back
and a subsequent reopen repairs the complete profile successfully.

## Verification boundary

| Executed check | Result |
| --- | --- |
| Actual previous implementation/control transition | Old restore, two edits and backup passed; both failures reproduced with `b36f6fb` |
| Full pinned Flutter suite | 353 passed; one existing opt-in live Wiktionary test skipped |
| Flutter analysis; Dart formatting | No issues; 134 files unchanged by formatting |
| Raw Dart storage and backup-contract probes | 88 storage checks and 63 backup-boundary checks passed |
| Annotation ordering probe | Five checks passed |
| Dependency pins, fixture hashes and vendor hashes | Unchanged dependencies; both fixture hashes and all 218 vendor hashes verified |
| Linux release build | Passed with Flutter 3.47.5 / Dart 3.13.4 |
| Actual extracted application profile upgrade | Ten records retained; six repaired; unaffected rows byte-identical; schema remains 2 |

The rebuilt artifact is
`build/distributions/busybooks-0.1.0-linux-x64-comic-locator-upgrade.tar.gz`,
SHA-256 `567379c8aa90e7ca61a96981a6400383535f472432a5b283b86aaa09be5bf11d`.
The extracted release application's compiled worker upgrades the actual previous
profile at startup, with every field other than the ignored comic `point`
preserved. Previous artifacts and historical verification records are retained.

Executed checks and exact package provenance are recorded in
[comic-locator-upgrade-results.json](comic-locator-upgrade-results.json); raw logs
are retained locally under `evidence/comic-locator-upgrade-20261023/`.
Previous renderer/native results remain in
[format review verification](format-review-verification.md). This correction
changes only the Dart store initialization path and its tests/documentation;
the EPUB/PDF/comic renderers, resource boundary, decoder, SDK and dependency
versions remain unchanged. Windows WebView2 and installed strict-Snap
acceptance remain unverified platform gates.
