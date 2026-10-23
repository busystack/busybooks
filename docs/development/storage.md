# Books, collections and reading data

Original EPUB/PDF files open directly. Opening, reading, collection membership
and Backup & Restore Reading Data never move or copy them. Only explicit Move
Book or Export Original Book changes publication files.

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
book verifies its entire content identity. A single-use, stat-bound worker token
avoids inspecting the same selected file twice; only the latest EPUB inspection
buffer is retained temporarily for cache preparation. PDF inspection streams its
fingerprint and retains only its header/trailer. Regenerable EPUB resource caches
preserve existing archive/resource isolation.

Known paths are references, including foreign-platform paths. Accessibility is
separate from verified identity. Locate checks the full SHA-256 and updates the
preferred location globally without moving anything or creating a new identity.
Failure to find a path does not establish whether a file was moved or deleted.
The Notebook reads stored quotations, notes, locations and structural metadata.
Stored outline records retain optional stable IDs, ordered depths, exact
destinations and publisher labels. Restore validates their types, uniqueness
and bounds, including finite PDF destination rectangles. This metadata remains
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
