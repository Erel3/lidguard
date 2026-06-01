import Cocoa
import SwiftUI

@MainActor
final class ActivityLogWindowController: SingleWindowController {
  static let shared = ActivityLogWindowController()

  private init() {
    super.init(
      configure: { window in
        window.title = "Activity Log"
        window.styleMask = [.titled, .closable, .resizable]
        window.center()
        window.setFrameAutosaveName("ActivityLogWindow")
      },
      contentController: { NSHostingController(rootView: ActivityLogView()) }
    )
  }
}
