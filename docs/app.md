# The app shell

The Rehearsal app is a SwiftUI shell over three local packages (text, audio, store). It owns no logic
of its own: screens read and write through small protocols, and the packages are wired in behind them.

## Project definition

- **XcodeGen, `App/project.yml` checked in, the `.xcodeproj` generated and git-ignored.** A hand-kept
  `.pbxproj` merges badly and four branches touch this tree at once. XcodeGen (MIT, a dev tool, not
  linked into the app) is any `xcodegen` on the PATH; run `xcodegen generate` in `App/`.
- **The Info.plist is generated from `project.yml`** (`info:`), so one file holds every key: microphone and
  Apple Music usage strings, `UIFileSharingEnabled` (takes and songs show in the Files app), in-place
  document opening, and the `audio` background mode so a take survives a locked screen.
- **iOS 17, SwiftUI lifecycle, iPhone and iPad, all orientations on iPad.** iOS 17 gives `@Observable`
  and `ContentUnavailableView`; nothing needs UIKit app delegates.
- **Bundle id `se.frediver.rehearsal`, display name "Rehearsal".**

## Seams

`App/Sources/Seams/` holds `SongLibrary`, `TakeRecording` and `TakePlaying`, each with an in-memory fake kept
for previews and tests; `App/Sources/Live/` holds the real ones over the three packages, and
`AppModel.live()` is the only place that builds them. Seam types (`Song`, `Take`) are the app's own and are
mapped from the store's models, so a model change does not reach the views.

- **The seams are `@MainActor` and the real ones `@Observable`**, so a list reads `model.library.songs` and
  redraws when the store changes; the store is observed, never polled.
- **Files live in Documents (`Songs/`, `Takes/`), the database in Application Support**: Files shows what
  the user can own, not the SQLite file. `AppPaths(root:)` moves all three into a temp folder for tests.
- **Import copies, then files.** A picked folder or audio file is copied into `Songs/` (security-scoped
  access held only during the copy), then read by `SongFolder.read`. An audio file alone becomes a folder
  holding `original.<ext>`, titled by its tags, else its file name. Re-importing the same name replaces it.
- **A listing never carries a take's envelope**; the detail page loads it with `take(id:)`.
- **The playhead is not part of the waveform.** `WaveformBars` is an `Equatable` Canvas fed only the
  samples; a separate overlay moves on a `TimelineView` that ticks only while playing.
- **Debug builds import `-ImportOnLaunch a:b`** (host paths), which lets the simulator be fed with no picker.

## Device only

Nothing here needs a phone to build, but these cannot be checked on the simulator or in the suite: the
microphone permission prompt and a real `EngineInput` take, routing to speaker or Bluetooth, an
interruption by a call, the system file picker's security-scoped URLs from iCloud, and what is audible.

## Screens

- **Songs, Takes, Settings** as a plain `TabView`: a bottom bar on iPhone, a top bar on iPad (iOS 26). A sidebar needs `.sidebarAdaptable`, iOS 18 and later, so it waits for a deployment target above 17.
- **A song is one column of tabs** (`packages/ui-library/docs/songPlayer.md`): it opens on chords, else
  lyrics, else sheets; Info is last, an icon pinned right outside the scrolling row; the header holds play,
  the title and a ⋮ menu. Back is the navigation bar's.
- **The recorder is a bar, never a dialog** (`packages/recorder/docs/recorder.md`): a bottom safe-area
  inset on the root view, so every tab and the song stay usable while a take runs.
- **Import is the system document picker** (`fileImporter`) for folders and audio files; it hands the
  URLs to `SongLibrary.importURLs` and does nothing else. Security-scoped access belongs to the real library.
- **Icons are SF Symbols.**

## The song screen

- **One file per tab** under `App/Sources/Screens/Song/`; `SongScreen` holds only the header, the tab row
  and the state the tabs share. The pure text logic (transposed lines, the sung line, tab grids, LRC,
  re-timing) is `Logic/SongText.swift`, so tests reach it without a view.
- **The screen reads the live song by id**: the pushed value is a snapshot, and an edit must show at once.
- **The sung line is polled, not observed**: a 150 ms loop runs only while the song plays and writes the
  line only when it changes, so the lists redraw on a line change and not on every frame. A tap on a timed
  line seeks `lyrics lead` seconds early (1 s, kept in UserDefaults, a Settings stepper) and starts playing,
  as the web does.
- **Transposition is kept per song in UserDefaults**, folded into -5...+6. It moves what is read: the
  chords and lyrics tabs and the diagrams; the files are never rewritten.
- **Chords and tab are monospace, scrolled sideways, never wrapped**, since alignment is the data. The
  sideways scroll is nested in the vertical one: a two-axis `ScrollView` centres short content.
- **The popover, not a menu, holds the ⋮ controls** (`.presentationCompactAdaptation(.popover)`), and the
  metronome lives in `AppModel`, so its click outlives the popover.
- **Texts are plain files of the song folder.** Saving writes the file, then rewrites the `SongFile` row in
  one transaction; an emptied text removes both. After a lyrics edit, chords that already carry timecodes
  are re-timed onto the new lyrics with `LRC.mergeTimedSheet`; untimed chords are left alone.
- **Sheets** are copied into `sheets/` under a unique name and ordered by `position`, which is the
  sidecar's order for imported ones; PDFs go through PDFKit, images through a zooming scroll view.
- **Tags are edited on the row only.** `song.yaml` is never rewritten, so re-importing the folder restores
  the sidecar's tags.
- **LRC import** merges a picked `.lrc` into the lyrics with `LRC.merge`, writing `{{MM:SS.cc}}` codes as the web does.

## Chord diagrams

`Logic/ChordDiagrams.swift` is the only file that reads `Resources/ChordsDB/guitar.json`, the guitar data of
`@tombatossals/chords-db` (MIT, licence beside it). The JSON is cut to what is drawn: no MIDI, and only each
chord's first fingering. The lookup follows `chordDiagram.ts` (`ROOT_TO_DB`, exact quality, slash form, bare
triad) and answers nil for what is not a chord; a card with no diagram shows its name alone.

## Device only (M3)

Nothing new needs a device; what is audible, the metronome click through a speaker or Bluetooth, and the
file picker on iCloud files are still checked by hand.
