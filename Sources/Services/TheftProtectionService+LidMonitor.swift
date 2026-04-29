import Foundation
import os.log

extension TheftProtectionService: LidMonitorDelegate {
  func lidMonitorDidDetectClose(_ monitor: LidMonitorService) {
    guard SettingsService.shared.triggerLidClose else { return }
    if SettingsService.shared.suppressLidTriggerWhenExternalDisplay,
       DisplayTopology.hasExternalDisplay() {
      suppressedLidClose = true
      ActivityLog.logAsync(.trigger, "Lid closed ignored (external display attached)")
      return
    }
    suppressedLidClose = false
    ActivityLog.logAsync(.trigger, "Lid closed detected")
    activateTheftMode(trigger: .lidClosed)
  }

  func lidMonitorDidDetectOpen(_ monitor: LidMonitorService) {
    suppressedLidClose = false
    Logger.theft.info("Lid opened - theft mode still active")
    ActivityLog.logAsync(.trigger, "Lid opened - theft mode still active")
  }
}
