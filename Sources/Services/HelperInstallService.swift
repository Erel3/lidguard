import Cocoa
import os.log
import SwiftUI

@MainActor
final class HelperInstallService {
  static let shared = HelperInstallService()

  enum HelperUpdateMode {
    case required   // version < minHelperVersion
    case optional   // version >= minHelperVersion but < latest GitHub release
  }

  private let settings = SettingsService.shared
  private var isInstalling = false
  private var updateWindow: NSWindow?
  private var periodicTimer: DispatchSourceTimer?
  private var initialCheckDone = false
  var disconnectedForRequiredUpdate = false

  /// Tracks the mode of the currently displayed update window for handleInstall progress view
  private var currentUpdateMode: HelperUpdateMode = .required
  private var currentLatestVersion: String?

  private init() {}

  // MARK: - Periodic Helper Checks

  func startPeriodicHelperChecks() {
    guard settings.autoUpdateEnabled else { return }

    if !initialCheckDone {
      initialCheckDone = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
        self?.checkForHelperUpdates(silent: true)
      }
    }

    schedulePeriodicTimer()
  }

  func stopPeriodicHelperChecks() {
    periodicTimer?.cancel()
    periodicTimer = nil
  }

  private func schedulePeriodicTimer() {
    periodicTimer?.cancel()

    let interval = Config.GitHub.autoCheckInterval
    let delay: TimeInterval

    if let last = settings.lastHelperUpdateCheckDate {
      delay = max(0, interval - Date().timeIntervalSince(last))
    } else {
      delay = interval
    }

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + delay, repeating: interval)
    timer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self = self, self.settings.autoUpdateEnabled else { return }
        self.checkForHelperUpdates(silent: true)
      }
    }
    timer.resume()
    periodicTimer = timer
  }

  // MARK: - Check for Helper Updates

  func checkForHelperUpdates(silent: Bool, completion: (@Sendable () -> Void)? = nil) {
    guard let url = URL(string: Config.Daemon.helperReleasesURL) else {
      completion?()
      return
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("LidGuard/\(Config.App.version)", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 15

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      let hadError = error != nil
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self = self else { completion?(); return }
          self.handleHelperCheckResponse(
            data: data,
            statusCode: statusCode,
            hadError: hadError,
            silent: silent
          )
          completion?()
        }
      }
    }.resume()
  }

  private func handleHelperCheckResponse(data: Data?, statusCode: Int, hadError: Bool, silent: Bool) {
    settings.lastHelperUpdateCheckDate = Date()

    guard !hadError, (200...299).contains(statusCode), let data = data,
          let release = try? JSONDecoder().decode(GitHubReleaseInfo.self, from: data) else {
      if !silent {
        Logger.daemon.error("Failed to check for helper updates")
        showHelperCheckError()
      }
      return
    }

    let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

    guard TheftProtectionService.daemonConnected,
          let currentVersion = TheftProtectionService.daemonVersion else {
      if !silent { showHelperUpToDate() }
      return
    }

    let isRequired = TheftProtectionService.helperNeedsUpdate
    let hasNewerRelease = HelperInstaller.isNewer(latestVersion, than: currentVersion)

    guard isRequired || hasNewerRelease else {
      if !silent { showHelperUpToDate() }
      return
    }

    let mode: HelperUpdateMode = isRequired ? .required : .optional

    if mode == .optional && silent && settings.skippedHelperVersion == latestVersion {
      Logger.daemon.info("Skipping helper update to \(latestVersion) (user skipped)")
      return
    }

    if silent && UpdateService.shared.hasUpdateAvailable {
      Logger.daemon.info("Suppressing helper update notification — app update available")
      return
    }

    showUpdateWindow(currentVersion: currentVersion, latestVersion: latestVersion, mode: mode)
  }

  private func showHelperUpToDate() {
    let alert = NSAlert()
    alert.messageText = "Helper Is Up to Date"
    alert.informativeText = "Helper daemon v\(TheftProtectionService.daemonVersion ?? "?") is the latest version."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func showHelperCheckError() {
    let alert = NSAlert()
    alert.messageText = "Helper Update Check Failed"
    alert.informativeText = "Could not check for helper updates. Please try again later."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // MARK: - Update Window

  func showUpdateWindow(currentVersion: String?, latestVersion: String? = nil, mode: HelperUpdateMode = .required) {
    DispatchQueue.main.async { [self] in
      if let existing = updateWindow, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        return
      }

      currentUpdateMode = mode
      currentLatestVersion = latestVersion

      let view = HelperUpdateView(
        currentVersion: currentVersion ?? "unknown",
        requiredVersion: Config.Daemon.minHelperVersion,
        latestVersion: latestVersion,
        mode: mode,
        isInstalling: false,
        onInstall: { [weak self] in self?.handleInstall() },
        onSkip: mode == .optional ? { [weak self] in
          if let v = latestVersion { self?.settings.skippedHelperVersion = v }
          self?.updateWindow?.close()
        } : nil,
        onDismiss: { [weak self] in
          if mode == .required {
            self?.handleRequiredUpdateDismissed()
          }
          self?.updateWindow?.close()
        }
      )

      let window = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: mode == .optional ? 260 : 240),
        styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
        backing: .buffered,
        defer: false
      )
      window.title = "Helper Update"
      window.contentView = NSHostingView(rootView: view)
      window.center()
      window.isReleasedWhenClosed = false
      window.level = .normal
      window.hidesOnDeactivate = false
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)

      updateWindow = window
    }
  }

  private func handleRequiredUpdateDismissed() {
    disconnectedForRequiredUpdate = true
    NotificationCenter.default.post(name: .helperUpdateDismissed, object: nil)
  }

  private func handleInstall() {
    let progressView = HelperUpdateView(
      currentVersion: TheftProtectionService.daemonVersion ?? "unknown",
      requiredVersion: Config.Daemon.minHelperVersion,
      latestVersion: currentLatestVersion,
      mode: currentUpdateMode,
      isInstalling: true,
      onInstall: {},
      onSkip: nil,
      onDismiss: {}
    )
    updateWindow?.contentView = NSHostingView(rootView: progressView)

    autoInstall { [weak self] success in
      DispatchQueue.main.async {
        self?.updateWindow?.close()
        if !success {
          let alert = NSAlert()
          alert.messageText = "Helper Update Failed"
          alert.informativeText = "Could not update the helper daemon. Check the activity log for details."
          alert.alertStyle = .warning
          alert.addButton(withTitle: "OK")
          alert.runModal()
        }
      }
    }
  }

  // MARK: - Auto-Install

  func autoInstall(completion: (@Sendable (Bool) -> Void)? = nil) {
    guard !isInstalling else { completion?(false); return }
    isInstalling = true
    Task { [weak self] in
      let success = await HelperInstaller.performAutoInstall()
      // Back on the main actor (the enclosing type is @MainActor).
      self?.isInstalling = false
      if success {
        self?.disconnectedForRequiredUpdate = false
        self?.settings.skippedHelperVersion = nil
        NotificationCenter.default.post(name: .helperInstallCompleted, object: nil)
      }
      completion?(success)
    }
  }
}
