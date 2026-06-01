import Cocoa
import SwiftUI

@MainActor
final class SettingsWindowController: SingleWindowController {
  static let shared = SettingsWindowController()

  private init() {
    super.init(
      configure: { window in
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 500))
        if let screen = NSScreen.main {
          let frame = screen.visibleFrame
          window.setFrameOrigin(NSPoint(x: frame.midX - 310, y: frame.midY - 250))
        }
      },
      contentController: { NSHostingController(rootView: SettingsView()) }
    )
  }
}
