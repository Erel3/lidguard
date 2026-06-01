import Cocoa
import SwiftUI

/// Base for singleton controllers that own one reusable, non-released window.
/// Subclasses supply window configuration and a content-controller factory;
/// this base handles the show/reuse/close lifecycle and acts as the window's
/// delegate so the reference is cleared when the user closes it.
@MainActor
class SingleWindowController: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private let configure: (NSWindow) -> Void
  private let makeContentController: () -> NSViewController

  init(
    configure: @escaping (NSWindow) -> Void,
    contentController: @escaping () -> NSViewController
  ) {
    self.configure = configure
    self.makeContentController = contentController
    super.init()
  }

  func show() {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let newWindow = NSWindow(contentViewController: makeContentController())
    newWindow.isReleasedWhenClosed = false
    configure(newWindow)
    newWindow.delegate = self

    window = newWindow
    newWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func close() {
    window?.close()
    window = nil
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
  }
}
