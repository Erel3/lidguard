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
    let charging = readACConnected()
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
    Logger.power.info("Started (AC: \(charging.map(String.init) ?? "unknown"))")
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
    // A transient IOKit read failure returns nil — do NOT treat that as "on
    // battery", or an unreadable sample fabricates a disconnect and fires a
    // false theft trigger (siren + "STOLEN" alerts). Skip the tick instead,
    // mirroring LidMonitorService's transient-failure handling.
    guard let charging = readACConnected() else { return }
    defer { wasCharging = charging }

    // Detect disconnect: was charging → not charging
    if wasCharging == true && charging == false {
      Logger.power.warning("Power disconnected")
      delegate?.powerMonitorDidDetectDisconnect(self)
    }
  }

  /// True = on AC, false = on battery, nil = power state unreadable this tick.
  /// Callers must not coerce nil to a concrete state.
  private func readACConnected() -> Bool? {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any]
    else { return nil }

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

  /// Display/status convenience: unreadable is reported as not-on-AC.
  func isCharging() -> Bool { readACConnected() ?? false }
}
