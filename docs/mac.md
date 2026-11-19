# Mac

The Mac app is the iPhone app built as Mac Catalyst: one target, one bundle id (`se.frediver.rehearsal`), one
code base, so the library, the recorder, the stems and the sync are the same code.

## Choices

- **Catalyst, not a second native target.** Every screen, the packages and the tests are shared. A native macOS
  target would mean a second UI layer; it is the next step if the Catalyst look is not enough.
- **The bundle id is not derived for the Mac** (`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER` is off), so the Mac
  and the iPhone are one app to iCloud and share the container `iCloud.se.frediver.rehearsal` (`docs/sync.md`).
  A song or a take made on one appears on the other through the records.
- **The sandbox is on**, with what the app uses: outgoing network (FTPS, SFTP, LRCLIB), the microphone, files the user
  picks, iCloud. Nothing else is asked for.
- **The separation model is installed per device.** On the Mac it goes in the app container's `Documents/Models`
  (`~/Library/Containers/se.frediver.rehearsal/Data/Documents/Models`); the stems it makes sync like any file.
- **The song's ⋮ is a Menu on the Mac**, a popover on the iPhone: a popover anchored in a Catalyst toolbar does not
  open. Both lay out the same `SongActions`, so the two cannot drift.
- **The rec button is an item of the window's title bar toolbar**, right of the tabs. The tab bar puts its tabs in
  that `NSToolbar` and owns its delegate, so `MacRecToolbarItem` stands in front of that delegate, forwards
  everything to it and adds one item; it re-joins if the tab bar replaces the toolbar. A SwiftUI view drawn up
  into the title bar is not an option: the title bar takes its clicks. The LED is the item's image, redrawn
  only when its shade changes. A toolbar item has no context menu, so the Mac reaches the metronome from a
  Recording menu in the menu bar, beside Record (⌘R).
- **Playback uses the `.playback` category on the Mac.** With `.playAndRecord` the engine reports a configuration
  change as it starts, and the player, which pauses on a route change, stopped at once. A take in progress keeps
  `.playAndRecord`; and if a configuration change still arrives while a song plays, the Mac restarts the engine
  and goes on from the same frame instead of pausing (the phone pauses: it means the headphones were unplugged).
- **The deployment target is macOS 14**, matching the packages.

## Only a device can verify

- Signing: the Mac must be registered on the developer account, and the iCloud capability set up for the Mac.
- A record travelling between the Mac and the phone, and the container's folder in Finder.
- The microphone prompt, the Local Network prompt (a file server on the LAN) and the look of the iPhone layout in a window.
