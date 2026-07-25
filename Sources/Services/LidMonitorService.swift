import Foundation
import IOKit
import os.log

@MainActor
protocol LidMonitorDelegate: AnyObject {
  func lidMonitorDidDetectClose(_ monitor: LidMonitorService)
  func lidMonitorDidDetectOpen(_ monitor: LidMonitorService)
}

@MainActor
final class LidMonitorService {
  weak var delegate: LidMonitorDelegate?

  private var lastState: Bool?
  private var timer: DispatchSourceTimer?
  private let checkInterval: TimeInterval

  init(checkInterval: TimeInterval = Config.Tracking.lidCheckInterval) {
    self.checkInterval = checkInterval
  }

  func start() {
    // Idempotent: assigning over a live DispatchSourceTimer does not cancel it,
    // so a second start() would leave the first orphaned and still firing.
    guard timer == nil else { return }
    let newTimer = DispatchSource.makeTimerSource(queue: .main)
    newTimer.schedule(deadline: .now(), repeating: checkInterval)
    newTimer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.checkState()
      }
    }
    newTimer.resume()
    timer = newTimer
    Logger.lid.info("Started")
  }

  func stop() {
    timer?.cancel()
    timer = nil
    lastState = nil
    Logger.lid.info("Stopped")
  }

  /// Synchronous read for one-shot queries (status command, sleep handler).
  ///
  /// Falls back to the last observed state on IOKit failure; `false` (open) is
  /// the answer only when no valid value has ever been read.
  ///
  /// The fallback is the point. `TheftProtectionService+SleepWake` gates
  /// `activateTheftMode` on this value, and an IORegistry read is most likely to
  /// fail during exactly the clamshell sleep transition that handler runs in —
  /// so coercing nil to "open" drops a real lid-close theft: no siren, no screen
  /// lock, no Telegram alert. `checkState()` skips the tick on nil for the same
  /// reason; this path has no tick to skip, so it reuses what it last saw.
  var isClosed: Bool {
    guard let current = Self.readClamshellState() else { return lastState ?? false }
    lastState = current
    return current
  }

  private func checkState() {
    // Skip tick entirely on IOKit transient failure; previous "false" default
    // could mask a close or fabricate an open across sleep/wake transitions.
    guard let currentState = Self.readClamshellState() else { return }

    if let last = lastState {
      if !last && currentState {
        delegate?.lidMonitorDidDetectClose(self)
      } else if last && !currentState {
        delegate?.lidMonitorDidDetectOpen(self)
      }
    }

    lastState = currentState
  }

  nonisolated private static func readClamshellState() -> Bool? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }

    guard let prop = IORegistryEntryCreateCFProperty(
      service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
    ) else { return nil }
    return prop.takeRetainedValue() as? Bool
  }
}
