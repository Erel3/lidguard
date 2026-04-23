import Foundation
import IOKit.ps
import os.log

@MainActor
protocol PowerMonitorDelegate: AnyObject {
  func powerMonitorDidDetectDisconnect(_ monitor: PowerMonitorService)
}

@MainActor
final class PowerMonitorService {
  weak var delegate: PowerMonitorDelegate?

  private var runLoopSource: CFRunLoopSource?
  private var wasCharging: Bool?
  private var hasBattery = true

  func start() {
    // Initialize state BEFORE adding the runloop source. If the source
    // fires synchronously during CFRunLoopAddSource, a nil `wasCharging`
    // would drop a legitimate disconnect on the first tick.
    let charging = isCharging()
    wasCharging = charging

    let context = Unmanaged.passUnretained(self).toOpaque()
    runLoopSource = IOPSNotificationCreateRunLoopSource({ ctx in
      guard let ctx = ctx else { return }
      Unmanaged<PowerMonitorService>.fromOpaque(ctx)
        .takeUnretainedValue()
        .checkPowerState()
    }, context)?.takeRetainedValue()

    guard let source = runLoopSource else {
      Logger.power.error("Failed to create power notification source")
      return
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

    if !hasBattery {
      Logger.power.info("No battery detected — power-disconnect trigger inactive")
    }
    Logger.power.info("Started (charging: \(charging))")
  }

  func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      runLoopSource = nil
    }
    wasCharging = nil
    Logger.power.info("Stopped")
  }

  private func checkPowerState() {
    let charging = isCharging()
    defer { wasCharging = charging }

    // Detect disconnect: was charging → not charging
    if wasCharging == true && charging == false {
      Logger.power.warning("Power disconnected")
      delegate?.powerMonitorDidDetectDisconnect(self)
    }
  }

  func isCharging() -> Bool {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any]
    else { return false }

    guard let source = sources.first,
          let info = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?
            .takeUnretainedValue() as? [String: Any]
    else {
      // No internal battery (Mac Studio, Mac Pro, Mac mini) — always on AC.
      hasBattery = false
      return true
    }

    return info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
  }
}
