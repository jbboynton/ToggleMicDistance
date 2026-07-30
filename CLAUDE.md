# ToggleMicDistance

A macOS menu bar app that toggles a desk mic between a close
position (about an inch) and a far position (about a foot), switching the
Audio Hijack processing chain to match and animating the menu bar icon.

## Layout

| File | Role |
| --- | --- |
| `AppDelegate.swift` | Status item, clicks, Settings window, device presence |
| `MenuBarIcon.swift` | The animated icon, composed from two SF Symbols |
| `IconColors.swift` | Icon color model, system accents, hex parsing |
| `MicDistance.swift` | State, preferences, the generated shell script |
| `AudioDeviceWatcher.swift` | CoreAudio presence watching |
| `AudioHijackWatcher.swift` | Is Audio Hijack running, and hiding it again |
| `SettingsView.swift` | Settings pane |
| `Tools/release.sh` | Build Release and install to /Applications |
| `Tools/GenerateAppIcon.swift` | Regenerate the app icon PNGs |

## Build and install

There are **no code signing identities** on this machine, so Xcode's
Archive then Distribute flow offers nothing usable (App Store Connect and
Direct Distribution both need a certificate). The app is ad hoc signed,
which is fine because it is never quarantined.

```bash
Tools/release.sh      # build Release, replace /Applications copy, relaunch
```

Do not filter build output down to `error:` only. That hid a real
concurrency warning for several rounds. `release.sh` does not filter.

Debug flags, useful because the app has no Dock icon:

```bash
ToggleMicDistance.app/Contents/MacOS/ToggleMicDistance --open-settings
ToggleMicDistance.app/Contents/MacOS/ToggleMicDistance --dump-settings out.png
ToggleMicDistance.app/Contents/MacOS/ToggleMicDistance --dump-icons out.png
```

`--dump-settings` renders the Settings pane offscreen with
`ImageRenderer`, which is how to check layout without a screenshot
(`screencapture` is blocked, no Screen Recording permission). Interactive
controls render as yellow placeholders; that is expected.

`--dump-icons` does the same for `IconStateGallery`: every icon state,
blown up, in Light and Dark. Use it after touching `MenuBarIcon.swift`;
it is the only way to see a state like "Audio Hijack quit while the app
was switched off" without staging it by hand.

## Icon states

The icon says one of three things, and `MicDistanceModel.iconState`
decides which, so the icon and the menu's status line can never disagree:

- **Normal.** `microphone.fill`, colored per Settings. The menu says
  "Mic is up close" or "Mic is set back".
- **Audio Hijack not running.** `waveform.slash` takes the mic's place,
  in the menu bar's own color. The menu says "Audio Hijack isn't
  running". Clicking still launches Audio Hijack, and asserts the current
  position rather than flipping it: the icon isn't showing a position, so
  flipping one nobody can see would make the icon jump to the opposite of
  what was expected.
- **Switched off.** `microphone.slash.fill`, and every part at two thirds
  of the menu bar's color. The menu says "Currently inactive".

In both of those states the struck-through glyph is drawn much larger,
about the size of the person, because there the glyph is the message and
the person is only context. The person is drawn close in both, and goes
back to reporting the real position the moment the icon means something
again.

Switched off wins over Audio Hijack being gone. Turn it off from the
menu's **Disable Temporarily**, or with an Option-click on the icon; the
setting persists across launches, and clicking a switched off icon only
pulses it.

## Things that will bite

- **Xcode 26 sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** Plain
  helper types get main actor isolation whether you want it or not. The
  CoreAudio helpers are marked `nonisolated` for this reason.
- **App Sandbox is off** (`ENABLE_APP_SANDBOX = NO`). It has to be: the
  app spawns a shell script, and the script drives Audio Hijack.
- **A stale sandbox container** can make the `defaults` CLI and the app
  read different preference stores. If `defaults read` disagrees with
  observed behavior, check for `~/Library/Containers/<bundle id>`.
- **`Settings` scenes are unreachable in an agent app.** No menu bar
  means no `showSettingsWindow:` route, so `AppDelegate` owns a plain
  `NSWindow` instead. The SwiftUI `Settings` scene is an intentionally
  empty placeholder.
- **Menus render SF Symbols as template images**, discarding tint. The
  color dots in the picker are drawn `NSImage`s with
  `isTemplate = false`.
- **macOS 26 gives some menu items an image you never asked for.**
  "Settings…" gets a gear and "Quit" gets a symbol, assigned at
  `NSMenuItem` creation. Titles line up per section, so one item with an
  image indents its neighbors' text. `item.image = nil` clears it and
  sticks, which is how the menu's titles stay flush left.
- **A SwiftUI state change and its undo in one run loop turn animate
  nothing.** Only the net change survives, so the in-between frame is
  never drawn. `MenuBarIcon.pulse()` awaits a sleep between the two
  halves for exactly this reason.
- **Spotlight offers stale Debug builds.** Every build registers its
  DerivedData copy with LaunchServices, and launching one of those puts an
  out of date icon in the menu bar that looks like your change didn't
  take. `release.sh` unregisters them after installing;
  `DerivedData/.metadata_never_index` keeps Spotlight out as well. An
  Xcode IDE build re-registers, so re-run `release.sh` if a phantom
  reappears.
- **Handing a document to a hidden app un-hides it.** `open -g -j` keeps
  Audio Hijack hidden on the launch that starts it, but every later
  `.ahcommand` un-hides it and its session list lands at the front
  (measured 2026-07-30). Nothing in the Audio Hijack JavaScript API can
  close that window, so `MicDistance.keepAudioHijackHidden()` watches for
  it and calls `NSRunningApplication.hide()`. That call returns `false`
  and works anyway, so don't branch on its result.
- **The icon geometry is duplicated** in `Tools/GenerateAppIcon.swift`,
  because a standalone script cannot import the app target. Retune the
  icon in `MenuBarIcon.swift`, mirror the constants, re-run the script.

## The switching script

Lives outside the bundle at
`~/Library/Application Support/ToggleMicDistance/set-mic-distance.sh` so
it can be edited without rebuilding. The app writes it only when
missing.

It carries a `# template-version:` marker. When the app ships a newer
template, Settings offers **Replace with Latest**, which keeps the old
copy as `.bak`. **Never overwrite this file silently**; it is meant to be
user editable.

See the `audio-hijack-scripting` memory for the Audio Hijack API, which
is not what you would guess.
