import AVFoundation
import os.log

final class AlarmAudioManager {
  static let shared = AlarmAudioManager()

  private var player: AVAudioPlayer?
  private var originalVolume: Float = 0.5
  private(set) var isPlaying = false

  private init() {}

  func play() {
    guard !isPlaying else { return }
    isPlaying = true

    // Save and max volume
    originalVolume = getSystemVolume()
    setSystemVolume(1.0)

    // Use selected system sound
    let soundName = SettingsService.shared.alarmSound
    let url = URL(fileURLWithPath: "/System/Library/Sounds/\(soundName).aiff")
    guard FileManager.default.fileExists(atPath: url.path) else {
      Logger.system.error("Alarm sound not found: \(soundName)")
      isPlaying = false
      return
    }

    do {
      player = try AVAudioPlayer(contentsOf: url)
      player?.numberOfLoops = -1  // Loop forever
      player?.play()
      Logger.system.info("Alarm started: \(soundName)")
      ActivityLog.logAsync(.system, "Alarm started: \(soundName)")
    } catch {
      Logger.system.error("Failed to play alarm: \(error.localizedDescription)")
      isPlaying = false
    }
  }

  func stop() {
    guard isPlaying else { return }
    isPlaying = false

    player?.stop()
    player = nil
    setSystemVolume(originalVolume)

    Logger.system.info("Alarm stopped")
    ActivityLog.logAsync(.system, "Alarm stopped")
  }

  private func setSystemVolume(_ volume: Float) {
    let script = "set volume output volume \(Int(volume * 100))"
    var error: NSDictionary?
    NSAppleScript(source: script)?.executeAndReturnError(&error)
  }

  private func getSystemVolume() -> Float {
    let script = "output volume of (get volume settings)"
    var error: NSDictionary?
    guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error) else {
      return 0.5
    }
    return Float(result.int32Value) / 100.0
  }
}
