# Text: chords, timecodes, LRC, tablature

`Packages/RehearsalText` is pure Swift with no dependency. It is a port of `packages/lyrics`
(`src/chords.ts`, `src/lrc.ts`) and `packages/tablature` (`src/tab.ts`), with their tests ported case
for case, so a song reads the same on the phone as in k7's web front. The rules themselves are argued
in `packages/lyrics/docs/chords.md`, `packages/lyrics/docs/timecodes.md` and
`packages/tablature/docs/tablature.md`; this page holds only what the port decided.

## A known chord vocabulary

A chord is a root plus qualities, extensions and alterations from a fixed list, never "any letters".
That is what keeps `Bad`, `Cage` and `Fed` out of the chord lines. A looser test would turn lyric
lines into chord lines and transpose words.

## Spacing is kept

`transposeLine` moves chords token by token and returns the whitespace between them untouched. The
alternative, re-aligning, would rewrite a line the user typed. A chord that changes width can drift
its column; that is accepted.

## Regexes stay regexes

The TS is regex-heavy and its behaviour is the spec, so the port keeps the same patterns on
`NSRegularExpression` through one small wrapper (`Rx.swift`). Its offsets are UTF-16, like JS's, and
patterns are written ASCII-explicit (`[0-9]`, `\z`) because ICU's `\d` and `$` differ from JS's. A
Swift `Character` split is avoided on text: `"\r\n"` is one Character, so lines split by regex.

## One matcher, equal arithmetic

The LRC merge aligns by edit distance and compares scores for equality when walking back. The Swift
keeps the TS's arithmetic order, and a Levenshtein over UTF-16 units written here (about twenty lines)
instead of a library, since no Swift one is worth a dependency. Sorting timed lines is made stable by
hand, as JS's is.

## Timecodes live in the text

`{{MM:SS.cc}}` stays in the sheet, as in the web app, so a song folder written by either app is read
by the other. A code is stripped, with its one space, before a line is read.

## Names, no I/O

`SongFolderLayout` names the files of a song folder (`lyrics.txt`, `tabs.txt`, `chords.txt`,
`sheets/`, `song.yaml`, `original.*`) and nothing else: reading them belongs to the store and the app.

## Departures from the TS

- **A tab line is read as pieces, not tested whole.** A piece is an optional string label (`e`, `f#`, `D`) and a
  body of dashes, frets, bars and techniques; whitespace ends a body. Tabs are often written two systems to a
  line (`e ----0----     e ----2----|`) with words after a string (`x2`, `let ring`), and a whole-line test then
  reads the line as prose. Pieces side by side come out as systems one after the other, left first, each on its
  own column grid; the words after a piece, up to the next piece, are that string's comment
  (`TabSystem.comments`), so `x2` between two systems stays on the string it was written on. A line that does
  not start with a piece is text, kept where it stands between systems. `:` belongs to a body, so repeat signs (`::`) are
  drawn in the system rather than read as its comment.

- A time that is not finite formats as zero: the TS returns garbage there, Swift's `Int` would trap.
- Maps are ordered arrays (`[LineTime]`), since the order of a `Map` is part of what `lineAt` returns.
- `{ok:false, reason:"empty"}` is the case `LrcTimecoding.empty`.
