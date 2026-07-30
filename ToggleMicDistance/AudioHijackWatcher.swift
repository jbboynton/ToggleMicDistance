//
//  AudioHijackWatcher.swift
//  ToggleMicDistance
//

import AppKit

/// Watches Audio Hijack launching and quitting, and knows how to put it
/// back out of sight.
///
/// The notifications come from `NSWorkspace.shared.notificationCenter`,
/// which is a *different* center from `NotificationCenter.default`.
/// Registering these names on the default center compiles, and then
/// never fires; app lifecycle notices are only posted on the workspace
/// center.
///
/// Because the app is told when Audio Hijack starts or stops, the icon
/// also updates when Audio Hijack is launched or quit by hand, with no
/// polling.
final class AudioHijackWatcher {

  /// Audio Hijack 4's bundle identifier. Checked against the launching
  /// app rather than matching on the name, which a user can change.
  ///
  /// `nonisolated` because Xcode 26 puts this type on the main actor, and
  /// the lookups below are deliberately off it. Safe for a `let` holding
  /// a `Sendable` value.
  ///
  /// Overridable with `TMD_WATCH_BUNDLE_ID` so the launch and quit path
  /// can be exercised against a harmless app:
  ///
  ///     TMD_WATCH_BUNDLE_ID=com.apple.TextEdit \
  ///       ToggleMicDistance.app/Contents/MacOS/ToggleMicDistance
  ///
  /// Testing it with the real thing means stopping a live session.
  nonisolated static let bundleIdentifier =
    ProcessInfo.processInfo.environment["TMD_WATCH_BUNDLE_ID"]
      ?? "com.rogueamoeba.audiohijack"

  /// Called on the main queue when any app starts or stops, as a cue to
  /// go and look at Audio Hijack. See `start()` for why it doesn't say
  /// what happened.
  var onChange: (() -> Void)?

  private var observers: [NSObjectProtocol] = []

  func start() {
    guard observers.isEmpty else { return }
    let center = NSWorkspace.shared.notificationCenter
    let names = [
      NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
    ]
    for name in names {
      let token = center.addObserver(
        forName: name,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        // Deliberately unfiltered. The obvious version reads the
        // launching app out of `userInfo` and compares bundle
        // identifiers, but a just-launched `NSRunningApplication` has its
        // properties filled in asynchronously, so `bundleIdentifier` can
        // still be nil at this point and a filter silently drops the
        // launch. That is the shape of the bug where the icon stayed in
        // its stopped state after a click launched Audio Hijack, while
        // *quitting* it updated fine: by quit time the object is fully
        // populated. Asking LaunchServices is accurate here (measured),
        // and a couple of app launches a minute is nothing.
        //
        // The queue above is `.main`, so this really is the main thread;
        // `assumeIsolated` is how you tell the compiler that, since the
        // notification block itself carries no actor.
        MainActor.assumeIsolated {
          self?.onChange?()
        }
      }
      observers.append(token)
    }
  }

  deinit {
    let center = NSWorkspace.shared.notificationCenter
    for observer in observers {
      center.removeObserver(observer)
    }
  }

  // MARK: - Asking about Audio Hijack

  /// The running instance, if there is one. Marked `nonisolated` for the
  /// same reason as the CoreAudio helpers: Xcode 26 puts plain types on
  /// the main actor by default, and these are called from a background
  /// context.
  nonisolated static var runningApp: NSRunningApplication? {
    NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    ).first
  }

  nonisolated static var isRunning: Bool {
    runningApp != nil
  }

  /// Running *and* not hidden. A hidden app is still running, so this is
  /// the question to ask before deciding whether a toggle is allowed to
  /// leave Audio Hijack on screen.
  nonisolated static var isVisible: Bool {
    guard let app = runningApp else { return false }
    return !app.isHidden
  }

  /// Hides Audio Hijack unless the user is in it. Returns whether there
  /// was anything to hide.
  ///
  /// The `isActive` check is the whole safety net: if Audio Hijack is the
  /// frontmost app, someone is using it and it must be left alone.
  /// Anything else means it drifted on screen by itself, which is what a
  /// toggle provokes, and it goes back out of the way.
  ///
  /// `NSRunningApplication.hide()` is the app-level equivalent of
  /// Command-H. Unlike the System Events route it needs no Accessibility
  /// permission. Its own return value is not worth reading: hiding Audio
  /// Hijack returns `false` and hides it anyway (measured 2026-07-30), so
  /// this reports whether the app *was* on screen instead.
  @discardableResult
  nonisolated static func hideUnlessActive() -> Bool {
    guard let app = runningApp, !app.isHidden, !app.isActive else {
      return false
    }
    app.hide()
    return true
  }
}
