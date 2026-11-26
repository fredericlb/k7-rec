# Mac

The Mac app is the iPhone app built as Mac Catalyst: one target, one bundle id (`rocks.k7.rec`), one
code base, so the library, the recorder, the stems and the sync are the same code.

## Choices

- **Catalyst, not a second native target.** Every screen, the packages and the tests are shared. A native macOS
  target would mean a second UI layer; it is the next step if the Catalyst look is not enough.
- **The bundle id is not derived for the Mac** (`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER` is off), so the Mac
  and the iPhone are one app to iCloud and share the container `iCloud.rocks.k7.rec` (`docs/sync.md`).
  A song or a take made on one appears on the other through the records.
- **The sandbox is on**, with what the app uses: outgoing network (FTPS, SFTP, LRCLIB), the microphone, files the user
  picks, iCloud. Nothing else is asked for.
- **The separation model is in the app**, as on the iPhone (`docs/stems.md`); the stems it makes sync like any file.
- **The song's ⋮ is a Menu on the Mac**, a popover on the iPhone: a popover anchored in a Catalyst toolbar does not
  open. Both lay out the same `SongActions`, so the two cannot drift.
- **The Mac is the iPad layout in a window**: the same floating tab bar and rec button at the bottom, the
  window's own title bar above. The menu bar has a Recording menu with Record (⌘R) and the metronome.
- **Playback uses the `.playback` category on the Mac.** With `.playAndRecord` the engine reports a configuration
  change as it starts, and the player, which pauses on a route change, stopped at once. A take in progress keeps
  `.playAndRecord`; and if a configuration change still arrives while a song plays, the Mac restarts the engine
  and goes on from the same frame instead of pausing (the phone pauses: it means the headphones were unplugged).
- **Every presentation is given the model again.** Catalyst may build a sheet, popover or full-screen cover
  outside the presenting view's environment (a sheet with its own sizing, a full-screen cover), and a view
  reading `AppModel` there traps; each presentation's content therefore carries `.environment(model)` itself.
- **The deployment target is macOS 26**, the Catalyst counterpart of iOS 26, which Liquid Glass needs.

## Dev loop

`App/dev-mac.sh` is the Mac's live reload: it builds the Debug Catalyst app into `App/build/dev`, runs it, and on
every save under `App/Sources`, `App/Resources` or a package's `Sources` rebuilds (about 5 s) and relaunches it.
Its arguments go to the app, so the debug launch arguments land on the screen being edited
(`App/dev-mac.sh -OpenFirstSong YES -OpenTab chords`, `docs/app.md`).

- **Rebuild and relaunch, not code injection.** It needs nothing beyond Xcode and XcodeGen; the state the app
  had (the open song, the scroll) is lost at each relaunch, which the launch arguments make up for.
- **A failed build keeps the running app** and prints the compiler's errors; the next save tries again.
- **A file added or removed, or `project.yml` changed, runs `xcodegen generate` first**: XcodeGen lists every
  source in the project, so a new file would otherwise not be compiled.
- **The dev build is `rocks.k7.rec`, the real bundle id, run from `App/build/dev`**, so it reads the same library
  and iCloud container as an installed K7 REC, as an Xcode Run does. A dev bundle id would need its own App ID
  and iCloud provisioning. The script refuses to start while another K7 REC runs, and only ever quits the
  process it launched; nothing is copied to `/Applications`.
- **Polling, not FSEvents**: a `find -newer` every half second over a few hundred files, so no watcher tool is
  installed.

## Only a device can verify

- Signing: the Mac must be registered on the developer account, and the iCloud capability set up for the Mac.
- A record travelling between the Mac and the phone, and the container's folder in Finder.
- The microphone prompt, the Local Network prompt (a file server on the LAN) and the look of the iPhone layout in a window.
