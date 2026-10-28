# BusyStack UI and source references

[BusyMark](https://github.com/busystack/busymark), revision
`7008772ce26b0d133bed9c0d01754b43d93c672b`, is the original BusyStack UI and
application-foundation reference. Adapted code retains BusyStack's Apache-2.0
attribution; see [NOTICE](../../NOTICE). A BusyMark checkout is not required to
build or run BusyBooks.

## Reuse map

| BusyMark foundation | BusyBooks responsibility |
| --- | --- |
| Theme, semantic surfaces, glyphs and controls | Shared BusyStack appearance and geometry |
| Linux window/header services, GTK preferences/icons/accent | Flutter window controls, header gestures and live desktop preferences |
| Workspace header/view selector, side-by-side panes and outline rows | Retained Reading/Notebook/Split shell, labeled selector, disclosure/indentation and trailing location column |
| Search session/sidebar and shared header input | Shared categorized search with repository-backed scopes and owned native session checks |
| Dialogs, feedback, motion, Settings and menus | Shared controls, adaptive navigation and reduced-motion behavior |
| Command registry, keymaps and shortcut capture | Book commands, configurable bindings and conflict validation |
| Ordered settings writer and startup handoff | Reading preferences and serialized atomic settings writes |
| Storage isolate and atomic file writer | Independent reading-data schema, transactions, durable publication and shutdown flushing |
| Localization and desktop packaging patterns | Product-local English/German strings and independent Linux/Windows builds |

BusyBooks' publication engines, content identity, collection model, protected
Notebook drafts and file workflows have their own owners. See
[workspace architecture](reading-workspace.md), [readers](readers.md) and
[storage](storage.md).

BusyMark's `_EditorPreviewSplit` uses side-by-side panes and a fixed divider.
BusyBooks retains that presentation concept while adding its own adjustable
divider, shared reader/Notebook ownership and measured-width collapse policy.
These are application integration changes, not modifications to a dependency or
a runtime link to the neighbouring checkout.

The adjacent Previous/Next controls follow BusyMax's schedule-toolbar reference
at `3fff55e62ae7dc6467d60309ca988b74d0950bc4`, using `go-previous-symbolic` and
`go-next-symbolic`. The location trigger between them belongs to BusyBooks.

Snap packaging retains the build-owned official SDK checkout and GNOME/Mesa
RUNPATH precedence handling. The session D-Bus slot supports GApplication file
opening; profile-suffixed names remain beneath the declared application name.
Installed strict-Snap acceptance is a separate qualification scope described in
[known issues](known-issues.md).
