# The app shell

The Rehearsal app is a SwiftUI shell over three local packages (text, audio, store). It owns no logic
of its own: screens read and write through small protocols, and the packages are wired in behind them.

## Project definition

- **XcodeGen, `App/project.yml` checked in, the `.xcodeproj` generated and git-ignored.** A hand-kept
  `.pbxproj` merges badly and four branches touch this tree at once. XcodeGen (MIT, a dev tool, not
  linked into the app) is installed with `brew install xcodegen`; run `xcodegen generate` in `App/`.
- **The Info.plist is generated from `project.yml`** (`info:`), so one file holds every key: microphone and
  Apple Music usage strings, `UIFileSharingEnabled` (takes and songs show in the Files app), in-place
  document opening, and the `audio` background mode so a take survives a locked screen.
- **iOS 17, SwiftUI lifecycle, iPhone and iPad, all orientations on iPad.** iOS 17 gives `@Observable`
  and `ContentUnavailableView`; nothing needs UIKit app delegates.
- **Bundle id `se.frediver.rehearsal`, display name "Rehearsal".**

## Seams

`App/Sources/Seams/` holds `SongLibrary`, `TakeRecording` and `TakePlaying`, each with an in-memory fake.
The shell compiles and runs with no package present, and integration replaces the three fakes in
`AppModel`'s defaults: no screen changes. Seam types (`Song`, `Take`) are the app's own and are mapped
from the store's models at the wiring point, so a model change does not reach the views.

## Screens

- **Songs, Takes, Settings** as a tab bar; iPad shows it as a sidebar through SwiftUI's adaptive style.
- **A song is one column of tabs** (`packages/ui-library/docs/songPlayer.md`): it opens on chords, else
  lyrics, else sheets; Info is last, an icon pinned right outside the scrolling row; the header holds play,
  the title and a ⋮ menu. Back is the navigation bar's.
- **The recorder is a bar, never a dialog** (`packages/recorder/docs/recorder.md`): a bottom safe-area
  inset on the root view, so every tab and the song stay usable while a take runs.
- **Import is the system document picker** (`fileImporter`) for folders and audio files; it hands the
  URLs to `SongLibrary.importURLs` and does nothing else. Security-scoped access belongs to the real library.
- **Icons are SF Symbols.**
