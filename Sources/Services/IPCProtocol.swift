import Foundation

// IPC WIRE CONTRACT — must stay field-compatible with the same file in the
// helper repo: lidguard-helper/Sources/IPCProtocol.swift. The two are duplicated
// (not shared via an SPM package) because the app and helper are built and
// distributed as independent repositories. Keep IPCCommand and IPCMessage
// byte-compatible across both — a field mismatch fails JSON decoding silently.

// MARK: - Outgoing Commands (App -> Daemon)

struct IPCCommand: Codable, Sendable {
  let type: String
  var contactName: String?
  var contactPhone: String?
  var message: String?
}

// MARK: - Incoming Messages (Daemon -> App)

struct IPCMessage: Codable, Sendable {
  let type: String
  var success: Bool?
  var version: String?
  var pmset: Bool?
  var lockScreen: Bool?
  var powerButton: Bool?
  var accessibilityGranted: Bool?
  var motion: Bool?
  var motionSupported: Bool?
  var motionDetail: String?
  var motionSession: UInt64?
  var message: String?
}
