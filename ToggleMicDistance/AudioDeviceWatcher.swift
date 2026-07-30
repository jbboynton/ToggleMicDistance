//
//  AudioDeviceWatcher.swift
//  ToggleMicDistance
//

import CoreAudio
import Foundation
// Needed at the use site: a Logger's string interpolation lives in `os`,
// and without this the call fails to compile even though `appLog` is a
// global. The other files get it through SwiftUI.
import OSLog

/// Watches CoreAudio for input devices appearing and disappearing.
///
/// This is done in Swift rather than in the shell script on purpose.
/// Shelling out to `system_profiler SPAudioDataType` works but takes
/// a second or more and can only tell you the answer when you ask, so
/// you'd have to poll. CoreAudio will call us the moment the device
/// list changes, which is what makes the menu bar icon appear and
/// disappear promptly.
///
/// (If you ever do want the shell equivalent, this is the one-liner:
/// `system_profiler SPAudioDataType | grep -q 'Scarlett 4i4 USB'`.)
final class AudioDeviceWatcher {

  /// Called on the main queue whenever devices are added or removed.
  var onChange: (() -> Void)?

  private var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  private var listener: AudioObjectPropertyListenerBlock?

  func start() {
    guard listener == nil else { return }
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.onChange?()
    }
    listener = block
    let status = AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      DispatchQueue.main,
      block
    )
    if status != noErr {
      appLog.error("Could not watch audio devices: \(status)")
      listener = nil
    }
  }

  deinit {
    guard let listener else { return }
    AudioObjectRemovePropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      DispatchQueue.main,
      listener
    )
  }

  // MARK: - Querying devices

  /// Names of every device that currently has an input stream, sorted
  /// for a stable ordering in the Settings picker.
  nonisolated static func inputDeviceNames() -> [String] {
    allDeviceIDs()
      .filter(hasInputStream)
      .compactMap(name(of:))
      .sorted()
  }

  nonisolated static func isInputDevicePresent(named wanted: String) -> Bool {
    guard !wanted.isEmpty else { return false }
    return inputDeviceNames().contains(wanted)
  }

  nonisolated private static func allDeviceIDs() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
    ) == noErr else { return [] }

    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var ids = [AudioObjectID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address, 0, nil, &size, &ids
    ) == noErr else { return [] }
    return ids
  }

  /// True if the device can record. Output-only devices have no input
  /// streams, which is how we tell the two apart.
  nonisolated private static func hasInputStream(_ id: AudioObjectID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(
      id, &address, 0, nil, &size
    )
    return status == noErr && size > 0
  }

  nonisolated private static func name(of id: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
    }
    guard status == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
  }
}
