//
//  MicDistance.swift
//  ToggleMicDistance
//

// OSLog explicitly: SwiftUI does not re-export it, and a Logger's string
// interpolation is only available where `os` is imported.
import OSLog
import SwiftUI

/// Which of the two mic positions we're currently in.
enum MicDistance: String {
  case close
  case far

  var other: MicDistance {
    self == .close ? .far : .close
  }

  /// Shown as the first, disabled item in the right-click menu, and used
  /// as the icon's accessibility label.
  var statusLabel: String {
    switch self {
    case .close: "Mic is up close"
    case .far: "Mic is set back"
    }
  }
}

/// What the icon is currently saying, which is not always the mic
/// position: the app can be switched off, and Audio Hijack can be gone.
///
/// Derived state, computed in one place so the icon and the menu's status
/// line can never disagree about which case wins.
enum IconState: Equatable {
  /// Normal operation, showing which position we're in.
  case position(MicDistance)
  /// Audio Hijack isn't running, so there's nothing to switch. Clicking
  /// still launches it.
  case audioHijackStopped
  /// Switched off from the menu (or with an Option-click). Clicking does
  /// nothing but pulse.
  case inactive
}

/// The app's shared state.
///
/// `@Observable` is what makes the SwiftUI icon redraw when `distance`
/// changes, and that redraw is what animates it.
@Observable
final class MicDistanceModel {

  /// Name of the device whose presence controls the menu bar icon.
  ///
  /// Defaults to the Scarlett rather than "Desk Mic": "Desk Mic" is a
  /// Loopback virtual device, so it exists whenever Loopback is running
  /// and never goes away when you unplug hardware. The Scarlett is the
  /// physical interface that actually comes and goes.
  static let defaultDeviceName = "Scarlett 4i4 USB"

  private enum Key {
    static let distance = "micDistance"
    static let device = "watchedDeviceName"
    static let startOnConnect = "startSessionOnConnect"
    static let disabled = "isDisabled"
  }

  /// False for the throwaway copies used by `#Preview` and by
  /// `--dump-icons`, so poking at their state to render a picture can't
  /// scribble over the real preferences.
  private let persists: Bool

  /// Whether connecting the interface should run the switching script,
  /// which starts the Audio Hijack session and puts it in the current
  /// position. This is the job the Keyboard Maestro macro was meant to
  /// do: because the app launches at login and the script starts the
  /// session, a login with the interface already plugged in brings the
  /// session up on its own.
  var startSessionOnConnect: Bool {
    didSet {
      guard persists else { return }
      UserDefaults.standard.set(
        startSessionOnConnect,
        forKey: Key.startOnConnect
      )
    }
  }

  var distance: MicDistance {
    didSet {
      guard persists else { return }
      UserDefaults.standard.set(distance.rawValue, forKey: Key.distance)
    }
  }

  /// Set from the Settings picker.
  var watchedDeviceName: String {
    didSet {
      guard persists else { return }
      UserDefaults.standard.set(watchedDeviceName, forKey: Key.device)
    }
  }

  /// Switched off from the menu or with an Option-click on the icon. The
  /// icon stays in the menu bar, dimmed, and every action the app would
  /// otherwise take is skipped.
  ///
  /// Remembered across launches on purpose: this is a mute switch, and a
  /// mute switch that quietly un-mutes itself when you log back in would
  /// be worse than one you have to turn back on.
  var isDisabled: Bool {
    didSet {
      guard persists else { return }
      UserDefaults.standard.set(isDisabled, forKey: Key.disabled)
    }
  }

  /// Whether Audio Hijack is running. Not persisted; `AppDelegate` sets
  /// it from `AudioHijackWatcher` at launch and on every change.
  var isAudioHijackRunning = false

  /// Asks LaunchServices directly instead of waiting to be told. Called
  /// before acting on a click, while opening the menu, and repeatedly
  /// after running the script, so a missed notification can only make the
  /// icon briefly wrong, never permanently wrong.
  func refreshAudioHijackState() {
    let running = AudioHijackWatcher.isRunning
    guard running != isAudioHijackRunning else { return }
    let state = running ? "running" : "not running"
    appLog.notice("Audio Hijack is \(state, privacy: .public)")
    isAudioHijackRunning = running
  }

  /// Bumped to ask the icon to pulse once. A counter rather than a flag
  /// because the icon reacts to the *change*, and clicking a switched off
  /// icon twice should pulse twice.
  var pulseTicks = 0

  /// Whether the watched device is plugged in right now. The status bar
  /// icon is added and removed in response to this.
  var isDevicePresent = false

  // MARK: - Derived state

  /// Which of the three things the icon can be saying. `isDisabled` wins:
  /// when the app is switched off, whether Audio Hijack happens to be
  /// running makes no difference to anything.
  var iconState: IconState {
    if isDisabled {
      .inactive
    } else if !isAudioHijackRunning {
      .audioHijackStopped
    } else {
      .position(distance)
    }
  }

  /// The first, disabled line of the right-click menu.
  var statusLabel: String {
    switch iconState {
    case .position(let distance): distance.statusLabel
    case .audioHijackStopped: "Audio Hijack isn't running"
    case .inactive: "Currently inactive"
    }
  }

  /// Color choice per icon part, edited in Settings. Because the model
  /// is `@Observable`, writing here redraws the menu bar icon at once.
  private var colorMode: [IconPart: IconColorMode] = [:]
  private var colorHex: [IconPart: String] = [:]

  init(persisting: Bool = true) {
    persists = persisting
    let defaults = UserDefaults.standard
    let saved = defaults.string(forKey: Key.distance)
    distance = MicDistance(rawValue: saved ?? "") ?? .close
    isDisabled = defaults.bool(forKey: Key.disabled)
    watchedDeviceName =
      defaults.string(forKey: Key.device) ?? Self.defaultDeviceName
    // Defaults to on, so a fresh install behaves like the macro did.
    startSessionOnConnect =
      defaults.object(forKey: Key.startOnConnect) as? Bool ?? true
    for part in IconPart.allCases {
      if let stored = defaults.string(forKey: part.modeKey) {
        colorMode[part] = IconColorMode(storageValue: stored)
      } else {
        colorMode[part] = part.defaultMode
      }
      colorHex[part] =
        defaults.string(forKey: part.hexKey) ?? part.defaultHex
    }
  }

  // MARK: - Icon colors

  func mode(for part: IconPart) -> IconColorMode {
    colorMode[part] ?? part.defaultMode
  }

  func setMode(_ mode: IconColorMode, for part: IconPart) {
    colorMode[part] = mode
    UserDefaults.standard.set(mode.storageValue, forKey: part.modeKey)
  }

  func hex(for part: IconPart) -> String {
    colorHex[part] ?? part.defaultHex
  }

  func setHex(_ value: String, for part: IconPart) {
    colorHex[part] = value
    UserDefaults.standard.set(value, forKey: part.hexKey)
  }

  /// The color to draw with. A blank or unparseable custom hex falls
  /// back, so a half typed value never hides the icon.
  func color(for part: IconPart) -> Color {
    switch mode(for: part) {
    case .matchSystem: .primary
    case .system(let accent): accent.color
    case .custom: Color(hex: hex(for: part)) ?? part.fallback
    }
  }

  /// True when a custom hex is neither blank nor valid, so Settings can
  /// flag it without changing what's drawn.
  func hexIsInvalid(for part: IconPart) -> Bool {
    guard mode(for: part) == .custom else { return false }
    let text = hex(for: part).trimmingCharacters(in: .whitespaces)
    return !text.isEmpty && Color(hex: text) == nil
  }

  func resetColors() {
    for part in IconPart.allCases {
      setMode(part.defaultMode, for: part)
      setHex(part.defaultHex, for: part)
    }
  }

  /// What a plain click on the icon does.
  ///
  /// Three outcomes, matching the three icon states:
  ///
  /// - Switched off: nothing but a pulse, to show the click landed.
  /// - Audio Hijack not running: launch it and assert the position we're
  ///   already in, rather than flipping. While Audio Hijack is down the
  ///   icon isn't showing a position, so flipping one the user can't see
  ///   would make the icon jump to the opposite of what they expected.
  /// - Normally: flip, and tell Audio Hijack.
  func toggle() {
    if isDisabled {
      pulseTicks += 1
      return
    }
    // Decide on fresh information: whether to flip or to assert depends on
    // it, and so does whether the icon the user just clicked was telling
    // the truth.
    refreshAudioHijackState()
    if isAudioHijackRunning {
      distance = distance.other
    }
    runScript(for: distance)
  }

  /// Re-send the current position, used when the device reappears. The
  /// session may have stopped while it was unplugged.
  func reassert() {
    guard !isDisabled else { return }
    runScript(for: distance)
  }

  // MARK: - Shell script

  /// Where the script lives. Deliberately outside the app bundle so you
  /// can edit it without rebuilding in Xcode.
  static var scriptURL: URL {
    supportDirectory.appendingPathComponent("set-mic-distance.sh")
  }

  static var supportDirectory: URL {
    FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0].appendingPathComponent("ToggleMicDistance", isDirectory: true)
  }

  /// Bumped whenever `scriptTemplate` changes so an installed copy can
  /// be recognised as out of date.
  static let templateVersion = 2

  /// Writes the starter script on first launch. Never overwrites, so
  /// your edits always survive an app update. Use `replaceScript()` for
  /// a deliberate upgrade.
  func installScriptIfNeeded() {
    let url = Self.scriptURL
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    replaceScript()
  }

  /// Overwrites the installed script, keeping the previous copy beside
  /// it as `.bak` so an edited version is never simply lost.
  func replaceScript() {
    let url = Self.scriptURL
    do {
      try FileManager.default.createDirectory(
        at: Self.supportDirectory,
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: url.path) {
        let backup = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: url, to: backup)
      }
      try Self.scriptTemplate.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      // A log message has to be one literal: `OSLogMessage` is not a
      // String and cannot be built up with `+`.
      let reason = error.localizedDescription
      appLog.error("Could not install script: \(reason, privacy: .public)")
    }
  }

  /// The version marker in the installed script, or nil if the file is
  /// missing or you've replaced the header with your own.
  var installedTemplateVersion: Int? {
    guard let text = try? String(contentsOf: Self.scriptURL, encoding: .utf8)
    else { return nil }
    for line in text.split(separator: "\n").prefix(12) {
      let marker = "# template-version:"
      guard line.hasPrefix(marker) else { continue }
      return Int(line.dropFirst(marker.count).trimmingCharacters(
        in: .whitespaces
      ))
    }
    return nil
  }

  /// True when the app knows about a newer script than the one on disk.
  var scriptIsOutdated: Bool {
    guard FileManager.default.fileExists(atPath: Self.scriptURL.path)
    else { return false }
    // No marker means the script predates versioning, so treat it as 1.
    return (installedTemplateVersion ?? 1) < Self.templateVersion
  }

  /// Runs the script with "close" or "far" as its only argument.
  ///
  /// Invoked as `/bin/bash <path>` so the file doesn't need its
  /// executable bit set.
  private func runScript(for distance: MicDistance) {
    let url = Self.scriptURL
    guard FileManager.default.fileExists(atPath: url.path) else {
      appLog.error("No script at \(url.path, privacy: .public)")
      return
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [url.path, distance.rawValue]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    process.terminationHandler = { finished in
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let result = "exited \(finished.terminationStatus): \(output)"
      appLog.notice("set-mic-distance \(result, privacy: .public)")
    }

    do {
      try process.run()
      settleAudioHijack()
    } catch {
      // Most likely cause: App Sandbox got switched back on.
      let reason = error.localizedDescription
      appLog.error("Could not run script: \(reason, privacy: .public)")
    }
  }

  /// Watches Audio Hijack for a few seconds after the script runs, keeping
  /// it off screen and the icon honest.
  ///
  /// Two things go wrong in that window, both measured rather than
  /// guessed:
  ///
  /// - Audio Hijack drifts on screen. `open -g -j` launches it hidden and
  ///   doesn't steal focus, but handing a `.ahcommand` to an app that is
  ///   already running un-hides it, and an un-hidden Audio Hijack with no
  ///   window open puts its session list up when the next command
  ///   arrives. Nothing in its JavaScript API can close that window, so
  ///   the answer is to hide the app.
  /// - The icon lags. A launch this script provokes may or may not have
  ///   been reported yet.
  ///
  /// Hence a watch rather than one check: `open` returns as soon as the
  /// file is handed over, and Audio Hijack does its part some
  /// unpredictable moment later, which on a cold launch can be seconds.
  /// Polling every 50ms keeps any flash to about a frame. It runs the
  /// whole window rather than stopping at the first hide, because Audio
  /// Hijack can surface more than once as the session starts.
  private func settleAudioHijack() {
    Task { @MainActor in
      // 6 seconds, generous enough for a cold launch of Audio Hijack.
      for _ in 0..<120 {
        try? await Task.sleep(for: .milliseconds(50))
        refreshAudioHijackState()
        AudioHijackWatcher.hideUnlessActive()
      }
    }
  }

  /// The generated script.
  ///
  /// Audio Hijack 4 has no AppleScript dictionary. It uses its own
  /// JavaScript API, and `.ahcommand` files are how you trigger that
  /// from outside the app: write JS to a file and `open` it. Your
  /// existing StartEnhanceDeskMic.ahcommand does the same thing.
  ///
  /// The Input Switch block's scriptable surface is `switchToA()` and
  /// `switchToB()`. Note that the `inputSource` you see in the saved
  /// session file is an internal node property and is *not* bridged to
  /// JavaScript, so assigning it fails silently.
  ///
  /// All the configuration lives in this one script rather than in
  /// separate per-mode command files, so there's a single place to edit
  /// if a name or an input index is wrong.
  private static let scriptTemplate = #"""
  #!/usr/bin/env bash
  # template-version: 2
  #
  # Called by ToggleMicDistance with one argument: close | far.
  #
  # Your "Mic Distance" block is an Audio Hijack Input Switch: the
  # "Close Mic" and "Far Mic" chains both feed into it, and it exposes
  # switchToA() / switchToB() to pick which one is live. If toggling
  # comes out backwards, swap the two values below. That is the only
  # change needed.

  set -euo pipefail

  SESSION="Enhance Desk Mic"
  BLOCK="Mic Distance"
  SWITCH_FOR_CLOSE="switchToB"
  SWITCH_FOR_FAR="switchToA"

  case "${1:-}" in
    close) SWITCH="$SWITCH_FOR_CLOSE" ;;
    far)   SWITCH="$SWITCH_FOR_FAR" ;;
    *)
      echo "usage: $(basename "$0") close|far" >&2
      exit 64
      ;;
  esac

  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  COMMANDS="$DIR/commands"
  mkdir -p "$COMMANDS"

  # Each run gets its own filename. Reusing one path meant `open` could
  # treat the file as already open in Audio Hijack and just activate the
  # app without re-running the script, so every other toggle silently
  # did nothing.
  COMMAND_FILE="$COMMANDS/$(date +%s)-$$-$1.ahcommand"

  # Don't accumulate these forever.
  find "$COMMANDS" -name '*.ahcommand' -mmin +5 -delete 2>/dev/null || true

  # Audio Hijack runs whatever JavaScript is in an .ahcommand file when
  # the file is opened. Errors land in Audio Hijack's Script Log window.
  #
  # The switch is thrown *before* starting the session, so a session
  # coming up can't race the switch back to its saved position.
  cat > "$COMMAND_FILE" <<EOF
  let session = app.sessionWithName("$SESSION")
  if (session == null) {
    console.error("No session named '$SESSION'")
    return
  }

  let block = session.blockWithName("$BLOCK")
  if (block == null) {
    console.error("No block named '$BLOCK'. Blocks: "
      + session.blocks.map(b => b.name).join(", "))
    return
  }

  block.$SWITCH()

  // Logged immediately after the switch, and before starting the
  // session. switchPosition reads back as "A" or "B", so this reports
  // what actually happened rather than what we asked for, and putting
  // it first means a failure to start can't swallow the confirmation.
  console.log("Mic Distance is now at input " + block.switchPosition)

  try {
    if (!session.running) {
      session.start()
      // We started it, so keep it out of the way. If you opened the
      // session window yourself it is left alone, because this only runs
      // when the session was not already going.
      session.windowShown = false
    }
  } catch (e) {
    console.error("Switched OK, but could not start the session: " + e)
  }
  EOF

  # -g keeps Audio Hijack from taking focus, -j launches it hidden if it
  # was not already running, so toggling never steals your foreground app.
  open -g -j -a "Audio Hijack" "$COMMAND_FILE"
  echo "set $1 ($SWITCH)"
  """#
}
