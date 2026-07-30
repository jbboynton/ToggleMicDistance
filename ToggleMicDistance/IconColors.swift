//
//  IconColors.swift
//  ToggleMicDistance
//

import AppKit
import SwiftUI

/// The four independently colorable parts of the menu bar icon.
enum IconPart: String, CaseIterable, Identifiable {
  case micClose
  case micFar
  case personClose
  case personFar

  var id: String { rawValue }

  var modeKey: String { "color.\(rawValue).mode" }
  var hexKey: String { "color.\(rawValue).hex" }

  var label: String {
    switch self {
    case .micClose: "Microphone, close:"
    case .micFar: "Microphone, far:"
    case .personClose: "Person, close:"
    case .personFar: "Person, far:"
    }
  }

  /// The person follows the menu bar by default so it stays legible in
  /// both appearances. The mic defaults to the system orange, which is
  /// the same family macOS uses for its own microphone-in-use
  /// indicator, and it adapts to Light and Dark like the rest of the
  /// system colors.
  var defaultMode: IconColorMode {
    switch self {
    case .micClose, .micFar: .system(.orange)
    case .personClose, .personFar: .matchSystem
    }
  }

  var defaultHex: String {
    switch self {
    // Only used if you switch the mic to Custom; starts from
    // the resolved system orange so nothing jumps.
    case .micClose, .micFar: "#FF8D28"
    case .personClose, .personFar: "#FFFFFF"
    }
  }

  /// Used when a custom hex is blank or unparseable, so a half typed
  /// value can never make the icon vanish.
  var fallback: Color {
    switch self {
    case .micClose, .micFar: .orange
    case .personClose, .personFar: .primary
    }
  }
}

/// Where a part's color comes from.
enum IconColorMode: Hashable {
  /// Follows the menu bar: black in Light appearance, white in Dark.
  case matchSystem
  case system(SystemAccent)
  case custom

  var storageValue: String {
    switch self {
    case .matchSystem: "matchSystem"
    case .system(let accent): "system.\(accent.rawValue)"
    case .custom: "custom"
    }
  }

  init(storageValue: String) {
    if storageValue == "custom" {
      self = .custom
    } else if storageValue.hasPrefix("system."),
              let accent = SystemAccent(
                rawValue: String(storageValue.dropFirst("system.".count))
              ) {
      self = .system(accent)
    } else {
      self = .matchSystem
    }
  }
}

/// The standard macOS accent colors, matching the set the system offers
/// for its own accent color setting.
enum SystemAccent: String, CaseIterable, Identifiable {
  case blue
  case purple
  case pink
  case red
  case orange
  case yellow
  case green
  case graphite

  var id: String { rawValue }

  var displayName: String {
    rawValue.capitalized
  }

  var color: Color {
    switch self {
    case .blue: .blue
    case .purple: .purple
    case .pink: .pink
    case .red: .red
    case .orange: .orange
    case .yellow: .yellow
    case .green: .green
    case .graphite: .gray
    }
  }

  /// A filled dot for the picker menu.
  ///
  /// This has to be a real bitmap rather than
  /// `Image(systemName: "circle.fill").foregroundStyle(color)`. Menus
  /// treat SF Symbols as template images, which discards the tint and
  /// renders every dot the same gray. Marking a drawn `NSImage` as not
  /// a template keeps its color.
  var dotImage: NSImage {
    let side: CGFloat = 11
    let image = NSImage(
      size: NSSize(width: side, height: side),
      flipped: false
    ) { rect in
      NSColor(self.color).setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
      return true
    }
    image.isTemplate = false
    return image
  }
}

extension Color {
  /// Parses `#RRGGBB`, `RRGGBB`, `#RGB` or `RGB`. Returns nil for
  /// anything else, including an empty string.
  init?(hex raw: String) {
    var digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard digits.count == 3 || digits.count == 6,
          digits.allSatisfy(\.isHexDigit)
    else { return nil }

    // Expand shorthand, so "f93" becomes "ff9933".
    if digits.count == 3 {
      digits = digits.map { "\($0)\($0)" }.joined()
    }
    guard let value = UInt32(digits, radix: 16) else { return nil }

    self.init(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }

  /// `#RRGGBB` for this color, used to store what the color picker
  /// hands back.
  var hexString: String {
    guard let srgb = NSColor(self).usingColorSpace(.sRGB) else {
      return "#FFFFFF"
    }
    return String(
      format: "#%02X%02X%02X",
      Int((srgb.redComponent * 255).rounded()),
      Int((srgb.greenComponent * 255).rounded()),
      Int((srgb.blueComponent * 255).rounded())
    )
  }
}
