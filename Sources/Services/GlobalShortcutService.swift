import ApplicationServices
import Cocoa
import os.log

extension Notification.Name {
  static let shortcutSettingsChanged = Notification.Name("com.lidguard.shortcutSettingsChanged")
}

protocol GlobalShortcutDelegate: AnyObject {
  func globalShortcutTriggered()
}

/// Monitors for a user-configured global keyboard shortcut.
/// Requires Accessibility permission for global event monitoring.
final class GlobalShortcutService {
  weak var delegate: GlobalShortcutDelegate?

  private var globalMonitor: Any?
  private var keyCode: Int = -1
  private var modifiers: NSEvent.ModifierFlags = []
  private var lastTriggerTime: Date = .distantPast

  func start() {
    let settings = SettingsService.shared
    guard settings.shortcutEnabled, settings.isShortcutConfigured else { return }
    guard globalMonitor == nil else { return }

    keyCode = settings.shortcutKeyCode
    modifiers = NSEvent.ModifierFlags(rawValue: UInt(settings.shortcutModifiers))
      .intersection([.command, .control, .option, .shift])

    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(options) {
      Logger.power.warning("Accessibility permission not granted - global shortcut may not work")
    }

    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleKeyEvent(event)
    }

    let displayStr = shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)
    Logger.theft.info("Global shortcut monitor started: \(displayStr)")
    ActivityLog.logAsync(.system, "Global shortcut monitor started: \(displayStr)")
  }

  func stop() {
    if let monitor = globalMonitor {
      NSEvent.removeMonitor(monitor)
      globalMonitor = nil
    }
  }

  func restart() {
    stop()
    start()
  }

  private func handleKeyEvent(_ event: NSEvent) {
    let eventMods = event.modifierFlags.intersection([.command, .control, .option, .shift])
    guard Int(event.keyCode) == keyCode, eventMods == modifiers else { return }
    guard Date().timeIntervalSince(lastTriggerTime) > 1.0 else { return }
    lastTriggerTime = Date()

    ActivityLog.logAsync(.trigger, "Global shortcut pressed")
    delegate?.globalShortcutTriggered()
  }
}
