//
//  MenuBarIcon.swift
//  ToggleMicDistance
//

import SwiftUI

/// The animated menu bar icon: a microphone in front of a person, with
/// the person "erased" behind the mic the way Apple's own layered
/// symbols look.
///
/// This is composed at runtime from two stock SF Symbols rather than
/// being a single custom symbol, because the effect is *geometric*. A
/// symbol `.replace` transition can only cross-fade one whole glyph into
/// another; it can't move parts around. Animating `scaleEffect` and
/// `offset` gives real motion, and there are no asset files to keep in
/// sync.
///
/// The front glyph is not always a microphone. It swaps with the state:
/// a struck-through waveform when Audio Hijack isn't running, a
/// struck-through mic when the app is switched off. See `frontSymbol`.
///
/// Hosted inside the status bar button by `AppDelegate`, because an
/// `NSImage` set on `button.image` is a static bitmap that AppKit will
/// never animate.
struct MenuBarIcon: View {
  let model: MicDistanceModel

  /// Drives the one-shot pulse a click gets when the app is switched off.
  @State private var isPulsing = false

  // MARK: - Tuning
  //
  // Nudge these if the icon doesn't look right. The `#Preview` at the
  // bottom of this file renders it large enough to see what you're
  // doing, and `--dump-icons out.png` renders every state side by side
  // in both appearances.

  /// The area we draw into. Wider than it is tall: the enlarged person
  /// in close mode overflows a 22pt square and gets clipped by the mask,
  /// which shears a flat edge off their shoulder.
  private let canvasWidth: CGFloat = 26
  private let canvasHeight: CGFloat = 22
  /// Breathing room either side. Most menu bar icons carry noticeably
  /// more horizontal padding than the glyph itself needs.
  private let horizontalPadding: CGFloat = 3

  /// The front glyph never moves and never resizes. It is the fixed
  /// reference point. All the motion belongs to the person, who steps
  /// toward it.
  private let micSize: CGFloat = 9.6
  private let micOffset = CGSize(width: -5.1, height: 4.4)

  /// The two struck-through glyphs are drawn much larger than the plain
  /// mic, roughly matching the person at close size. In these states the
  /// glyph is the message ("stopped", "switched off") and the person is
  /// only context, so the glyph carries the icon instead of sitting in
  /// the corner of it. Both are pulled down and left to make room.
  private let micSlashSize: CGFloat = 12.4
  private let micSlashOffset = CGSize(width: -4.8, height: 3.3)

  /// Audio Hijack's waveform, standing in for the mic when Audio Hijack
  /// isn't running. A wider glyph than the mic, so a little smaller.
  private let waveformSize: CGFloat = 11.4
  private let waveformOffset = CGSize(width: -4.4, height: 3.4)

  /// The person is large in both positions now that the mic has its own
  /// color to separate it. Distance reads from the *difference* in size
  /// and the diagonal gap, not from the person being small.
  private let personSize: CGFloat = 11
  private let personCloseScale: CGFloat = 1.55
  private let personFarScale: CGFloat = 1.20
  private let personCloseOffset = CGSize(width: 2.1, height: -1.7)
  /// Far still overlaps the mic slightly, pulled in from the corner so
  /// the two shapes stay visually connected.
  private let personFarOffset = CGSize(width: 2.9, height: -2.7)

  /// Width of the erased gap around the front glyph.
  private let knockoutGap: CGFloat = 1.2

  /// How much of the menu bar's own color is left when the app is
  /// switched off: about a third of the way toward the background, which
  /// reads as gray against a white icon without going murky.
  private let inactiveShade: Double = 0.67

  // MARK: - State

  private var state: IconState { model.iconState }

  /// Only the working states show a distance. Stopped and switched off
  /// both draw the person close, where they stay out of the enlarged
  /// glyph's way; the far position comes back as soon as the icon is
  /// reporting a real position again, so it never lies about the switch.
  private var isFar: Bool {
    state == .position(.far)
  }

  private var personScale: CGFloat {
    isFar ? personFarScale : personCloseScale
  }
  private var personOffset: CGSize {
    isFar ? personFarOffset : personCloseOffset
  }

  /// One of the three glyphs that can hold the front position, with the
  /// geometry it needs there.
  private struct FrontGlyph: Identifiable {
    let name: String
    let size: CGFloat
    let offset: CGSize

    var id: String { name }
  }

  /// All three, always. Which one is *shown* is opacity, not identity:
  /// swapping an `Image`'s `systemName` snaps, while two glyphs stacked
  /// with animatable opacities cross-fade. That is what makes a state
  /// change look like the close-to-far move rather than a jump cut.
  private var frontGlyphs: [FrontGlyph] {
    [
      FrontGlyph(name: "microphone.fill", size: micSize, offset: micOffset),
      // One symbol rather than a waveform with a separate slash layer on
      // top: SF Symbols ships the struck-through version, so the slash is
      // already positioned and weighted to match the strokes it crosses.
      FrontGlyph(
        name: "waveform.slash",
        size: waveformSize,
        offset: waveformOffset
      ),
      FrontGlyph(
        name: "microphone.slash.fill",
        size: micSlashSize,
        offset: micSlashOffset
      ),
    ]
  }

  private var currentGlyphName: String {
    switch state {
    case .position: "microphone.fill"
    case .audioHijackStopped: "waveform.slash"
    case .inactive: "microphone.slash.fill"
    }
  }

  // Colors come from Settings, per position. See IconColors.swift.
  private var frontColor: Color {
    switch state {
    case .position: model.color(for: isFar ? .micFar : .micClose)
    // Not the mic's color: this isn't the mic, and the configured orange
    // reads as "live" when the point is that nothing is running.
    case .audioHijackStopped: .primary
    case .inactive: .primary.opacity(inactiveShade)
    }
  }

  private var personColor: Color {
    switch state {
    case .position, .audioHijackStopped:
      model.color(for: isFar ? .personFar : .personClose)
    case .inactive:
      .primary.opacity(inactiveShade)
    }
  }

  // MARK: - View

  var body: some View {
    ZStack {
      // The person, with a glyph-shaped hole punched through it.
      person
        .foregroundStyle(personColor)
        .mask {
          ZStack {
            Rectangle()
            frontShape(dilatedBy: knockoutGap)
              .blendMode(.destinationOut)
          }
          // Required, or `.destinationOut` punches through everything
          // below it instead of just this group.
          .compositingGroup()
        }

      // The mic (or waveform) itself, drawn on top and in front.
      frontShape(dilatedBy: 0)
        .foregroundStyle(frontColor)
    }
    .frame(width: canvasWidth, height: canvasHeight)
    .padding(.horizontal, horizontalPadding)
    // Animates on the whole state, not just the distance, so switching
    // off or losing Audio Hijack moves and cross-fades exactly the way
    // close-to-far does. Attached to the view rather than relying on
    // `withAnimation` at the call site, so the transition still plays
    // when the state is changed from AppKit code.
    .animation(.snappy(duration: 0.28), value: state)
    .scaleEffect(isPulsing ? 0.8 : 1)
    .onChange(of: model.pulseTicks) { _, _ in pulse() }
    .accessibilityLabel(model.statusLabel)
  }

  /// The acknowledgement a click gets when the app is switched off: a
  /// quick squeeze that springs back, so the click clearly landed
  /// without implying anything happened.
  ///
  /// The two halves have to land in *different* run loop turns. Setting
  /// `isPulsing` true and then false in one turn, even with a delayed
  /// animation on the second, leaves SwiftUI with only the net change,
  /// which is no change at all: the squeezed frame is never drawn and
  /// nothing visibly happens. Awaiting a sleep in between is what makes
  /// the first state real.
  private func pulse() {
    withAnimation(.easeOut(duration: 0.12)) {
      isPulsing = true
    }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(130))
      withAnimation(.spring(response: 0.36, dampingFraction: 0.45)) {
        isPulsing = false
      }
    }
  }

  private var person: some View {
    Image(systemName: "person.fill")
      .font(.system(size: personSize))
      .scaleEffect(personScale)
      .offset(personOffset)
      .frame(width: canvasWidth, height: canvasHeight)
  }

  private func image(_ glyph: FrontGlyph) -> some View {
    Image(systemName: glyph.name)
      .font(.system(size: glyph.size))
      .offset(glyph.offset)
  }

  /// The front position's silhouette, optionally fattened.
  ///
  /// The fattened version is used as the knockout so there's a visible
  /// gap between the glyph and the person behind it. It's dilated by
  /// stamping the glyph in a ring of small offsets, which keeps the gap
  /// an even width. Scaling the glyph up instead would make the gap
  /// wider at the edges than in the middle.
  ///
  /// Used as the mask as well as the drawn shape, so the hole in the
  /// person cross-fades along with the glyph. Mid-transition both holes
  /// are half punched, which reads as the person healing over one shape
  /// while the other opens up.
  private func frontShape(dilatedBy gap: CGFloat) -> some View {
    ZStack {
      ForEach(frontGlyphs) { glyph in
        stamped(glyph, dilatedBy: gap)
          .opacity(glyph.name == currentGlyphName ? 1 : 0)
      }
    }
    .frame(width: canvasWidth, height: canvasHeight)
  }

  private func stamped(
    _ glyph: FrontGlyph,
    dilatedBy gap: CGFloat
  ) -> some View {
    let ringSteps = gap > 0 ? 12 : 0
    return ZStack {
      ForEach(Array(0..<ringSteps), id: \.self) { step in
        let angle = Double(step) / 12 * 2 * .pi
        image(glyph).offset(x: cos(angle) * gap, y: sin(angle) * gap)
      }
      image(glyph)
    }
  }
}

/// An `NSHostingView` that refuses to handle clicks, so they fall
/// through to the status bar button underneath it.
///
/// Without this the SwiftUI view sits on top of the button and eats
/// every click, so the icon shows but pressing it does nothing.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

/// Every icon state, blown up, in both appearances.
///
/// This exists to be rendered to a PNG by `--dump-icons`, because the
/// icon lives in the menu bar and this machine can't take screenshots.
/// It's the only way to actually look at a state like "Audio Hijack
/// quit while the app is switched off" without staging it by hand.
struct IconStateGallery: View {
  private let states: [(label: String, state: IconState)] = [
    ("close", .position(.close)),
    ("far", .position(.far)),
    ("no Audio Hijack", .audioHijackStopped),
    ("inactive", .inactive),
  ]

  var body: some View {
    HStack(spacing: 0) {
      column(for: .light)
      column(for: .dark)
    }
    .fixedSize()
  }

  private func column(for scheme: ColorScheme) -> some View {
    VStack(spacing: 18) {
      Text(scheme == .light ? "Light" : "Dark")
        .font(.headline)
      ForEach(states, id: \.label) { entry in
        VStack(spacing: 6) {
          // 5x, which is about as large as the composite can go before
          // the ring-stamped knockout starts to look faceted.
          MenuBarIcon(model: Self.model(showing: entry.state))
            .scaleEffect(5)
            .frame(width: 170, height: 120)
          Text(entry.label)
            .font(.caption)
        }
      }
    }
    .padding(20)
    .frame(width: 230)
    .background(scheme == .light ? Color(white: 0.92) : Color(white: 0.1))
    .environment(\.colorScheme, scheme)
  }

  /// A throwaway model in the given state. `persisting: false` matters:
  /// writing `distance` on the real model would save it, so rendering a
  /// picture of "far" would leave the app switched to far.
  private static func model(showing state: IconState) -> MicDistanceModel {
    let model = MicDistanceModel(persisting: false)
    switch state {
    case .position(let distance):
      model.distance = distance
      model.isAudioHijackRunning = true
    case .audioHijackStopped:
      model.isAudioHijackRunning = false
    case .inactive:
      model.isAudioHijackRunning = true
      model.isDisabled = true
    }
    return model
  }
}

#Preview {
  IconStateGallery()
}
