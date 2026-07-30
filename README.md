# ToggleMicDistance

ToggleMicDistance is a small macOS menu bar app for desk mic users.
It flips your mic setup between two positions with one click:

- **Close:** the mic is about an inch from your mouth.
- **Far:** the mic is about a foot away.

Each position needs different audio processing. When you click the
icon, the app tells [Audio Hijack](https://rogueamoeba.com/audiohijack/)
to switch its processing chain to match. The menu bar icon animates to
show which position is active, so you always know how your mic sounds
to other people.

The icon also warns you when something is wrong. If Audio Hijack is
not running, the icon shows a struck-through waveform. If you turn the
app off for a while, it shows a struck-through mic.

> [!IMPORTANT]
> You need Audio Hijack installed for this app to be useful. The app
> drives it with `.ahcommand` script files.

## Install and use

Build from source with Xcode 26 or newer, on macOS 26 or newer:

```bash
Tools/release.sh
```

This builds the Release version, installs it to `/Applications`, and
relaunches it. There is no signed download, because the app is only
ad hoc signed.

Once it runs, you will see a mic icon in the menu bar:

- **Click** the icon to flip between close and far.
- **Right-click** to open the menu. It shows the current state and has
  items for Settings, Disable Temporarily, and Quit.
- **Option-click** to turn the app off or on without opening the menu.

If Audio Hijack is not running, a click launches it and asserts the
current position instead of flipping it.

## Configuration

Open **Settings** from the icon's menu. You can set:

- **Icon colors.** Each part of the icon can follow the system accent
  color, match the menu bar, or use a fixed color (picker or hex).
- **Mic interface.** Pick the audio device the app should watch. Pick
  the physical interface, not a Loopback virtual device.
- **Startup.** Launch at login, and start the Audio Hijack session
  when the interface connects.
- **The switching script.** Buttons to reveal, open, or copy the path
  of the script described below.

The app writes the script that does the actual switching to:

```
~/Library/Application Support/ToggleMicDistance/set-mic-distance.sh
```

You can edit this file freely; the app never overwrites it on its
own. When the app ships a newer template, Settings offers **Replace
with Latest** and keeps your old copy as `.bak`.

> [!TIP]
> The app has no Dock icon, so it also accepts command line flags for
> debugging: `--open-settings` opens Settings, `--dump-settings` and
> `--dump-icons` render the UI and every icon state to a PNG.

## Contributing

There is no CONTRIBUTING.md yet. Open an issue or a pull request.

Notes on the build environment:

- Built with Xcode 26 on macOS 26. The project sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so plain helper types
  are main actor isolated unless marked `nonisolated`.
- The App Sandbox is off on purpose. The app spawns a shell script,
  and that script drives Audio Hijack. It cannot do this from inside
  the sandbox.
- The app is ad hoc signed. `Tools/release.sh` needs no signing
  identity, but the Xcode Archive flow will not work without one.
- The app depends on Audio Hijack and on macOS menu bar behavior, so
  it is not portable to other platforms.

> [!WARNING]
> Do not filter build output down to errors only. That once hid a
> real concurrency warning for several rounds. Use `release.sh`,
> which does not filter.

## Source tour

Everything lives in one app target plus a `Tools` folder:

| Path | What it is |
| --- | --- |
| `ToggleMicDistance/AppDelegate.swift` | Status item, clicks, windows |
| `ToggleMicDistance/MenuBarIcon.swift` | The animated icon |
| `ToggleMicDistance/IconColors.swift` | Icon color model |
| `ToggleMicDistance/MicDistance.swift` | State, prefs, the script |
| `ToggleMicDistance/AudioDeviceWatcher.swift` | CoreAudio watching |
| `ToggleMicDistance/AudioHijackWatcher.swift` | Audio Hijack watching |
| `ToggleMicDistance/SettingsView.swift` | Settings pane |
| `Tools/release.sh` | Build and install |
| `Tools/GenerateAppIcon.swift` | Regenerate app icon PNGs |

Two things may surprise a new reader:

- The icon geometry appears twice. `Tools/GenerateAppIcon.swift` is a
  standalone script, so it cannot import the app target. If you tune
  the icon in `MenuBarIcon.swift`, mirror the constants there and
  re-run the script.
- `CLAUDE.md` holds detailed working notes for this codebase,
  including a list of traps ("Things that will bite"). Read it before
  making changes.
