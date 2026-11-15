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
