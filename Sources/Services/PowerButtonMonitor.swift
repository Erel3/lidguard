import ApplicationServices
import Cocoa
import os.log

protocol PowerButtonDelegate: AnyObject {
  func powerButtonPressed()
}

/// Monitors for power button press using NSEvent global monitor
/// Detects NSSystemDefined events with NX_POWER_KEY (0x7F)
final class PowerButtonMonitor {
  weak var delegate: PowerButtonDelegate?

  private var globalMonitor: Any?
  private var localMonitor: Any?

  func start() {
    guard globalMonitor == nil else { return }

    // Check and request Accessibility permission
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(options) {
      Logger.power.warning("Accessibility permission not granted - power button detection may be limited")
    }

    // Monitor for system-defined events (media keys, power button)
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
      self?.handleSystemEvent(event)
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
      self?.handleSystemEvent(event)
      return event
    }

    Logger.power.info("Power button monitor started")
    ActivityLog.logAsync(.system, "Power button monitor started")
  }

  func stop() {
    if let monitor = globalMonitor {
      NSEvent.removeMonitor(monitor)
      globalMonitor = nil
    }
    if let monitor = localMonitor {
      NSEvent.removeMonitor(monitor)
      localMonitor = nil
    }
    Logger.power.info("Power button monitor stopped")
  }

  private func handleSystemEvent(_ event: NSEvent) {
    let subtype = event.subtype.rawValue

    // Subtype 8 = NX_SUBTYPE_AUX_CONTROL_BUTTONS (classic media keys, power)
    // Subtype 16 = Power button on modern macOS
    guard subtype == 8 || subtype == 16 else { return }

    let data1 = event.data1
    let keyCode = (data1 & 0xFFFF0000) >> 16

    // NX_POWER_KEY = 0x7F (127), or subtype 16 on modern macOS
    let isPowerButton = (subtype == 16) || (subtype == 8 && keyCode == 0x7F)

    if isPowerButton {
      ActivityLog.logAsync(.trigger, "Power button pressed")
      delegate?.powerButtonPressed()
    }
  }
}
