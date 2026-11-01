# Current-data comic locator upgrade fixtures

These fixtures contain only BusyBooks-generated CC0 text and references/hashes
to the existing CC0 fixture publications. They contain no publication bytes,
extracted pages, thumbnails or resource caches. Paths under
`/busybooks-fixture-originals/` deliberately reference missing originals.

`comic-locator-previous-profile.sql` is a snapshot of a real, closed
`reading-data.sqlite` schema-2 profile produced by implementation
`852bd74ec290ffe5f14acef729f51b6b43d0f55c`. That implementation restored CBZ and
CBR region/page notes containing `point: []`, edited two affected notes/colors,
and successfully created a reading-data backup. The snapshot also contains
comic current-position/outline points, unaffected same-region notes and a PDF
highlight with genuine PDF coordinates and quoted text. The fixture preserves
the resulting JSON, identities, geometry and schema. It is executed only by
tests to recreate that current-data profile; SQL is not an application importer.

`comic-locator-previous-backup.json` is the decoded manifest from that actual
previous-version backup. The current tests ZIP it as `manifest.json` to verify
that malformed incoming backups continue to be rejected, including after a
valid book projection reaches annotation validation.

`tools/make_comic_locator_upgrade_fixture.py` regenerates both files using local
Git objects, disposable profiles and the pinned SDK/cache. It also opens the
same previous profile with `b36f6fb0e0de4aca4e5e2012eb6df8d3503a4f40` and
requires editing and backup to fail with `comic locator fields`. No installed
profile is used. The generator requires Python 3.12+, the existing pinned
Flutter/Dart tools on PATH, an offline populated package cache and both Git
revisions. Ordinary Flutter tests consume the committed fixtures and require
neither historical checkouts nor fixture generation. Byte hashes are recorded
in `SHA256SUMS`.
