# Scores on the Sheets tab

A song's Sheets tab takes MusicXML files (`.musicxml`, `.xml`, and the compressed `.mxl`) beside its PDFs and
images, and draws them as notation you can play, transpose and zoom. A song folder written by k7 with a score
in `sheets/` opens with the same notation it had there.

## Verovio draws, in a web view

- **Verovio is the engraver**, as in k7: it keeps a clef change where the file puts it (a piano's left hand
  moving between treble and bass), which is what a musician reading from the screen needs most. iOS has no
  MusicXML reader of its own. LGPL-3.0-or-later, used as published, its licence beside it
  (`App/Resources/Score/LICENSE-verovio.txt`).
- **Its JavaScript build in a `WKWebView`, not its C++ compiled in.** Verovio writes SVG, which iOS draws only in
  WebKit; the JS build is one self-contained file (its wasm inside, about 7 MB), bundled, so a score opens offline.
  A native build would still need the web view to show what it draws, and adds a C++ build to keep.
- **The page is the app's own** (`App/Resources/Score/score.html`, `score.js`): it engraves, lights notes and
  reports taps. The Swift side (`Screens/Song/ScoreSheet.swift`) reads the file, cuts parts and owns the controls.
- **The module compiles once per score opened**, about a second on a phone; a spinner covers it. Keeping one web
  view alive across scores would save that second at the cost of 7 MB held while no score is shown.
- **Dark mode inverts the drawn pages**: Verovio draws black on transparent, and an inverted page reads as a
  dark sheet without a second set of colours.

## The app plays, Verovio times

- **Verovio writes the score as MIDI; `AVMIDIPlayer` plays it** through the SONiVOX General MIDI bank
  (`sonivox.sf2`, 1.3 MB, Apache-2.0). `AVMIDIPlayer` takes SF2 or DLS, not k7's compressed SF3.
- **The player is a seam** (`Seams/ScorePlaying.swift`, `Live/MIDIScorePlayer.swift`): it needs a route, so tests
  use the fake. The app model owns it, so the audio session is given back only once neither player sounds.
- **Playing a score pauses the song**, since two unrelated tempos at once help nobody.
- **The sounding notes are lit**, about thirty times a second, from `getElementsAtTime` on the drawn file; the
  column scrolls when they leave it. A tapped note is where playback jumps to.

## Parts, transposition, zoom

| choice | why |
|---|---|
| a score opens with every part; a part menu shows when there are two or more | a musician reads their own line alone |
| the menu changes what is drawn, never what is played | the part read alone is still heard in its arrangement |
| the whole file is loaded for the MIDI, then the part for the page | a toolkit holds one file at a time; both share one timing |
| an unnamed part is "Part n" | many exports leave `part-name` empty |
| transposition is Verovio's, in semitones, ±12 | the drawing and the sound move together |
| it opens at 50 % on a phone, 75 % on a tablet, 100 % wider | a phone's column fits a line at half size |
| a new width wraps the systems again | a rotation is a new layout, never a page turn |
| the controls float in the bottom-right corner | a bar would take a system's height on a phone |

## A compressed score is opened here

An `.mxl` is a zip whose `META-INF/container.xml` names the score inside it. `Logic/MusicXML.swift` reads the
archive's directory and inflates the entry with the Compression framework, since the Swift side needs the score
as text to list and cut its parts. One without a container is read by its one `.musicxml` or `.xml`.

## Only a device can verify

- How long the module takes to compile on the oldest supported phone, and whether a long score stutters while lit.
- Whether the SONiVOX bank sounds acceptable through the phone's speaker and over Bluetooth.
- That a score playing while the screen locks keeps sounding (the `audio` background mode covers it).
