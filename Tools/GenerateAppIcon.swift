//
//  GenerateAppIcon.swift
//  ToggleMicDistance
//
//  Regenerates every PNG in Assets.xcassets/AppIcon.appiconset from the
//  close-mic composition, so the app icon and the menu bar icon stay in
//  step.
//
//  Run it with no arguments:
//
//      swift Tools/GenerateAppIcon.swift
//
//  Or pass an explicit output directory:
//
//      swift Tools/GenerateAppIcon.swift /path/to/AppIcon.appiconset
//
//  Contents.json is NOT rewritten; it already lists these filenames.
//  Only touch it if you add or remove a size.
//
//  IMPORTANT: the constants below are duplicated from MenuBarIcon.swift.
//  A standalone script can't import the app target, so if you retune the
//  icon there, mirror the change here and re-run. The values that matter
//  are micSize/micOffset and the *close* person scale and offset.
//

import AppKit
import SwiftUI

// MARK: - Must match MenuBarIcon.swift

// NSColor.systemOrange resolved in Light appearance. Hardcoded
// rather than dynamic so the rendered icon is deterministic.
let micOrange = Color(red: 255 / 255, green: 141 / 255, blue: 40 / 255)
let canvasWidthUnits: CGFloat = 26
let canvasHeightUnits: CGFloat = 22
let micSizeUnits: CGFloat = 9.6
let micOffsetUnits = CGSize(width: -5.1, height: 4.4)
let personSizeUnits: CGFloat = 11
let personScaleClose: CGFloat = 1.55
let personOffsetClose = CGSize(width: 2.1, height: -1.7)
let knockoutGapUnits: CGFloat = 1.2

/// Ink color for the person. Deliberately not `Color.primary`: an app
/// icon is composited on its own light tile, not on the menu bar, so it
/// must not follow the system appearance.
let personInk = Color(white: 0.16)

// MARK: - Artwork

/// The close-mic composition, parameterized by `unit` so the glyphs are
/// drawn natively large rather than as an upscaled raster of a 22pt view.
struct Art: View {
  let unit: CGFloat

  private var width: CGFloat { canvasWidthUnits * unit }
  private var height: CGFloat { canvasHeightUnits * unit }

  var body: some View {
    ZStack {
      person
        .foregroundStyle(personInk)
        .mask {
          ZStack {
            Rectangle()
            micShape(dilatedBy: knockoutGapUnits * unit)
              .blendMode(.destinationOut)
          }
          .compositingGroup()
        }
      micShape(dilatedBy: 0).foregroundStyle(micOrange)
    }
    .frame(width: width, height: height)
  }

  private var person: some View {
    Image(systemName: "person.fill")
      .font(.system(size: personSizeUnits * unit))
      .scaleEffect(personScaleClose)
      .offset(
        x: personOffsetClose.width * unit,
        y: personOffsetClose.height * unit
      )
      .frame(width: width, height: height)
  }

  private var micGlyph: some View {
    Image(systemName: "microphone.fill")
      .font(.system(size: micSizeUnits * unit))
      .offset(x: micOffsetUnits.width * unit, y: micOffsetUnits.height * unit)
  }

  private func micShape(dilatedBy gap: CGFloat) -> some View {
    let ringSteps = gap > 0 ? 16 : 0
    return ZStack {
      ForEach(Array(0..<ringSteps), id: \.self) { step in
        let angle = Double(step) / 16 * 2 * .pi
        micGlyph.offset(x: cos(angle) * gap, y: sin(angle) * gap)
      }
      micGlyph
    }
    .frame(width: width, height: height)
  }
}

/// A macOS-style app icon: a rounded-rect tile inset from the canvas
/// edges, with the artwork centered on it.
struct AppIcon: View {
  let side: CGFloat

  var body: some View {
    let inset = side * 0.0977          // Apple's ~100/1024 margin
    let tile = side - inset * 2
    let radius = tile * 0.2237         // squircle-ish
    let unit = (tile * 0.66) / canvasHeightUnits

    ZStack {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color(white: 0.995), Color(white: 0.88)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .overlay {
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
              .black.opacity(0.07),
              lineWidth: max(1, side * 0.003)
            )
        }
        .frame(width: tile, height: tile)

      Art(unit: unit)
    }
    .frame(width: side, height: side)
  }
}

// MARK: - Output

// (filename, pixel size), mirroring Contents.json.
let outputs: [(String, CGFloat)] = [
  ("icon_16x16.png", 16),
  ("icon_16x16@2x.png", 32),
  ("icon_32x32.png", 32),
  ("icon_32x32@2x.png", 64),
  ("icon_128x128.png", 128),
  ("icon_128x128@2x.png", 256),
  ("icon_256x256.png", 256),
  ("icon_256x256@2x.png", 512),
  ("icon_512x512.png", 512),
  ("icon_512x512@2x.png", 1024),
]

/// Defaults to this project's asset catalog, resolved from the script's
/// own location so it works from any working directory.
let outputDirectory: URL = {
  if CommandLine.arguments.count > 1 {
    return URL(fileURLWithPath: CommandLine.arguments[1])
  }
  return URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()      // Tools/
    .deletingLastPathComponent()      // project root
    .appendingPathComponent("ToggleMicDistance/Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")
}()

MainActor.assumeIsolated {
  guard FileManager.default.fileExists(atPath: outputDirectory.path) else {
    print("No such directory: \(outputDirectory.path)")
    exit(1)
  }
  for (filename, pixels) in outputs {
    let renderer = ImageRenderer(content: AppIcon(side: pixels))
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
      print("Failed to render \(filename)")
      exit(1)
    }
    try! png.write(to: outputDirectory.appendingPathComponent(filename))
    print("wrote \(filename) (\(Int(pixels))px)")
  }
  print("\nDone. Rebuild in Xcode to pick up the new icon.")
}
