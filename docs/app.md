# The app shell

The Rehearsal app is a SwiftUI shell over three local packages (text, audio, store). It owns no logic
of its own: screens read and write through small protocols, and the packages are wired in behind them.

## Project definition

- **XcodeGen, `App/project.yml` checked in, the `.xcodeproj` generated and git-ignored.** A hand-kept
  `.pbxproj` merges badly and four branches touch this tree at once. XcodeGen (MIT, a dev tool, not
  linked into the app) is any `xcodegen` on the PATH; run `xcodegen generate` in `App/`.
- **The Info.plist is generated from `project.yml`** (`info:`), so one file holds every key: microphone and
  local network usage strings, `UIFileSharingEnabled` (takes and songs show in the Files app), in-place
  document opening, and the `audio` background mode so a take survives a locked screen.
- **iOS 17, SwiftUI lifecycle, iPhone and iPad, all orientations on iPad.** iOS 17 gives `@Observable`
  and `ContentUnavailableView`; nothing needs UIKit app delegates.
- **Bundle id `se.frediver.rehearsal`, display name "Rehearsal".** The version is `MARKETING_VERSION` in
  `project.yml`, read by Settings from the bundle.
- **Swift 6 language mode**, like the three packages, so every `@MainActor` and `Sendable` claim is checked.
  What the system calls back off the main actor (the media picker's delegate, the media permission) is
  handled where no actor owns the closure.

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
  holding `original.<ext>`, titled by its tags, else its file name.
- **A copy is named by `SongFolder.destinationName(for:)`** (its name plus 8 characters of its id), so two
  songs of the same name never share a folder. The song row names its folder, so a text typed into a
  song that lost its last file goes back to that song's own folder.
- **A re-import refreshes the copy from the source and keeps what the app made.** The copy is built in a
  temporary folder, the texts and sheets the source lacks are carried over from the old copy, the tags stay
  when the sidecar has none, and the old copy is swapped for the new whole: a copy that fails leaves the song
  as it was.
- **The copy, never the source, gets the uuid.** A picked folder with no uuid has one written into the
  COPIED `song.yaml` (the source is read-only to us), after a leading `---` when the file has one, and the
  same uuid again when that folder is imported again. The song's id then belongs to the copy and does not
  move with the picked folder's path.
- **Takes survive a crash and a call.** A take paused by a call or a lost input stays in the take panel
  with a Resume button; a resume on another input rate ends that part and continues it, which the
  encoder joins; the first part's raw file goes once the continuation's own sidecar holds its audio. At
  launch, the raw takes a crash left are encoded and saved as "Recovered take" rows with no song (the raw
  file does not know it); a raw file is deleted only after its row is saved, and the ones that cannot be
  encoded stay in the folder and are counted in a notice.
- **The audio session is given back** when nothing records, plays or clicks, so another app's music resumes.
- **The headset microphone is a setting, off by default**: earphones then play in full quality and the
  take uses the phone's microphone (`docs/audio.md`).
- **The song list is built off the main actor**, once per change of the rows and files, with each text read
  there; a song carries flags (`hasDiagrams`, `hasChords`...) so the screen never parses to know its tabs.
  A parsed text is kept until the text or the transposition changes.
- **A listing never carries a take's envelope**; the detail page loads it with `take(id:)`.
- **The playhead is not part of the waveform.** `WaveformBars` is an `Equatable` Canvas fed only the
  samples; a separate overlay moves on a `TimelineView` that ticks only while playing.
- **Debug builds import `-ImportOnLaunch a:b`** (host paths), which lets the simulator be fed with no picker.

## Device only

Nothing here needs a phone to build, but these cannot be checked on the simulator or in the suite: the
microphone permission prompt and a real `EngineInput` take, routing to speaker or Bluetooth, an
interruption by a call, the system file picker's security-scoped URLs from iCloud, what is audible, the
metronome click through a speaker or Bluetooth, and a take recorded while a song plays (the
speaker is picked up by the microphone; headphones are not).

## Screens

- **Songs, Takes, Settings** as a plain `TabView`: a bottom bar on iPhone, a top bar on iPad (iOS 26). A sidebar needs `.sidebarAdaptable`, iOS 18 and later, so it waits for a deployment target above 17.
- **A song is one column of tabs** (`packages/ui-library/docs/songPlayer.md`): it opens on chords, else
  lyrics, else sheets; Info is last, an icon pinned right outside the scrolling row; the header holds play,
  the title and a menu. Back is the navigation bar's.
- **Recording is one button, at the top right of every screen**: a tap starts a take where the person is,
  with no change of screen; on a song's page the take belongs to that song. While a take runs, the button is
  an LED lit by the input level (black, green, orange, red; `Logic/LevelLED.swift`), ringed red so a silent
  take still reads as recording, and a tap opens the take panel as a sheet (clock, waveform, moments, pause
  and stop). The metronome sits in the same panel, reached while idle from the button's context menu. The
  screens stay usable under a running take; nothing sits above the tab bar.
- **The panel draws the running take**: the last 30 seconds of its envelope, re-levelled to the loudest bucket so far
  (`Logic/LiveTake.swift`), with the metronome right under it and the take's controls below.
- **The moments found so far are listed under the controls**, each with its own slice of the waveform and a play
  button. The detector runs at its default floor and silence; a moment still open counts once it is 4 seconds
  long, so a row can change or vanish while the take grows. Playing one rests the take first, so the speaker is
  never recorded, and reads the take's raw file (readable while it is written, flushed first) at the take's
  playback gain; Resume or Stop silences it. A moment of an earlier part of a continued take plays from that part.
  The take's page gives the final list.
- **Lyrics come from LRCLIB at import, and again from the song menu.** A song that arrives without lyrics
  (a file, a folder, a server file) is looked up on lrclib.net by title, artist and, for a file,
  its duration; timed lyrics are saved in the app's own timecodes, else the words alone. Only those three
  values leave the device, and only here. A failure never blocks the import: one notice says which songs
  got nothing, and the song menu's "Download lyrics from LRCLIB" repeats the lookup. A song that already
  has lyrics only gets timing from it: its words are never replaced.
- **The song's header is the navigation bar**: back, then play and the title, the menu at the right. A bar item is 36 pt
  tall whatever its label asks for, so those two are the one exception to the 44 pt rule.
- **A file server can feed the import**: Settings connects one FTPS or SFTP server (`docs/server.md`), and Songs' + menu then
  offers it. The import sheet browses folders and ticks audio files; they are downloaded and imported as picked files.
  "Missing song" in the same menu asks for an artist and a title and adds them to `MISSING-SONGS.md` on the server.
- **The chords take the lyrics' times.** Whenever the lyrics or the chords are saved (typed, imported from an LRC,
  downloaded), each sung line of the chords takes the time of the lyrics line it matches (`LRC.mergeTimedSheet`,
  the matching that times lyrics from an LRC), so a tap on a chord line seeks the song. It runs in the library,
  where both texts are written, never in a screen. Lyrics with no time, or no line that matches, leave the chords
  as typed.
- **Import is the system document picker** (`fileImporter`) for folders and audio files; it hands the
  URLs to `SongLibrary.importURLs` and does nothing else. Security-scoped access belongs to the real library.
- **Icons are SF Symbols.**

## The song screen

- **One file per tab** under `App/Sources/Screens/Song/`; `SongScreen` holds only the header, the tab row
  and the state the tabs share. The two file pickers (a sheet, an LRC file) are one importer told which
  kind it is asked for, since a view presents one `fileImporter` only. The pure text logic (transposed lines, the sung line, tab grids, LRC,
  re-timing) is `Logic/SongText.swift`, so tests reach it without a view.
- **The screen reads the live song by id**: the pushed value is a snapshot, and an edit must show at once.
- **The sung line is polled, not observed**: a 150 ms loop runs only while the song plays, over timings read
  once, and writes the line only when it changes, so the lists redraw on a line change and not on every frame. A tap on a timed
  line seeks `lyrics lead` seconds early (1 s, kept in UserDefaults, a Settings stepper) and starts playing,
  as the web does.
- **Transposition is kept per song in UserDefaults**, folded into -5...+6. It moves what is read: the
  chords and lyrics tabs and the diagrams; the files are never rewritten.
- **Chords and tab are monospace, scrolled sideways, never wrapped**, since alignment is the data. The
  sideways scroll is nested in the vertical one: a two-axis `ScrollView` centres short content.
- **Tab is drawn, not printed**: a system is a `Canvas` staff on the ASCII's column grid (one monospaced
  advance per character), string labels in the accent colour, frets bold with the string line cut around
  them, bar lines across the strings. Each system scrolls sideways on its own, so a long riff does not push
  the rest of the page. What comes before the first system (title, tuning, legend) folds behind a
  "Show header" button; VoiceOver reads a system string by string, frets only, never the dashes.
- **The popover, not a menu, holds the song menu's controls** (`.presentationCompactAdaptation(.popover)`); it is as
  wide as the screen allows, up to 400 pt. The transposition sits in the song's Info tab. The metronome sits in the
  take panel and lives in `AppModel`, so its click outlives any screen and a stop by the system (a call, a route
  change) clears its running state.
- **Texts are plain files of the song folder.** Saving writes the file, then rewrites the `SongFile` row in
  one transaction; an emptied text removes both. After a lyrics edit, chords that already carry timecodes
  are re-timed onto the new lyrics with `LRC.mergeTimedSheet`; untimed chords are left alone.
- **Sheets** are copied into `sheets/` under a unique name and ordered by `position`, which is the
  sidecar's order for imported ones; PDFs go through PDFKit, images through a zooming scroll view over a bounded
  decode (4096 px on the long side), made off the main actor, and MusicXML scores through Verovio (`docs/score.md`).
- **Tags are edited on the row only.** The copy's `song.yaml` gets only the uuid; a re-import takes the
  sidecar's tags when it has some and keeps the row's own otherwise.
- **LRC import** merges a picked `.lrc` into the lyrics with `LRC.merge`, writing `{{MM:SS.cc}}` codes as the web does.

## Chord diagrams

`Logic/ChordDiagrams.swift` is the only file that reads `Resources/ChordsDB/guitar.json`, the guitar data of
`@tombatossals/chords-db` (MIT, licence beside it). The JSON is cut to what is drawn: no MIDI, and only each
chord's first fingering. The lookup follows `chordDiagram.ts` (`ROOT_TO_DB`, exact quality, slash form, bare
triad) and answers nil for what is not a chord; a card with no diagram shows its name alone.

## Playback

- **The seam follows the player, not its own flag.** `TakePlayer.onPause` reports every pause, whoever asked
  (another player taking the floor, an interruption, a route change), so the play button never shows
  "playing" over silence.
- **A button a thumb must hit is 44 pt**, and an icon-only one is named for VoiceOver: the play buttons,
  the rec button, the take panel and its metronome, the Info tab's transposition, the tab chips. `UITests/TargetTests.swift` measures them on the
  simulator and `PlayTests.swift` taps the real play button.

## Moments and markers

- **Detection is a button on each visit**, off when a page opens and never kept
  (`packages/ui-rehearsal/docs/recordings.md`). `MomentDetector` runs over the take's stored envelope;
  the floor is an absolute level (15% of the peak until moved), the silence 0.5 to 10 s, and every move of
  a slider runs the detector again in memory. `Logic/TakeMoments.swift` holds that state so tests reach it
  without a view.
- **A recording is its take's file name**, as the store's rules name it. A moment keeps the slice of the
  envelope it covers; there is no clip, no consolidation and no sharing, so a moment plays as a span of
  the take: a detected span once, a saved moment in a loop.
- **A moment cannot outlive its take here.** The store lets a moment stay on its clip when its recording
  goes; the app cuts no clip, so deleting a take deletes its moments (and their markers) as well, and the
  confirmation says so.
- **Pins are the recording's own** (`momentId` empty): named at the playhead, tap to seek, deleted with
  the take by the store's rule. A moment's own pins are not offered.
- **A saved span is not saved twice**; an empty title becomes "Moment m:ss", an empty pin name "Marker".
- **`UITests/MomentsShot.swift` takes screenshots** of the page when `TEST_RUNNER_SHOT_DIR` is set, over a
  take seeded by the debug launch argument `-SeedTake <audio path>`; it skips otherwise.
