# k7-rec

A native iPhone and Mac app (SwiftUI, iOS 17, Mac Catalyst) extracted from k7's rehearsal part: a song list with chords, lyrics,
tabs and sheets, and a recorder with moments and markers. No account, no server of ours: songs and takes
sync through the user's iCloud (`docs/sync.md`), on the iPhone and the Mac (`docs/mac.md`). Songs come from imported files (a song
folder or an audio file), and an FTPS or SFTP server.

```
App/        the app: project.yml (XcodeGen), SwiftUI sources, tests
Packages/   RehearsalText (chords, lyrics, tablature), RehearsalAudio (recorder, player, moments),
            RehearsalStore (SQLite documents, song folders), RehearsalStems (stem separation and a mixing player), RehearsalFTP (an FTPS client), RehearsalSFTP (an SFTP client over Citadel)
docs/       one page per zone: app, audio, stems, store, text, sync, server, mac, score — choices, not mechanism
```

## Build

```
cd App && xcodegen generate            # the .xcodeproj is generated and ignored
xcodebuild -project Rehearsal.xcodeproj -scheme Rehearsal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
(cd Packages/RehearsalText && swift test)   # same for RehearsalAudio, RehearsalStems, RehearsalStore, RehearsalFTP and RehearsalSFTP
xcodebuild -project Rehearsal.xcodeproj -scheme Rehearsal -destination 'platform=macOS,variant=Mac Catalyst' build
```

Third-party code: GRDB and Yams (MIT), and the guitar chord data of `@tombatossals/chords-db`
(MIT, in `App/Resources/ChordsDB`), Verovio's JavaScript build (LGPL-3.0) and the SONiVOX General MIDI
bank (Apache-2.0) for scores (in `App/Resources/Score`). Everything else is Apple's frameworks.

## Provenance

The packages port code of the k7 repository. The paths the docs and comments name under
`packages/…` and `apps/k7/…` (for example `packages/lyrics/src/chords.ts`) are that repository's, kept
so a behaviour can be compared with its original; they do not exist here.
