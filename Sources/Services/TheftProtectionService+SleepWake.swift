import AppKit
import Foundation
import os.log

extension TheftProtectionService: SleepWakeDelegate {
  func systemWillSleep() {
    ActivityLog.logAsync(.power, "System will sleep")
    // Check lid FIRST — if entering theft mode, services should stay active.
    // Suppress if the lid-close that caused sleep was itself suppressed by
    // external-display presence (undocking at a dock).
    let suppressClamshellSleep = suppressedLidClose
      || (SettingsService.shared.suppressLidTriggerWhenExternalDisplay
          && DisplayTopology.hasExternalDisplay())
    if (state == .enabled || state == .enabledBluetooth)
        && SettingsService.shared.triggerLidClose
        && lidMonitor.isClosed
        && !suppressClamshellSleep {
      activateTheftMode(trigger: .lidClosed)
    }
    if state != .theftMode {
      bluetoothProximityService.pause()
      commandService.pause()
    }
  }

  func systemDidWake() {
    ActivityLog.logAsync(.power, "System did wake")
    // On any wake (including DarkWake), check lid for theft trigger
    if state == .enabled || state == .enabledBluetooth {
      let suppress = suppressedLidClose
        || (SettingsService.shared.suppressLidTriggerWhenExternalDisplay
            && DisplayTopology.hasExternalDisplay())
      if SettingsService.shared.triggerLidClose && lidMonitor.isClosed && !suppress {
        activateTheftMode(trigger: .lidClosed)
        commandService.resume()
      }
    }
    // Only resume services and re-enable assertions on full (user) wake, not DarkWake
    guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }
    if state == .enabled || state == .enabledBluetooth {
      if SettingsService.shared.behaviorSleepPrevention {
        sleepPrevention.enable()
      }
    }
    bluetoothProximityService.resume()
    commandService.resume()
    if state == .enabled || state == .enabledBluetooth {
      recalibrateMotion()
    }
  }

  func shouldDenySleep() -> Bool {
    return state == .theftMode
  }
}
