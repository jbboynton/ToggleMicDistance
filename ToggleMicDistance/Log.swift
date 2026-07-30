//
//  Log.swift
//  ToggleMicDistance
//

import OSLog

/// The app's log.
///
/// `NSLog` from this app reaches the unified log, but redacted: each call
/// shows up as `(Foundation) <private>` with the message gone (measured
/// 2026-07-30). For an app with no window and no Dock icon that means no
/// way to see what it did after the fact, which is how a stuck menu bar
/// icon ends up unexplainable. An `os.Logger` with an explicit subsystem
/// and `.public` interpolations arrives readable, and can be watched live:
///
///     log stream --predicate \
///       'subsystem == "com.jamesboynton.ToggleMicDistance"'
///
/// Use `.notice` for anything worth reading after the fact, because it is
/// persisted to the log store while `.info` and `.debug` are not.
///
/// **Interpolated strings need `privacy: .public`.** `Logger` redacts them
/// as `<private>` otherwise, which is the right default for user data and
/// useless for a device name you are trying to read. Numbers are public
/// already.
let appLog = Logger(
  subsystem: "com.jamesboynton.ToggleMicDistance",
  category: "app"
)
