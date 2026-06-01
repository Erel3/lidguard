import Foundation
import os.log

struct GitHubReleaseInfo: Decodable, Sendable {
  let tagName: String
  let assets: [GitHubAsset]

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case assets
  }
}

struct GitHubAsset: Decodable, Sendable {
  let name: String
  let browserDownloadURL: String

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
  }
}

enum HelperInstaller {
  static func performAutoInstall() async -> Bool {
    Logger.daemon.info("Auto-installing helper daemon...")
    ActivityLog.logAsync(.system, "Auto-installing helper daemon...")

    guard let url = URL(string: Config.Daemon.helperReleasesURL) else { return false }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("LidGuard/\(Config.App.version)", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 30

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        Logger.daemon.error("Failed to fetch helper release info")
        ActivityLog.logAsync(.system, "Helper auto-install failed: could not fetch release info")
        return false
      }

      guard let release = try? JSONDecoder().decode(GitHubReleaseInfo.self, from: data),
            let asset = release.assets.first(where: { isValidHelperAssetName($0.name) }),
            let downloadURL = URL(string: asset.browserDownloadURL) else {
        Logger.daemon.error("No suitable asset found in helper release")
        ActivityLog.logAsync(.system, "Helper auto-install failed: no suitable asset")
        return false
      }

      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidguard-helper-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: tempDir) }

      let pkgPath = tempDir.appendingPathComponent(asset.name)
      try await downloadFile(from: downloadURL, to: pkgPath)
      try await verifyPkgSignature(at: pkgPath)

      await unloadDaemon()
      try? await Task.sleep(nanoseconds: 1_000_000_000)

      // Path passed as argv[1] — never interpolated into the shell command body.
      // `quoted form of` produces shell-safe single-quoted form, blocking $(),
      // backticks, and variable expansion.
      let script = """
      on run argv
        do shell script "/usr/sbin/installer -pkg " & quoted form of (item 1 of argv) & " -target /" with administrator privileges
      end run
      """
      let installer = Process()
      installer.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      installer.arguments = ["-e", script, pkgPath.path]
      installer.standardOutput = FileHandle.nullDevice
      installer.standardError = FileHandle.nullDevice
      try await installer.runToCompletion()

      guard installer.terminationStatus == 0 else {
        throw NSError(domain: "HelperInstall", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PKG installer exited with status \(installer.terminationStatus)"])
      }

      Logger.daemon.info("Helper daemon installed successfully")
      ActivityLog.logAsync(.system, "Helper daemon installed successfully")
      return true
    } catch {
      Logger.daemon.error("Helper install failed: \(error.localizedDescription)")
      ActivityLog.logAsync(.system, "Helper auto-install failed: \(error.localizedDescription)")
      return false
    }
  }

  /// Allowlist for helper PKG asset filenames published on GitHub Releases.
  /// Format: `lidguard-helper-MAJOR[.MINOR[.PATCH]].pkg` — must match the
  /// pattern produced by lidguard-helper/justfile `_pkg` target.
  /// Blocks shell-metacharacter filenames before any filesystem/exec use.
  static func isValidHelperAssetName(_ name: String) -> Bool {
    let pattern = #"^lidguard-helper-[0-9]+(\.[0-9]+){0,2}\.pkg$"#
    return name.range(of: pattern, options: .regularExpression) != nil
  }

  /// Verify a downloaded PKG was signed with our Developer ID Installer cert.
  /// Mirrors AuthManager's team-ID pin in the helper daemon: defense against
  /// a release-channel compromise serving a PKG signed under a different cert.
  private static func verifyPkgSignature(at path: URL) async throws {
    let pkgutil = Process()
    pkgutil.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
    pkgutil.arguments = ["--check-signature", path.path]
    let pipe = Pipe()
    pkgutil.standardOutput = pipe
    pkgutil.standardError = FileHandle.nullDevice
    try await pkgutil.runToCompletion()

    guard pkgutil.terminationStatus == 0 else {
      throw NSError(domain: "HelperInstall", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "PKG signature invalid"])
    }
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard out.contains("(\(Config.App.teamID))") else {
      throw NSError(domain: "HelperInstall", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "PKG not signed by expected team ID"])
    }
  }

  private static func downloadFile(from url: URL, to destination: URL) async throws {
    let (localURL, response) = try await URLSession.shared.download(from: url)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      throw NSError(domain: "HelperInstall", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Download HTTP error: \(http.statusCode)"])
    }
    try FileManager.default.moveItem(at: localURL, to: destination)
  }

  private static func unloadDaemon() async {
    let plistDst = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(Config.Daemon.launchAgentLabel).plist")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["bootout", "gui/\(getuid())", plistDst.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? await process.runToCompletion()
  }

  static func isNewer(_ remote: String, than local: String) -> Bool {
    func parts(_ v: String) -> [Int] {
      let clean = v.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
      return clean.split(separator: ".").compactMap { Int($0) }
    }
    let r = parts(remote), l = parts(local)
    let count = max(r.count, l.count)
    for i in 0..<count {
      let rv = i < r.count ? r[i] : 0
      let lv = i < l.count ? l[i] : 0
      if rv != lv { return rv > lv }
    }
    return false
  }
}
