# Sync

Songs and takes follow the user's iCloud account; the database does not.

## Choices

- **Files live in the app's iCloud container** (`iCloud.rocks.k7.rec`, Documents): `Songs/`, `Takes/`
  (stems sit in their song's folder) and `Records/`. The Files app shows them under iCloud Drive. Without a
  container (signed out, simulator, tests) the same folders sit in the local Documents and nothing else changes.
- **The model and the database stay on the device.** The 400 MB separation model is installed per device, and
  SQLite's WAL must never be copied file by file: two devices writing would corrupt it.
- **The database is rebuilt from `Records/`.** One JSON per song (the row and its file rows) and one per take
  (the row, its moments and its pins). Every device mirrors its rows into them and applies the ones another
  device wrote. Paths in rows are relative to the container, so a move between roots changes no row.
- **Three versions are compared, never two.** For each record: the rows as they are now, the file as it is now,
  and the file's hash at the last pass. A file that differs from that hash was changed elsewhere and wins; a
  file equal to it while the rows differ is a local change and is written. A hash is kept only once the rows or
  the file really hold the record: a record that does not decode, or a write that fails, is tried again.
- **Absence is never a deletion.** A record whose file is missing is written again from the rows; rows that are
  missing are rebuilt from the file. A deletion is something the user did: deleting a take writes
  `take-<id>.json.deleted`, removes the record, and any device that reads that tombstone drops the rows. A bug,
  a late download or a reinstall can therefore lose nothing that the records still hold.
- **A file still in iCloud is left out of the pass.** A record that cannot be read yet (a dataless file, or a
  `.name.icloud` placeholder on older systems) keeps out of it and is asked for. A library that fell back to memory is never mirrored, and a pass that cannot read
  the rows changes nothing.
- **Media is asked for on every pass, not fetched on demand.** Any file under `Songs/` and `Takes/` whose
  downloading status is not current is asked for, so a song imported on another device plays here. The status
  is read, not the name: iCloud keeps a file that is not downloaded under its own name, dataless, and a walk
  that looks only for `.name.icloud` placeholders never asks for it. A song shown before its audio arrives
  reads it again when iCloud reports a delivery.
- **A raw take in progress is in the Takes folder too**, and so is uploaded while it grows; it is removed once
  the take is saved. Recording into a local scratch folder would avoid the upload.
- **A first launch with the container moves** the local `Songs/` and `Takes/` into it, item by item; a name
  already in the container is left alone.

## Only a device can verify

- The container and its entitlement (needs the iCloud capability on the App ID, signed in to iCloud).
- A record written on one phone reaching another, a take's audio downloading, a deletion travelling.
- Signing out of iCloud: the app then reads the local folders, which no longer hold the moved files.
