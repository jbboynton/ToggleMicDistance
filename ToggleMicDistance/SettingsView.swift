//
//  SettingsView.swift
//  ToggleMicDistance
//

import ServiceManagement
import SwiftUI

/// The Settings window, opened from the icon's right-click menu.
///
/// Hosted in a plain `NSWindow` that `AppDelegate` owns rather than in a
/// SwiftUI `Settings` scene. A `Settings` scene can only be opened with
/// the `showSettingsWindow:` action, which routes through the app menu,
/// and this app has no menu bar because it runs as an agent.
struct SettingsView: View {
  let model: MicDistanceModel

  @State private var deviceNames: [String] = []
  @State private var selectedDevice = ""
  @State private var launchAtLogin = false
  @State private var loginError: String?
  @State private var copiedPath = false
  @State private var scriptReplaced = false

  private let labelWidth: CGFloat = 118

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      group {
        ForEach(IconPart.allCases) { part in
          row(part.label) { colorControl(for: part) }
        }
        row("") {
          Button("Reset to Defaults") { model.resetColors() }
        }
        help(
          """
          Match System follows the menu bar, drawing the shape black in \
          Light appearance and white in Dark.
          """
        )
      }

      Divider()

      group {
        row("Mic interface:") {
          Picker("", selection: $selectedDevice) {
            ForEach(deviceNames, id: \.self) { name in
              Text(name).tag(name)
            }
            // Keeps a saved but unplugged device selectable.
            if !selectedDevice.isEmpty,
               !deviceNames.contains(selectedDevice) {
              Text("\(selectedDevice) (not connected)")
                .tag(selectedDevice)
            }
          }
          .labelsHidden()
          .frame(width: 240)
        }
        help(
          """
          Pick the physical interface, not a Loopback virtual device \
          (which stays present even when your hardware is not \
          connected).
          """
        )
      }

      Divider()

      group {
        row("Startup:") {
          VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: $launchAtLogin)
              .toggleStyle(.checkbox)
              .onChange(of: launchAtLogin) { _, wanted in
                setLaunchAtLogin(wanted)
              }
            Toggle(
              "Start Audio Hijack session when the interface connects",
              isOn: Binding(
                get: { model.startSessionOnConnect },
                set: { model.startSessionOnConnect = $0 }
              )
            )
            .toggleStyle(.checkbox)
          }
        }
        if let loginError {
          help(loginError, isError: true)
        }
      }

      Divider()

      group {
        row("Script:") {
          HStack(spacing: 8) {
            Button("Reveal in Finder") {
              NSWorkspace.shared.activateFileViewerSelecting(
                [MicDistanceModel.scriptURL]
              )
            }
            Button("Open in Editor") {
              NSWorkspace.shared.open(MicDistanceModel.scriptURL)
            }
            Button(copiedPath ? "Copied" : "Copy Path") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(
                MicDistanceModel.scriptURL.path,
                forType: .string
              )
              copiedPath = true
            }
          }
        }
        help(MicDistanceModel.scriptURL.path, monospaced: true)
        if model.scriptIsOutdated {
          row("") {
            Button("Replace with Latest") {
              model.replaceScript()
              scriptReplaced = true
            }
          }
          help(
            scriptReplaced
              ? "Replaced. The previous version is beside it as .bak."
              : """
                A newer version of this script ships with the app. \
                Replacing it keeps your current copy as .bak.
                """
          )
        }
      }

      Divider()

      row("About:") {
        Text("ToggleMicDistance \(Self.version)")
          .foregroundStyle(.secondary)
      }
    }
    .padding(20)
    .frame(width: 520)
    .onAppear(perform: reload)
  }

  // MARK: - Layout helpers

  private func group<Content: View>(
    @ViewBuilder _ content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) { content() }
  }

  /// One right-aligned label with its control, the layout used across
  /// macOS settings panes.
  private func row<Content: View>(
    _ label: String,
    @ViewBuilder _ content: () -> Content
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(label)
        .frame(width: labelWidth, alignment: .trailing)
      content()
      Spacer(minLength: 0)
    }
  }

  /// Explanatory text, indented to sit under the control column.
  private func help(
    _ text: String,
    isError: Bool = false,
    monospaced: Bool = false
  ) -> some View {
    HStack(spacing: 10) {
      Spacer().frame(width: labelWidth)
      Text(text)
        .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
        .foregroundStyle(isError ? AnyShapeStyle(.red)
                                 : AnyShapeStyle(.secondary))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
  }

  // MARK: - Color control

  /// One color row. Every control is always present at a fixed size, so
  /// switching to Custom cannot change the row's dimensions and reflow
  /// the pane.
  private func colorControl(for part: IconPart) -> some View {
    HStack(spacing: 8) {
      Picker("", selection: modeBinding(for: part)) {
        Text("Match System").tag(IconColorMode.matchSystem)
        Divider()
        ForEach(SystemAccent.allCases) { accent in
          Label {
            Text(accent.displayName)
          } icon: {
            Image(nsImage: accent.dotImage)
          }
          .tag(IconColorMode.system(accent))
        }
        Divider()
        Text("Custom").tag(IconColorMode.custom)
      }
      .labelsHidden()
      .frame(width: 150)

      // Always the real color well, so the swatch looks identical in
      // every mode. Choosing a color here switches the row to Custom.
      ColorPicker(
        "",
        selection: colorBinding(for: part),
        supportsOpacity: false
      )
      .labelsHidden()

      // Shows the resolved hex even for the system colors, and typing in
      // it switches the row to Custom.
      TextField("#RRGGBB", text: hexBinding(for: part))
        .font(.system(.body, design: .monospaced))
        .frame(width: 92)

      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .help("Not a valid hex color, so the default is being used.")
        // Kept in the layout at all times so the row never resizes.
        .opacity(model.hexIsInvalid(for: part) ? 1 : 0)
    }
  }

  // MARK: - Color bindings

  private func modeBinding(for part: IconPart) -> Binding<IconColorMode> {
    Binding(
      get: { model.mode(for: part) },
      set: { model.setMode($0, for: part) }
    )
  }

  private func colorBinding(for part: IconPart) -> Binding<Color> {
    Binding(
      get: { model.color(for: part) },
      set: { newColor in
        let hex = newColor.hexString
        // Guard against SwiftUI writing back the value it just read,
        // which would silently flip the row to Custom.
        guard hex != model.color(for: part).hexString else { return }
        model.setHex(hex, for: part)
        model.setMode(.custom, for: part)
      }
    )
  }

  private func hexBinding(for part: IconPart) -> Binding<String> {
    Binding(
      get: {
        switch model.mode(for: part) {
        case .custom: model.hex(for: part)
        // Report what is actually being drawn, resolved for the current
        // appearance.
        default: model.color(for: part).hexString
        }
      },
      set: { text in
        guard text != model.hex(for: part) else { return }
        model.setHex(text, for: part)
        model.setMode(.custom, for: part)
      }
    )
  }

  // MARK: - Loading and login item

  private static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      as? String ?? "?"
  }

  private func reload() {
    deviceNames = AudioDeviceWatcher.inputDeviceNames()
    selectedDevice = model.watchedDeviceName
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  private func setLaunchAtLogin(_ wanted: Bool) {
    do {
      if wanted {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginError = nil
    } catch {
      // Registering needs a signed app in a stable location. This app is
      // ad hoc signed, so if it refuses, add it by hand in System
      // Settings, General, Login Items.
      loginError = "Couldn't change this: \(error.localizedDescription)"
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }
}

#Preview {
  SettingsView(model: MicDistanceModel())
}
