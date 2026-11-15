# k7-rec

A native iOS app (SwiftUI, iOS 17) extracted from k7's rehearsal part: a song list with chords, lyrics,
tabs and sheets, and a recorder with moments and markers. Everything is local: no account, no server,
no synchronisation. Songs come from imported files (a song folder or an audio file) and from the
Apple Music items the device can read.

```
App/        the app: project.yml (XcodeGen), SwiftUI sources, tests
Packages/   RehearsalText (chords, lyrics, tablature), RehearsalAudio (recorder, player, moments),
            RehearsalStore (SQLite documents, song folders)
docs/       one page per zone: app, audio, store, text — choices, not mechanism
```

## Build

```
cd App && xcodegen generate            # the .xcodeproj is generated and ignored
xcodebuild -project Rehearsal.xcodeproj -scheme Rehearsal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
(cd Packages/RehearsalText && swift test)   # same for RehearsalAudio and RehearsalStore
```

Third-party code: GRDB and Yams (MIT), and the guitar chord data of `@tombatossals/chords-db`
(MIT, in `App/Resources/ChordsDB`). Everything else is Apple's frameworks.

## Provenance

The packages port code of the k7 repository. The paths the docs and comments name under
`packages/…` and `apps/k7/…` (for example `packages/lyrics/src/chords.ts`) are that repository's, kept
so a behaviour can be compared with its original; they do not exist here.
