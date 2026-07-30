//
//  ToggleMicDistanceApp.swift
//  ToggleMicDistance
//
//

import SwiftUI

@main
struct ToggleMicDistanceApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  var body: some Scene {
    Settings {
      // Unreachable in an agent app (no menu bar); the real Settings
      // window is an NSWindow owned by AppDelegate.
      EmptyView()
    }
  }
}
