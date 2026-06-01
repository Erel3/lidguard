import Cocoa
import os.log
import SwiftUI

@MainActor
final class UpdateService {
  static let shared = UpdateService()

  private let settings = SettingsService.shared
  private let logger = Logger.update
  private var periodicTimer: DispatchSourceTimer?
  private var updateWindow: NSWindow?
  private var initialCheckDone = false
  private(set) var hasUpdateAvailable = false

  private init() {}

  // MARK: - Periodic Checks

  func startPeriodicChecks() {
    guard settings.autoUpdateEnabled else { return }
    #if DEBUG
    // In DEBUG the bundled CFBundleShortVersionString can be a stub like "1.0"
    // which would make us think we're wildly behind and self-overwrite the dev
    // binary with a release build. Skip entirely.
    logger.info("Auto-update disabled in DEBUG build")
    return
    #else

    if !initialCheckDone {
      initialCheckDone = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
        self?.checkForUpdates(silent: true)
      }
    }

    schedulePeriodicTimer()
    #endif
  }

  func stopPeriodicChecks() {
    periodicTimer?.cancel()
    periodicTimer = nil
  }

  private func schedulePeriodicTimer() {
    periodicTimer?.cancel()

    let interval = Config.GitHub.autoCheckInterval
    let delay: TimeInterval

    if let last = settings.lastUpdateCheckDate {
      delay = max(0, interval - Date().timeIntervalSince(last))
    } else {
      delay = interval
    }

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + delay, repeating: interval)
    timer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self = self, self.settings.autoUpdateEnabled else { return }
        self.checkForUpdates(silent: true)
      }
    }
    timer.resume()
    periodicTimer = timer
  }

  // MARK: - Check for Updates

  private func logAndShowError(_ message: String, silent: Bool) {
    logger.error("\(message)")
    if !silent {
      showError(message)
    }
  }

  func checkForUpdates(silent: Bool, completion: (@Sendable () -> Void)? = nil) {
    guard let url = URL(string: Config.GitHub.releasesURL) else {
      completion?()
      return
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("LidGuard/\(Config.App.version)", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 15

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      let errorMessage = error?.localizedDescription
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self = self else { completion?(); return }
          self.handleCheckResponse(
            data: data,
            statusCode: statusCode,
            errorMessage: errorMessage,
            silent: silent
          )
          completion?()
        }
      }
    }.resume()
  }

  private func handleCheckResponse(data: Data?, statusCode: Int, errorMessage: String?, silent: Bool) {
    settings.lastUpdateCheckDate = Date()

    if let errorMessage {
      logAndShowError("Could not reach GitHub: \(errorMessage)", silent: silent)
      return
    }

    guard (200...299).contains(statusCode), let data = data else {
      logAndShowError("Update check HTTP error: \(statusCode)", silent: silent)
      return
    }

    let releases: [GitHubRelease]
    do {
      releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
    } catch {
      logAndShowError("Could not parse GitHub response: \(error)", silent: silent)
      return
    }

    let localVersion = Config.App.version
    let newerReleases = releases.filter { isNewer($0.version, than: localVersion) }
      .sorted { isNewer($0.version, than: $1.version) }  // newest first

    guard let latest = newerReleases.first else {
      logger.info("App is up to date (\(localVersion))")
      if !silent { showUpToDate() }
      return
    }

    if silent && settings.skippedVersion == latest.version {
      logger.info("Skipping update to \(latest.version) (user skipped)")
      return
    }

    let combinedChangelog = newerReleases.map { release in
      let header = "## v\(release.version)"
      let body = release.body ?? "No release notes."
      return "\(header)\n\(body)"
    }.joined(separator: "\n\n")

    hasUpdateAvailable = true
    showUpdateWindow(release: latest, changelog: combinedChangelog)
  }

  private func showUpdateWindow(release: GitHubRelease, changelog: String) {
    if let existing = updateWindow, existing.isVisible {
      existing.makeKeyAndOrderFront(nil)
      return
    }

    let view = UpdateView(
      version: release.version,
      changelog: changelog,
      onInstall: { [weak self] in
        self?.installUpdate(release: release, changelog: changelog)
      },
      onSkip: { [weak self] in
        self?.hasUpdateAvailable = false
        self?.settings.skippedVersion = release.version
        self?.updateWindow?.close()
      },
      onDismiss: { [weak self] in
        self?.hasUpdateAvailable = false
        self?.updateWindow?.close()
      }
    )

    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
      styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
      backing: .buffered,
      defer: false
    )
    window.title = "Software Update"
    window.contentView = NSHostingView(rootView: view)
    window.center()
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.hidesOnDeactivate = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    updateWindow = window
  }

  // MARK: - Install

  private func installUpdate(release: GitHubRelease, changelog: String) {
    guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
          let downloadURL = URL(string: asset.browserDownloadURL) else {
      showError("No download found in this release.")
      return
    }

    // Update the view to show progress
    if let window = updateWindow {
      let progressView = UpdateView(
        version: release.version,
        changelog: changelog,
        isInstalling: true,
        onInstall: {},
        onSkip: {},
        onDismiss: {}
      )
      window.contentView = NSHostingView(rootView: progressView)
    }

    let version = release.version
    let downloadDest = downloadURL
    Task { [weak self] in
      do {
        let currentAppURL = try await Self.performInstall(from: downloadDest)
        // Back on the main actor (enclosing type is @MainActor).
        ActivityLog.logAsync(.system, "Update to v\(version) installed")
        self?.hasUpdateAvailable = false
        self?.settings.skippedVersion = nil
        self?.restartApp(at: currentAppURL)
      } catch {
        self?.logger.error("Update failed: \(error.localizedDescription)")
        self?.updateWindow?.close()
        self?.showError("Update failed: \(error.localizedDescription)")
      }
    }
  }

  /// Downloads, verifies (codesign team-ID pinned), and atomically swaps in the
  /// new bundle, returning the current bundle URL to relaunch. Runs off the main
  /// actor and never blocks a thread.
  nonisolated private static func performInstall(from downloadURL: URL) async throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lidguard-update-\(UUID().uuidString)")
    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      let zipPath = tempDir.appendingPathComponent("LidGuard.zip")

      try await downloadFile(from: downloadURL, to: zipPath)
      let newAppURL = try await unzipAndVerify(zipPath: zipPath, in: tempDir)

      let currentAppURL = Bundle.main.bundleURL
      let staging = tempDir.appendingPathComponent("LidGuard-staged.app")
      try FileManager.default.moveItem(at: newAppURL, to: staging)

      try FileManager.default.replaceItem(
        at: currentAppURL,
        withItemAt: staging,
        backupItemName: "LidGuard-backup.app",
        options: .usingNewMetadataOnly,
        resultingItemURL: nil
      )

      try? FileManager.default.removeItem(at: tempDir)
      return currentAppURL
    } catch {
      try? FileManager.default.removeItem(at: tempDir)
      throw error
    }
  }

  nonisolated private static func downloadFile(from url: URL, to destination: URL) async throws {
    let (localURL, response) = try await URLSession.shared.download(from: url)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      throw NSError(domain: "UpdateService", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Download HTTP error: \(http.statusCode)"])
    }
    try FileManager.default.moveItem(at: localURL, to: destination)
  }

  nonisolated private static func unzipAndVerify(zipPath: URL, in tempDir: URL) async throws -> URL {
    let unzipDir = tempDir.appendingPathComponent("unzipped")
    try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzip.arguments = ["-q", zipPath.path, "-d", unzipDir.path]
    try await unzip.runToCompletion()

    guard unzip.terminationStatus == 0 else {
      throw NSError(domain: "UpdateService", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to unzip update"])
    }

    let contents = try FileManager.default.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)
    guard let newAppURL = contents.first(where: { $0.lastPathComponent == "LidGuard.app" }) else {
      throw NSError(domain: "UpdateService", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "LidGuard.app not found in zip"])
    }

    let codesign = Process()
    codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    codesign.arguments = [
      "--verify", "--deep", "--strict",
      "-R=\(Config.App.designatedRequirement)",
      newAppURL.path
    ]
    try await codesign.runToCompletion()
    guard codesign.terminationStatus == 0 else {
      throw NSError(domain: "UpdateService", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Code signature verification failed"])
    }

    return newAppURL
  }

  private func restartApp(at appURL: URL) {
    let pid = ProcessInfo.processInfo.processIdentifier
    let escapedPath = appURL.path.replacingOccurrences(of: "'", with: "'\\''")
    let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open '\(escapedPath)'"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", script]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      logger.error("Failed to launch restart: \(error.localizedDescription)")
      showError("Update installed. Please relaunch LidGuard manually.")
      return
    }

    ActivityLog.logAsync(.system, "Restarting for update")

    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.allowQuitForUpdate()
    } else {
      exit(0)
    }
    NSApp.terminate(nil)
  }

  // MARK: - Version Comparison

  nonisolated private func isNewer(_ remote: String, than local: String) -> Bool {
    let (rCore, rPre) = splitPrerelease(remote)
    let (lCore, lPre) = splitPrerelease(local)
    let count = max(rCore.count, lCore.count)
    for i in 0..<count {
      let rv = i < rCore.count ? rCore[i] : 0
      let lv = i < lCore.count ? lCore[i] : 0
      if rv != lv { return rv > lv }
    }
    // Cores equal — prerelease < release per semver. 1.2.3-beta.1 < 1.2.3.
    switch (rPre, lPre) {
    case (nil, nil): return false
    case (nil, _?): return true    // remote release newer than local prerelease
    case (_?, nil): return false   // remote prerelease older than local release
    case let (r?, l?): return r > l
    }
  }

  nonisolated private func splitPrerelease(_ v: String) -> ([Int], String?) {
    let stripped = v.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    let comps = stripped.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    let coreStr = comps.first.map(String.init) ?? stripped
    let core = coreStr.split(separator: ".").compactMap { Int($0) }
    let pre = comps.count > 1 ? String(comps[1]) : nil
    return (core, pre)
  }

  // MARK: - Alerts

  private func showUpToDate() {
    let alert = NSAlert()
    alert.messageText = "You're Up to Date"
    alert.informativeText = "LidGuard \(Config.App.version) is the latest version."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Update Error"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}

// MARK: - API Models

private struct GitHubReleaseAsset: Decodable, Sendable {
  let name: String
  let browserDownloadURL: String

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
  }
}

private struct GitHubRelease: Decodable, Sendable {
  let tagName: String
  let body: String?
  let assets: [GitHubReleaseAsset]

  var version: String {
    tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
  }

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case body
    case assets
  }
}
