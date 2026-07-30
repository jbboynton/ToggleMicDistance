//
//  AppDelegate.swift
//  ToggleMicDistance
//

// OSLog explicitly: SwiftUI does not re-export it, and a Logger's string
// interpolation is only available where `os` is imported.
import OSLog
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

  /// Held strongly. Releasing this is what removes the icon from the
  /// menu bar, which is exactly how we hide it when the mic is gone.
  private var statusItem: NSStatusItem?
  private var settingsWindow: NSWindow?
  private let model = MicDistanceModel()
  private let watcher = AudioDeviceWatcher()
  private let audioHijack = AudioHijackWatcher()

  func applicationDidFinishLaunching(_ notification: Notification) {
    model.installScriptIfNeeded()

    // Debug helpers, so the Settings layout can be checked without
    // clicking through the menu.
    if CommandLine.arguments.contains("--open-settings") {
      openSettings()
      let visible = settingsWindow?.isVisible == true
      let size = settingsWindow?.frame.size ?? .zero
      let detail = "visible: \(visible) size: \(size)"
      appLog.notice("settings window \(detail, privacy: .public)")
    }
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--dump-settings"),
       index + 1 < arguments.count {
      dumpSettings(to: arguments[index + 1])
      NSApp.terminate(nil)
    }
    if let index = arguments.firstIndex(of: "--dump-icons"),
       index + 1 < arguments.count {
      dumpIcons(to: arguments[index + 1])
      NSApp.terminate(nil)
    }

    // Audio Hijack quitting or launching changes the icon, including when
    // that happens by hand rather than through us. Set up before the
    // status item exists, so the icon is drawn right the first time.
    audioHijack.onChange = { [weak self] in
      self?.model.refreshAudioHijackState()
    }
    audioHijack.start()
    model.refreshAudioHijackState()

    watcher.onChange = { [weak self] in
      self?.updateDevicePresence()
    }
    watcher.start()
    updateDevicePresence()
  }

  // MARK: - Showing and hiding

  /// Adds or removes the status item to match whether the watched
  /// device is plugged in.
  private func updateDevicePresence() {
    let present = AudioDeviceWatcher.isInputDevicePresent(
      named: model.watchedDeviceName
    )
    guard present != model.isDevicePresent else { return }
    model.isDevicePresent = present

    if present {
      showStatusItem()
      // The session may have stopped while the mic was unplugged, so
      // put Audio Hijack back into the state the icon is showing. This
      // also covers logging in with the interface already connected.
      if model.startSessionOnConnect {
        model.reassert()
      }
    } else {
      hideStatusItem()
    }
  }

  /// Call after changing the watched device in Settings, since the
  /// device list itself hasn't changed.
  func refreshDevicePresence() {
    let present = AudioDeviceWatcher.isInputDevicePresent(
      named: model.watchedDeviceName
    )
    model.isDevicePresent = !present
    updateDevicePresence()
  }

  private func showStatusItem() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(
      withLength: NSStatusItem.variableLength
    )
    statusItem = item

    guard let button = item.button else { return }
    button.target = self
    button.action = #selector(statusBarButtonClicked(_:))
    // Ask for right-clicks too, so we can show a menu on those.
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    let iconView = PassthroughHostingView(
      rootView: MenuBarIcon(model: model)
    )
    iconView.translatesAutoresizingMaskIntoConstraints = false
    button.addSubview(iconView)
    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
      iconView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
      iconView.topAnchor.constraint(equalTo: button.topAnchor),
      iconView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
    ])
  }

  private func hideStatusItem() {
    if let statusItem {
      NSStatusBar.system.removeStatusItem(statusItem)
    }
    statusItem = nil
  }

  // MARK: - Clicks

  @objc private func statusBarButtonClicked(_ sender: Any?) {
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp {
      showMenu()
    } else if event?.modifierFlags.contains(.option) == true {
      // The same shortcut macOS itself uses for the "extra" action on a
      // menu bar item, and it saves opening the menu to flip a switch.
      toggleDisabled()
    } else {
      model.toggle()
    }
  }

  private func showMenu() {
    // The status line is only worth showing if it's current, and a
    // notification can always have been missed.
    model.refreshAudioHijackState()

    let menu = NSMenu()
    let state = NSMenuItem(
      title: model.statusLabel,
      action: nil,
      keyEquivalent: ""
    )
    state.isEnabled = false
    menu.addItem(state)
    menu.addItem(.separator())

    // A checked toggle rather than a title that flips between "Disable"
    // and "Enable", which is the AppKit convention and reads the same
    // whichever state you open the menu in.
    let disable = NSMenuItem(
      title: "Disable Temporarily",
      action: #selector(toggleDisabled),
      keyEquivalent: ""
    )
    disable.target = self
    disable.state = model.isDisabled ? .on : .off
    disable.toolTip =
      "Option-click the icon to switch it off without opening this menu."
    menu.addItem(disable)
    menu.addItem(.separator())

    let script = NSMenuItem(
      title: "Edit Switching Script…",
      action: #selector(openScript),
      keyEquivalent: ""
    )
    script.target = self

    let settings = NSMenuItem(
      title: "Settings…",
      action: #selector(openSettings),
      keyEquivalent: ","
    )
    settings.target = self

    // macOS 26 hands "Settings…" and "Quit" an SF Symbol of its own
    // accord, at the moment the item is created. Titles line up per
    // section, so one item carrying an image indents its neighbors, which
    // left this item's title hanging in from the left. Give it an image
    // too, sized to whatever the system picked, and the section lines up.
    script.image = NSImage(
      systemSymbolName: "square.and.pencil",
      accessibilityDescription: "Edit"
    )
    if let systemSize = settings.image?.size {
      script.image?.size = systemSize
    }

    menu.addItem(script)
    menu.addItem(settings)

    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )

    // Pop the menu up directly rather than assigning `statusItem.menu`.
    // Assigning it would stop left-clicks from reaching our action, and
    // the usual workaround (assign, `performClick`, unassign) re-enters
    // this click handler.
    guard let button = statusItem?.button else { return }
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: 0, y: button.bounds.height + 5),
      in: button
    )
  }

  /// Switches the icon off, or back on. Nothing is sent to Audio Hijack
  /// either way: whatever the session is doing, it keeps doing.
  @objc private func toggleDisabled() {
    model.isDisabled.toggle()
  }

  @objc private func openScript() {
    NSWorkspace.shared.open(MicDistanceModel.scriptURL)
  }

  /// Opens the Settings window, creating it on first use.
  ///
  /// This app owns the window rather than using a SwiftUI `Settings`
  /// scene. That scene can only be opened by sending the private
  /// `showSettingsWindow:` action, which routes through the app menu,
  /// and an agent app has no menu bar, so the menu item did nothing.
  @objc private func openSettings() {
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 470, height: 400),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "ToggleMicDistance Settings"

      // Size the window to whatever the content actually needs, rather
      // than a guessed height that clips the last section.
      let hosting = NSHostingView(rootView: SettingsView(model: model))
      hosting.layoutSubtreeIfNeeded()
      window.contentView = hosting
      window.setContentSize(hosting.fittingSize)
      window.contentMinSize = hosting.fittingSize
      // Without this the window is destroyed on close and reopening
      // crashes on the dangling reference.
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = window
    }
    NSApp.activate()
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  /// Renders the Settings pane to a PNG so its layout can be reviewed
  /// without a screenshot. Note that `onAppear` does not run under
  /// `ImageRenderer`, so the device picker renders empty.
  private func dumpSettings(to path: String) {
    render(SettingsView(model: model), to: path)
  }

  /// Renders every icon state to a PNG, in both appearances. The icon
  /// can't be screenshotted out of the menu bar on this machine, so this
  /// is how to check it.
  private func dumpIcons(to path: String) {
    render(IconStateGallery(), to: path)
  }

  private func render<Content: View>(_ content: Content, to path: String) {
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
      appLog.error("could not render")
      return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    let detail = "\(path) size \(image.size)"
    appLog.notice("wrote render to \(detail, privacy: .public)")
  }

  /// Lets the Settings UI reach the model and this delegate.
  static var shared: AppDelegate? {
    NSApp.delegate as? AppDelegate
  }

  var sharedModel: MicDistanceModel { model }
}
