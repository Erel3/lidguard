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

  /// nil = not yet determined, true = a battery has been seen, false = confirmed
  /// batteryless (Mac Studio / Pro / mini). Tri-state because an empty power-source
  /// list cannot be read without it — see `readACConnected()`.
  private var batteryPresence: Bool?

  func start() {
    // Idempotent: a second CFRunLoopAddSource without removing the first leaves
    // two live notification sources delivering duplicate ticks.
    guard runLoopSource == nil else { return }

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

    if batteryPresence == false {
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

    guard let source = sources.first else {
      // An empty list is ambiguous. A batteryless Mac has no power source to
      // report — but neither does a laptop for a moment around sleep/wake and
      // power-source transitions. Only a machine we have never seen a battery on
      // may be called "always on AC"; once one has been seen, an empty list is a
      // transient failure, and coercing it to `true` here makes the NEXT valid
      // on-battery read look like an AC disconnect — firing a full false theft
      // trigger (siren, STOLEN overlay, Telegram alert) on a machine nobody
      // touched. That is the coercion the contract above forbids.
      guard batteryPresence != true else { return nil }
      batteryPresence = false
      return true
    }

    guard let info = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?
            .takeUnretainedValue() as? [String: Any]
    else {
      // A source exists but its description is unreadable: transient, and it says
      // nothing about whether this Mac has a battery. Never latch presence here.
      return nil
    }

    batteryPresence = true
    return info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
  }

  /// Display/status convenience: unreadable is reported as not-on-AC.
  func isCharging() -> Bool { readACConnected() ?? false }
}
