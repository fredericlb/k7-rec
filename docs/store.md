# The rehearsal store (iOS)

`Packages/RehearsalStore/` holds the app's rows: songs, their files, takes, moments and markers. It
follows the web store's design (`apps/k7/backend-rs/docs/rehearsal/store.md`) and drops what is
server-shaped: ownership, releases, versions, pages, exercises, publications.

## GRDB and Yams, nothing else

GRDB (MIT) is SQLite with Swift concurrency and `ValueObservation`, which is what keeps SwiftUI
lists current without a hand-made change feed. It is pinned by exact version. Yams (MIT) reads the
song folder's `song.yaml`; Foundation has no YAML. Both are the user's approved libraries.

## A row is a JSON document

One table, `docs`, keyed by `(coll, id)`, each row a JSON document. A field added to a model needs
no migration, and a field a row never set decodes as its type's zero value, because every model's
decoder says so. `Schema.swift` lists the fields of each collection, and a test fails when a model
and its schema differ: the schema is what a filter's field name is checked against.

The fields rows are looked up by carry an expression index on `(coll, json_extract(fields, ...))`.
SQLite uses it only when the query spells the same expression, so a field name is written into the
SQL after the schema has vouched for it, never bound as a parameter.

A listing that names its fields reads only those, each pulled out in SQL: a take's envelope is not
handed back nor parsed unless asked for. The unselected fields decode as zeros.

## One writer, short transactions

The store is an actor over one `DatabaseQueue`: WAL, `synchronous = NORMAL` (a power cut can lose
the last commits, never corrupt the file). A write that spans rows is one `write` transaction, and
its closure is synchronous so nothing can await inside it. The rules of what leaves with what live
in `Store+Rules.swift`.

## What leaves with what

- A moment names a **recording** by its path, not a take (`apps/k7/backend-rs/docs/rehearsal/moments.md`):
  it outlives the take and the file it was cut from.
- Deleting a take or a recording deletes the markers pinned on it; moments stay on their clips.
- Deleting a moment deletes the markers it owns.
- Re-filing a recording moves its takes, moments and markers to the new path in one step.
- Deleting a song deletes its files; its takes stay, detached from the song.

## Observation

`Store.observe(query)` is a `nonisolated` async stream: it emits the listing at once and again on
each change, and ends with the error that stopped it. It emits only when the listing changed, since a write to another collection re-runs the query over the whole table. It is a throwing stream, since a database
error is not something a list view can recover by itself.

## The song folder importer

`SongFolder.read` is pure: a folder URL in, a `Song` and its `SongFile`s out. It reads only the
sidecar's `uuid`, `title`, `artist`, `tags` and the `songbook:` sheets' order and names
(`packages/mediatek/docs/songbook.md`); everything else in `song.yaml` is left alone. The uuid is
the song's id, so importing a folder twice updates a song instead of doubling it. A folder with no
uuid gets a UUIDv5-style hash of the path it was picked from (symlinks resolved) as id, never a
random one: picking the same folder again is idempotent, and two different folders that share a
name are two songs. Its folder name is its title. The destination is the importer's choice and
never decides the id: `SongFolder.destinationName(for:)` names it `<folder name> <first 8 of the
id>`, so two songs never share a copy and the importer never deletes a destination another song
owns. A moved folder is a new song. Sheets the sidecar does not list follow the
listed ones, by name. File ids derive from the song id and the file, for the same reason.
Paths are relative to the app's songs folder: the caller names the folder it copies the song to.

## Times and ids

Times are epoch seconds as numbers, which sort and compare in SQL as they are. An id is a random
15-character string, like the web store's.
