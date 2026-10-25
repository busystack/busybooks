# Books, collections and reading data

Original PDF, EPUB 2/3, FB2 (raw or ZIP-wrapped), CBZ and CBR files open directly.
Opening, reading, collection membership
and Backup & Restore Reading Data never move them or create managed library copies.
Rendering may stage disposable, verified resources, including a PDF snapshot.
Only explicit Move Book or Export Original Book changes publication files.

`reading-data.sqlite` is the sole application database. An owned isolate handles
all SQL, inspection, archives and file operations through a serialized queue.
Every connection explicitly enables and verifies foreign keys before transactions.
WAL and synchronous FULL protect committed data. Application preferences retain
the existing queued, atomic `settings.json` implementation.

Schema 2 adds database collections, indexed unique `(collection_id, book_id)`
memberships, known book locations and typed Recent. Collections have generated
IDs independent of names and paths. Books retain SHA-256 identities and existing
reading/annotation records. An annotation cannot replace a book or change its
owning book. Membership/collection removal leaves books and annotations intact.

The additive migration within `reading-data.sqlite` preserves existing
book/annotation data and turns known book paths into unverified locations.
Historical filesystem-definition records
remain inert; they are never opened, converted, scanned, backed up or replayed.
Unrelated `library.sqlite` files and managed book copies are neither inspected
nor changed; their presence does not affect startup, workspace state or the
interface. External manifests, old profiles and backups are left untouched.
Directories and manifest files are unsupported opening targets.

Collection queries return stored metadata immediately. Accessibility checks run
in batches of at most 64, without inspecting publication content. Selecting a
book verifies its entire content identity. A single-use worker token, bound to
the source instance and final stat, avoids inspecting the same selected file
twice. Only the latest validated FB2 prepared representation is retained temporarily;
plain and wrapped FB2 feed a bounded incremental XML decoder/parser once. EPUB inspection
reads a bounded ZIP directory and required metadata from file-backed input; cache
preparation streams each resource to staging with CRC, size and SHA-256 checks.
Comics retain an owned file-backed staging descriptor. PDF inspection streams
its fingerprint and retains only its header/trailer. Rendering uses a verified, content-addressed
`cache/pdf-v1/<id>/publication.pdf` snapshot. Native hosts receive its
`publicationPath`, while source verification and watching retain the original
path, physical file-instance identity and final size/modification/change times.
The watcher starts before native opening, with an instance-aware fallback poll
that remains active alongside native events. Validation of the original and
expected SHA-256 precedes parsing and preparation, including warm-cache opens. A missing/changed original cannot
be replaced by a cache. Cancellation and a replaced session cannot attach late
preparation results. Interrupted owned staging directories are removed under the
profile lock on startup.

The logical format is independent of the original representation. EPUB 2 remains
`epub`; `.fb2`, `.fb2.zip` and `.fbz` remain `fb2`. Optional `originalSuffix`
metadata plus the verified current path preserves the actual export suffix.
Compressed exports reproduce the complete original ZIP bytes. New format values
are JSON records in schema 2; no SQL migration or historical importer is needed.

Disposable `cache/fb2-v2` and `cache/comic-v2` representations contain controlled
resource indices and SHA-256 physical filenames. EPUB index version 4 and
FB2/comic index version 3 also record resource content digests. Warm validation
checks every digest, the exact physical file set, and format-specific descriptor
closure (EPUB package/manifest/spine, FB2 sections/links/images, comic pages).
A separate index digest detects truncated or edited descriptors. The reader
also verifies each fetched resource with WebCrypto SHA-256, detecting corruption
that occurs after preparation and before resource delivery. Ordinary Retry
forces regeneration; the first renderer cache/parsing failure receives one
automatic forced rebuild before reporting an unreadable publication. Versioned interpretation and
stable logical paths preserve case-distinct archive names on Windows. Preparation
publishes a complete validated directory and writes its index last. FB2-generated
XHTML is rendering preparation, never an authoritative replacement publication.
All original bytes, extracted pages, generated HTML, thumbnails and caches remain
excluded from backup. Source and decompression limits for the new formats are
listed in [format-verification.md](format-verification.md); EPUB/backup limits
are unchanged.

The v2 cache paths regenerate earlier prepared contents/page lists after the
[format review corrections](format-review-verification.md). Cache descriptor versions are independent of durable locators. Durable
locator versions remain 1; originals, content hashes and existing text
CFI paths are unchanged. Startup also cleans interrupted staging in the old
cache directories.

Known paths are references, including foreign-platform paths. Accessibility is
separate from verified identity. Locate checks the full SHA-256 and updates the
preferred location globally without moving anything or creating a new identity.
Failure to find a path does not establish whether a file was moved or deleted.
The Notebook reads stored quotations, notes, locations and structural metadata.
Stored outline records retain optional stable IDs, ordered depths, exact
destinations and publisher labels. Restore validates their types, uniqueness
and bounds, including finite PDF destination rectangles. FB2 anchors carry
`kind:fb2`, `version:1`, a stable section identity/index and CFI. Comic anchors
carry `kind:comic`, `version:1`, the exact logical format, zero-based page index
and hashed logical page identity. Optional within-page position and region
rectangles use normalized oriented intrinsic-image coordinates. Regions require
finite positive geometry wholly within one page; text/format mismatches are
rejected. Bookmark deduplication is page-wide and independent of region notes.
Comic locators admit only their versioned image fields; incompatible PDF/text
fields and unknown keys are rejected before restore writes. Comic ordering
ends within its own branch, so formerly accepted stray PDF fields cannot break
Notebook lists or Markdown export.

Opening the current database also repairs the previously accepted, unused PDF
`point` field on otherwise valid version-1 comic locators. The worker performs
this idempotent repair in one transaction under the profile lock before serving
any requests, including note/color edits or backup. It handles stored annotations,
current positions and outline destinations in batches of 32 candidate rows,
preserving identities, text and image geometry. PDF points, invalid geometry,
other unknown fields and unknown locator versions are unchanged. Incoming
backups still undergo strict validation and receive no such repair. No schema
change or historical database/backup importer is introduced. See
[upgrade verification](comic-locator-upgrade-verification.md).

Notebook ordering and Markdown references use these semantic locations. This metadata remains
reading data; regenerable page previews are not another persistence authority.

Move Book operates on the displayed physical source path. Its durable
`move_operations` journal belongs to the same database but is excluded from
backup. The worker records intent, stages cross-volume copies, verifies complete
bytes, publishes without overwriting and commits the new location before guarded
source removal. Physical file identity prevents recovery from deleting a
replacement at the old path, even with identical content. Source removal uses an
owned quarantine and verification. Linux directory fsync and Windows
MOVEFILE_WRITE_THROUGH complement durable SQLite journal commits; Windows never
uses MOVEFILE_COPY_ALLOWED. Final verification checks destination bytes, database
location and source absence. Other known copies are preserved.

An interrupted move remains visible on Home with source, destination and stage.
Retry explicitly resumes the journal and rechecks identity. Keep Files stops
recovery only after verifying an accessible original; it preserves originals
and removes only an owned temporary copy. Verified destination
plus retained source is an incomplete move. Recovery preserves changed source or
staging paths. Restore is blocked until pending moves have been resolved; it
never replays operations from an archive.

Backup format 3 is a bounded logical ZIP containing `manifest.json` only. It
includes book metadata/location references, collections/memberships, positions,
appearance, annotations/private notes, Recent and application settings. It
excludes original bytes, known regenerable cover thumbnails, resource caches and
operation journals. Explicitly edited and historical edited cover metadata is
retained. Backup flushes pending notes,
positions and settings and snapshots the worker in a transaction, then publishes
atomically. It succeeds without checking or hashing external books.

Export and restore share the 100,000 combined-record and 128 MiB encoded-manifest
limits. Books, annotations, collections, memberships, locations and Recent all
count. Export validates the complete logical snapshot before publishing; bounded
UTF-8 encoding stops at the byte limit. Rejection leaves the source data and any
previous destination backup intact.

Restore validates the entire typed dataset before committing. IDs, references,
uniqueness, publication-specific anchors, finite/bounded coordinates, supported
types/colors and bounded notes are enforced. Book presentation fields are typed
before publication, including nullable integer timestamps within the supported
nonnegative millisecond range, bounded sanitized cover data URIs and per-book
appearance. Valid optional omissions retain their defaults. Matching book/annotation/collection
and Recent records are replaced; unrelated data stays. Matching memberships
replace their added order; other existing memberships remain. Names never merge
collections. Older backup schemas are rejected without conversion. Incoming
locations become unverified; foreign paths are never created. A committed
settings replay is acknowledged only after settings publication succeeds.

Reading appearance's `font` field accepts the existing generic strings and bounded
literal family identities (`{"family":"…"}`); existing named strings normalize
without losing their names. Book validation, settings normalization and backup
restore share that contract. Font availability is runtime resolution state, never
a storage allowlist. No font paths/binaries or preview PNGs enter reading data or
backups. See [typography.md](typography.md) for default/reset and failure behavior.

Reader messages use session-owned, ordered JSON chunks when a logical command
or event exceeds 128 KiB. Frames remain below the native 1 MiB UTF-8 limit; a
logical payload has a 16 MiB UTF-16 limit and fails explicitly above that bound.
Incomplete transfers and native bridge-limit errors cannot acknowledge a flush.
Locations omit passage text; selections and on-demand narration own quotations.
New PDF segment anchors store `length` instead of duplicating text. Legacy
text-bearing PDF anchors remain readable and restorable, including from backups.

Publication resource limits apply before cache publication and in the reader's
streamed response consumer, before hashing or text decoding. Text/SVG is capped
at 4 MiB, navigation/NCX/CSS at 1 MiB, raster images at 64 MiB and fonts at 32 MiB.
Filename, manifest type and payload checks constrain disguised markup/fonts;
structural checks also bound XML and tolerant HTML before a WebView DOM exists.
Comic caches contain supported pages and at most one bounded ComicInfo file.
Unused entries are integrity-checked into a discard sink, with a separate
128 MiB work budget. Disk preflight accounts for retained bytes and a 64 MiB
reserve; RAR performs a header-only first pass before staging any data.

Windows source and move identity uses GetFileInformationByHandleEx(FileIdInfo):
the full 64-bit volume serial and 128-bit file ID. The attribute/reparse guard
uses FileAttributeTagInfo. Unsupported identity queries fail closed; legacy
64-bit move-journal identities are not accepted as physical-instance proof.
