import Foundation
import IOKit.pwr_mgt
import os.log

@MainActor
protocol SleepPrevention {
  func enable()
  func disable()
  var isEnabled: Bool { get }
}

@MainActor
final class SleepPreventionService: SleepPrevention {
  private var idleSleepAssertionID: IOPMAssertionID = 0
  private var systemSleepAssertionID: IOPMAssertionID = 0
  private var idleHeld = false
  private var systemHeld = false
  var isEnabled: Bool { idleHeld || systemHeld }

  func enable() {
    guard !isEnabled else { return }

    let reason = "LidGuard theft protection active" as CFString

    let idleResult = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reason,
      &idleSleepAssertionID
    )
    idleHeld = (idleResult == kIOReturnSuccess)

    let systemResult = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reason,
      &systemSleepAssertionID
    )
    systemHeld = (systemResult == kIOReturnSuccess)

    Logger.power.info("SleepPrevention enabled (idle=\(self.idleHeld) system=\(self.systemHeld))")
  }

  func disable() {
    // Release each independently — do not leak one when the other failed to create.
    if idleHeld {
      IOPMAssertionRelease(idleSleepAssertionID)
      idleHeld = false
      idleSleepAssertionID = 0
    }
    if systemHeld {
      IOPMAssertionRelease(systemSleepAssertionID)
      systemHeld = false
      systemSleepAssertionID = 0
    }
    Logger.power.info("SleepPrevention disabled")
  }
}
