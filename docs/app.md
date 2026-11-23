# The app shell

The K7 REC app is a SwiftUI shell over three local packages (text, audio, store). It owns no logic
of its own: screens read and write through small protocols, and the packages are wired in behind them.

## Project definition

- **XcodeGen, `App/project.yml` checked in, the `.xcodeproj` generated and git-ignored.** A hand-kept
  `.pbxproj` merges badly and four branches touch this tree at once. XcodeGen (MIT, a dev tool, not
  linked into the app) is any `xcodegen` on the PATH; run `xcodegen generate` in `App/`; it writes `K7Rec.xcodeproj`.
- **The Info.plist is generated from `project.yml`** (`info:`), so one file holds every key: microphone and
  local network usage strings, `UIFileSharingEnabled` (takes and songs show in the Files app), in-place
  document opening, and the `audio` background mode so a take survives a locked screen.
- **iOS 26 and later only, SwiftUI lifecycle, iPhone and iPad, all orientations on iPad.** The controls are
  Liquid Glass (`glassEffect`, `.glass` buttons), which iOS 26 draws itself; an earlier system is not supported,
  so nothing imitates the glass. The packages keep their own, lower targets.
- **The app is K7 REC, bundle id `rocks.k7.rec`, iCloud container `iCloud.rocks.k7.rec`.** The Xcode project,
  the targets and the module are `K7Rec` (`K7RecTests`, `K7RecUITests`); the packages keep their `Rehearsal`
  names, which no user sees. The version is `MARKETING_VERSION` in `project.yml`, read by Settings from the bundle.
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
  holding `original.<ext>`, titled by its tags, else its file name. The tags are the common ones, else
  the Vorbis comments (`TITLE`, `ARTIST`) that FLAC, Ogg and Opus carry and AVFoundation keeps apart.
- **A song can be made without audio** (Add song → New song, a title and an artist): its folder holds
  only the `song.yaml` that `SongFolder.sidecar` writes, named like a copy, and it opens at once. Its
  texts and sheets come from the tab switch's + tabs. With no recording, the song screen has no waveform
  and no play button, and its menu has no LRCLIB, LRC timing or stems: lyrics are typed, never looked up.
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
speaker is picked up by the microphone; headphones are not), and K7 REC in an audio file's share sheet.

## Look

- **The K7 design system, Rec theme** (the "K7" design system artifact): warm black ground, cream text, orange
  accent, light-blue highlights. `Screens/K7Tokens.swift` is its "SwiftUI tokens" page copied unchanged and
  replaced whole when the tokens change; screens read colours from `k7`, never a literal, so a token change
  is one file. `Screens/Theme.swift` holds what the system builds from them: the backdrop (two glows, two
  wave lines, the only glow allowed), cards, wells, the header, the empty state.
- **One backdrop, always moving** (`Screens/Backdrop.swift`), behind the tab stacks, which are see-through, so a
  single view animates. Silent, its two wave lines drift apart (one pass in 60 s and 90 s); while a song or a
  take plays, or a take records, they follow the level heard (`AppModel.soundLevel`: the player's output, metered
  after its gain, or the microphone's input), from 1× at silence to 2× at full level on the decibel scale, and
  speed up to 9 s and 13 s. The motion is stepped frame by frame from the last state, so a change of speed
  never jumps, and the height rises in a tenth of a second and settles in half a second. The lines are the
  design system's own, kept as a mean and two harmonics each. Reduced motion stills them.
- **Dark only.** The tokens define no light theme, so the root forces the dark scheme.
- **Platform sizes follow the system's rules** (`Metrics`): side margin 16 on iPhone, 40 on iPad, 64 on the
  Mac; tab 86 by 64 on iPhone, 112 by 68 wider; wells about 30% shorter on iPhone; the view switch shares the
  full width on iPhone and has 104 pt segments wider. What does not fit on iPhone (Info, the instrumental
  switch) moves into the song's "…". Settings is one column on iPhone, two on iPad and the Mac.
- **Glass floats, cards sit.** Glass is for what floats over the ground (the tab bar, header actions, the
  view switch); inside a card or the take panel, controls are quiet `fillControl` pills so glass never stacks.
  Red means recording or stopping, nothing else.
- **Saved moments are called highlights** on screen, as in the design; "Detect moments" keeps its name.

## Screens

- **Songs, Takes, Settings under one floating glass bar**, centred at the bottom on iPhone, iPad and the Mac
  alike, with the rec button beside it (the K7 TabBar). It is the app's own bar, not a `TabView`: the system
  bar sits at the top on iPad and in the title bar on the Mac, where the design has none. The three tabs stay
  alive behind the one in front, so a switch keeps their pages; picking the tab in front again goes back to
  its list. Content scrolls under the bar.
- **A song is one column of views** (`packages/ui-library/docs/songPlayer.md`): it opens on chords (with their
  diagrams, "Chord diagrams" below), else lyrics, else sheets, picked from the glass view switch under the waveform.
  The switch always holds Chords, Lyrics, Sheets and Tab, those with content first: one with nothing yet comes
  after them with a small plus, and picking it
  asks for its content (the text editor, or the sheet picker), then opens it once saved; Info and the instrumental switch
  sit at the switch's right on iPad and the Mac, in the song's "…" on iPhone. Play and "…" share the bar's
  right capsule. Back is the navigation bar's.
- **Recording is the round glass button beside the tab bar**, the same on every screen. A tap starts a take
  where the person is, with no change of screen; while the Songs tab shows a song the take belongs to it
  (`AppModel.songForTake`). While a take runs, the button's glass is tinted by the input level on the
  decibel scale (`Logic/LevelMeter.swift`): clear at silence, fading in to green by -20 dB, orange at -6 dB,
  red at full level, so a glance tells whether the take is too quiet or clipping. The level is followed like a
  meter's needle (`LevelMeter.follow`): every 50 ms, only while a take runs, it rises half the way to the new
  level and falls 15%, and each step is animated, so the colour glides instead of flickering; a rest or a
  stop fades it out. The dot pulses whenever the panel is closed, so recording is never
  invisible, and a tap opens the take panel as a sheet. The metronome is a menu in the panel's header,
  reached while idle from the button's context menu. The screens stay usable under a running take.
- **The panel draws the running take**: clock, input level on a decibel scale (`Logic/LevelMeter.swift`), and
  the last 30 seconds of its envelope, re-levelled to the loudest bucket so far (`Logic/LiveTake.swift`).
  The well scrolls at display rate, not in 200 ms steps (`Screens/LiveWaveform.swift`): its bars are bins
  pinned to take time (a bin always holds the same buckets), so a bar keeps its height as it slides instead of
  changing with every regrouping of the window; and between two buckets a clock runs the scroll on from the
  newest one's arrival, for at most one bucket, so the newest bucket slides in from the right edge.
- **The highlights found so far are spans on that waveform**, with no list and no count. The detector runs
  at its default floor and silence; a span still open counts once it is 4 seconds long, so a span can change or
  vanish while the take grows. A tap on a span rests the take first, so the speaker is never recorded, zooms
  the well until the span fills about 80% of it and plays it in a loop from the take's raw file (readable
  while it is written, flushed first) at the take's playback gain; the filled Resume button zooms out and
  goes on recording. Stop ends the take, closes the panel and opens the saved take's page in the Takes tab
  (`AppModel.stoppedTake`), which gives the final list.
- **Lyrics come from LRCLIB at import, and again from the song menu.** A song that arrives without lyrics
  (a file, a folder, a server file) is looked up on lrclib.net by title, artist and, for a file,
  its duration; timed lyrics are saved in the app's own timecodes, else the words alone. Only those three
  values leave the device, and only here. A failure never blocks the import: one notice says which songs
  got nothing, and the song menu's "Download lyrics from LRCLIB" repeats the lookup. A song that already
  has lyrics only gets timing from it: its words are never replaced.
- **The header keeps the design's gap under the status bar**: 10 pt on iPhone, 22 on iPad, 28 under the Mac's
  title bar (`Metrics.top`). The system places navigation bars from the window's safe area, which SwiftUI
  padding does not move, so the gap is the root controller's extra top inset.
- **Every screen's header is the navigation bar, dense**: back when pushed, the K7 Rec mark at 26 pt, the
  title and its subtitle (a count, the artist, the date) as one leading item, the screen's actions at the
  right in one glass capsule. The system title is removed so it is not drawn twice. A bar item is 36 pt tall
  whatever its label asks for, and the bar adds about 14 pt to its label's width, so play and the menu ask
  for 30 pt to be 44 pt wide; on iPhone the title is capped at 170 pt so the actions are never pushed into the
  bar's overflow.
- **Another app can feed the import**: the app declares `public.audio` as a document type it views, at the
  Alternate rank (it never becomes the default player), so iOS lists K7 REC in an audio file's share sheet and
  Open in, and the Mac in Finder's Open With. The URL goes through the same import as a picked file and the new
  song opens on its page. A file iOS could not open in place arrives as a copy in `Documents/Inbox`, which is
  removed once imported. No share extension: it would run apart from the app's store and its iCloud container;
  the Mac's Share menu, which lists only extensions, does not offer K7 REC.
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
- **Transposition is kept per song in UserDefaults**, folded into -5...+6. It moves what is read (the
  chords and lyrics tabs and the diagrams; the files are never rewritten) and what is heard: the song, its
  instrumental and its stems play pitch-shifted at the same tempo (`docs/audio.md`), a take as recorded. The fold
  keeps the shift at half an octave at most, where the shifter sounds cleanest. A change is heard at once.
- **Chords and tab are monospace, scrolled sideways, never wrapped**, since alignment is the data. The
  sideways scroll is nested in the vertical one: a two-axis `ScrollView` centres short content.
- **Tab is drawn, not printed**: a system is a `Canvas` staff on the ASCII's column grid (one monospaced
  advance per character), string labels in the accent colour, frets bold with the string line cut around
  them, bar lines across the strings. A string's comment (`x2`, `let ring`) stands in a column at the staff's
  right, italic, on that string's line, so it reads where it was written (`docs/text.md`). Systems written side
  by side, or one after the other with only blank lines between, stand side by side while they fit the card and
  wrap to the next row when they do not; a line of text or a section between two systems keeps them on rows of
  their own, so the text stays between the parts it separates. The card's width is read from the scroll view,
  since the card grows with what it holds. A system wider than the card scrolls sideways on its own, so a long riff does not push
  the rest of the page. What comes before the first system (title, tuning, legend) folds behind a
  "Show header" button; VoiceOver reads a system string by string, frets and comment, never the dashes.
- **Adding is done where the content goes, editing from the song menu.** A missing text or the first sheet is
  added from its "+" tab, another sheet from the "+" beside the Sheets tab's chips; the song menu lists only
  "Edit" for the texts the song has, so no action has two places. A lone sheet has no chips: a row naming the
  one sheet there is says nothing, so its remove and expand buttons float over it and "Add another sheet" is in
  the song menu.
- **The popover, not a menu, holds the song menu's controls** (`.presentationCompactAdaptation(.popover)`); it is as
  wide as the screen allows, up to 400 pt. The transposition sits in the song's Info tab. The metronome sits in the
  take panel and lives in `AppModel`, so its click outlives any screen and a stop by the system (a call, a route
  change) clears its running state.
- **The text editor takes 80% of the window each way** on iPad and the Mac, where a form sheet is too small for
  a chord sheet's columns. The sizing API is given no container size, so `WindowFraction` reads the key window's
  bounds. On iPhone a sheet already spans the screen.
- **Texts are plain files of the song folder.** Saving writes the file, then rewrites the `SongFile` row in
  one transaction; an emptied text removes both. After a lyrics edit, chords that already carry timecodes
  are re-timed onto the new lyrics with `LRC.mergeTimedSheet`; untimed chords are left alone.
- **Sheets** are copied into `sheets/` under a unique name and ordered by `position`, which is the
  sidecar's order for imported ones; PDFs go through PDFKit, images through a zooming scroll view over a bounded
  decode (4096 px on the long side), made off the main actor, and MusicXML scores through Verovio (`docs/score.md`).
  The picked sheet goes full screen from the expand button at the top right of the tab, a full-screen cover
  with one button that shrinks it back, so a sheet is read without the song screen's header and switch.
- **Title, artist and tags are edited in the Info tab, on the row only**, saved as each is made (a field on
  return or on leaving the tab, a tag chip at once); an emptied title keeps the one before. The copy's
  `song.yaml` gets only the uuid, so a re-import reads title and artist from the source again; it takes the
  sidecar's tags when it has some and keeps the row's own otherwise.
- **The Info tab is the settings cards**: the rows of `SettingsRows.swift`, shared with Settings, and tags as
  chips that wrap, each with its remove button.
- **LRC import** merges a picked `.lrc` into the lyrics with `LRC.merge`, writing `{{MM:SS.cc}}` codes as the web does.

## Chord diagrams

`Logic/ChordDiagrams.swift` is the only file that reads `Resources/ChordsDB/guitar.json`, the guitar data of
`@tombatossals/chords-db` (MIT, licence beside it). The JSON is cut to what is drawn: no MIDI, and only each
chord's first fingering. The lookup follows `chordDiagram.ts` (`ROOT_TO_DB`, exact quality, slash form, bare
triad) and answers nil for what is not a chord; a card with no diagram shows its name alone.

- **Diagrams belong to the chords view, not to a tab of their own.** On iPad and the Mac every chord the song
  uses, transposed, stands in a 176 pt column at the right of the chords, so a glance finds a shape while the
  sheet scrolls. On iPhone there is no width for it: each chord in the sheet is a button that opens its diagram
  in a popover pointing at it. A chord line is cut into runs (`SongText.chordRuns`), chords and the gaps between
  them, and laid side by side in the same monospace, so the columns stay where the text put them.

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
