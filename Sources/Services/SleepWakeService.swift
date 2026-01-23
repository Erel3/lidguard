import Foundation
import IOKit.pwr_mgt

// IOKit message constants (not exposed to Swift)
private let kIOMessageCanSystemSleep: UInt32 = 0xe0000270
private let kIOMessageSystemWillSleep: UInt32 = 0xe0000280
private let kIOMessageSystemHasPoweredOn: UInt32 = 0xe0000300

protocol SleepWakeDelegate: AnyObject {
  func systemWillSleep()
  func systemDidWake()
  func shouldDenySleep() -> Bool
}

final class SleepWakeService {
  weak var delegate: SleepWakeDelegate?

  private var notificationPort: IONotificationPortRef?
  private var notifierObject: io_object_t = 0
  private var rootPort: io_connect_t = 0

  func start() {
    rootPort = IORegisterForSystemPower(
      Unmanaged.passUnretained(self).toOpaque(),
      &notificationPort,
      powerCallback,
      &notifierObject
    )

    guard rootPort != 0 else {
      print("[SleepWakeService] Failed to register")
      return
    }

    if let port = notificationPort {
      CFRunLoopAddSource(
        CFRunLoopGetCurrent(),
        IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
        .commonModes
      )
    }

    print("[SleepWakeService] Started")
  }

  func stop() {
    if notifierObject != 0 {
      IODeregisterForSystemPower(&notifierObject)
      notifierObject = 0
    }
    if let port = notificationPort {
      IONotificationPortDestroy(port)
      notificationPort = nil
    }
    rootPort = 0
  }

  fileprivate func handlePower(_ type: UInt32, _ arg: UnsafeMutableRawPointer?) {
    switch type {
    case kIOMessageSystemWillSleep:
      print("[SleepWakeService] Will sleep")
      delegate?.systemWillSleep()
      IOAllowPowerChange(rootPort, Int(bitPattern: arg))

    case kIOMessageSystemHasPoweredOn:
      print("[SleepWakeService] Did wake")
      delegate?.systemDidWake()

    case kIOMessageCanSystemSleep:
      if delegate?.shouldDenySleep() == true {
        IOCancelPowerChange(rootPort, Int(bitPattern: arg))
      } else {
        IOAllowPowerChange(rootPort, Int(bitPattern: arg))
      }

    default:
      break
    }
  }
}

private func powerCallback(
  refCon: UnsafeMutableRawPointer?,
  service: io_service_t,
  messageType: UInt32,
  messageArgument: UnsafeMutableRawPointer?
) {
  guard let refCon = refCon else { return }
  Unmanaged<SleepWakeService>.fromOpaque(refCon)
    .takeUnretainedValue()
    .handlePower(messageType, messageArgument)
}
