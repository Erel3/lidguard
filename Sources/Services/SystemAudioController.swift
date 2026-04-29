import AudioToolbox
import CoreAudio
import Foundation
import os.log

@MainActor
final class SystemAudioController {
  private static let savedVolumeKey = "AlarmAudioManager.savedSystemVolume"

  private var savedSystemVolume: Float?
  private var savedDefaultOutputDevice: AudioObjectID = 0
  private var didSwitchOutput = false
  private var monitoredDeviceID: AudioObjectID = 0
  private var volumeListenerBlock: AudioObjectPropertyListenerBlock?

  /// Restore stale persisted volume (after crash mid-alarm).
  func restoreSystemVolumeIfNeeded() {
    guard UserDefaults.standard.object(forKey: Self.savedVolumeKey) != nil else { return }
    let volume = UserDefaults.standard.float(forKey: Self.savedVolumeKey)
    setSystemVolume(volume)
    clearPersistedVolume()
    Logger.system.info("Restored system volume to \(String(format: "%.0f%%", volume * 100)) after previous session")
  }

  /// Snapshot current volume, max it, route to built-in speakers, start enforcement.
  func captureAndMaximize(isActive: @escaping @MainActor () -> Bool) {
    routeToBuiltInSpeakers()
    savedSystemVolume = getSystemVolume()
    persistSavedVolume(savedSystemVolume)
    setSystemVolume(1.0)
    startVolumeMonitoring(isActive: isActive)
  }

  /// Stop enforcement, restore prior volume + output device.
  func restore() {
    stopVolumeMonitoring()
    if let saved = savedSystemVolume {
      setSystemVolume(saved)
      savedSystemVolume = nil
      clearPersistedVolume()
    }
    restoreDefaultOutputDevice()
  }

  // MARK: - System Volume

  private func getSystemVolume() -> Float? {
    var deviceID = AudioObjectID(kAudioObjectSystemObject)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    )
    guard status == noErr else {
      Logger.system.error("Failed to get default output device: OSStatus \(status)")
      return nil
    }

    var volume: Float32 = 0
    size = UInt32(MemoryLayout<Float32>.size)
    address.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    address.mScope = kAudioDevicePropertyScopeOutput
    let volStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
    guard volStatus == noErr else {
      Logger.system.error("Failed to read system volume: OSStatus \(volStatus)")
      return nil
    }
    return volume
  }

  private func setSystemVolume(_ volume: Float) {
    var deviceID = AudioObjectID(kAudioObjectSystemObject)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    )
    guard status == noErr else {
      Logger.system.error("Failed to get default output device for volume set: OSStatus \(status)")
      return
    }

    var vol = volume
    size = UInt32(MemoryLayout<Float32>.size)
    address.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    address.mScope = kAudioDevicePropertyScopeOutput
    let setStatus = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
    if setStatus != noErr {
      Logger.system.error("Failed to set system volume: OSStatus \(setStatus)")
    }
  }

  private func persistSavedVolume(_ volume: Float?) {
    guard let volume = volume else { return }
    UserDefaults.standard.set(volume, forKey: Self.savedVolumeKey)
  }

  private func clearPersistedVolume() {
    UserDefaults.standard.removeObject(forKey: Self.savedVolumeKey)
  }

  // MARK: - Output Routing

  /// Routes audio to built-in speakers so siren isn't sent to AirPods/USB DAC/HDMI.
  private func routeToBuiltInSpeakers() {
    guard let builtin = findBuiltInOutputDevice() else { return }

    var currentDefault = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let getStatus = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &currentDefault
    )
    guard getStatus == noErr else { return }

    if currentDefault == builtin {
      return
    }

    var newDefault = builtin
    let setStatus = AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
      UInt32(MemoryLayout<AudioObjectID>.size), &newDefault
    )
    if setStatus == noErr {
      savedDefaultOutputDevice = currentDefault
      didSwitchOutput = true
      Logger.system.info("Alarm: routed audio to built-in speakers")
    } else {
      Logger.system.error("Alarm: failed to switch to built-in output (OSStatus \(setStatus))")
    }
  }

  private func restoreDefaultOutputDevice() {
    guard didSwitchOutput, savedDefaultOutputDevice != 0 else {
      savedDefaultOutputDevice = 0
      didSwitchOutput = false
      return
    }
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var prev = savedDefaultOutputDevice
    let setStatus = AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
      UInt32(MemoryLayout<AudioObjectID>.size), &prev
    )
    if setStatus != noErr {
      Logger.system.error("Alarm: failed to restore prior output (OSStatus \(setStatus))")
    }
    savedDefaultOutputDevice = 0
    didSwitchOutput = false
  }

  private func findBuiltInOutputDevice() -> AudioObjectID? {
    var size: UInt32 = 0
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
    ) == noErr, size > 0 else { return nil }

    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var devices = [AudioObjectID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
    ) == noErr else { return nil }

    for device in devices where isBuiltInOutputDevice(device) {
      return device
    }
    return nil
  }

  private func isBuiltInOutputDevice(_ device: AudioObjectID) -> Bool {
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var tAddr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(device, &tAddr, 0, nil, &size, &transport) == noErr,
          transport == kAudioDeviceTransportTypeBuiltIn else {
      return false
    }

    var streamsSize: UInt32 = 0
    var sAddr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyDataSize(device, &sAddr, 0, nil, &streamsSize) == noErr else {
      return false
    }
    return streamsSize > 0
  }

  // MARK: - Volume Enforcement

  /// Snap volume back to max whenever it changes during alarm.
  private func startVolumeMonitoring(isActive: @escaping @MainActor () -> Bool) {
    var deviceID = AudioObjectID(kAudioObjectSystemObject)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    ) == noErr else { return }

    monitoredDeviceID = deviceID

    // Listener block fires on .main DispatchQueue, which is NOT the @MainActor isolation domain
    // under Swift 6 — hop via DispatchQueue.main.async before MainActor.assumeIsolated.
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self, isActive() else { return }
          if let current = self.getSystemVolume(), current < 1.0 {
            self.setSystemVolume(1.0)
          }
        }
      }
    }
    volumeListenerBlock = block

    var volAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectAddPropertyListenerBlock(deviceID, &volAddress, .main, block)
  }

  private func stopVolumeMonitoring() {
    guard monitoredDeviceID != 0, let block = volumeListenerBlock else { return }

    var volAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectRemovePropertyListenerBlock(monitoredDeviceID, &volAddress, .main, block)
    monitoredDeviceID = 0
    volumeListenerBlock = nil
  }
}
