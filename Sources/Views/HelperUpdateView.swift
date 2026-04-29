import SwiftUI

struct HelperUpdateView: View {
  let currentVersion: String
  let requiredVersion: String
  var latestVersion: String?
  var mode: HelperInstallService.HelperUpdateMode = .required
  var isInstalling: Bool = false
  let onInstall: () -> Void
  var onSkip: (() -> Void)?
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      VStack(spacing: 8) {
        Image(systemName: mode == .required ? "arrow.triangle.2.circlepath" : "arrow.up.circle")
          .font(.system(size: 40))
          .foregroundStyle(mode == .required ? .orange : .blue)

        Text(mode == .required ? "Helper Update Required" : "Helper Update Available")
          .font(.headline)

        if mode == .required {
          Text("Installed: v\(currentVersion) — Required: v\(requiredVersion)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if let latest = latestVersion {
          Text("Installed: v\(currentVersion) — Latest: v\(latest)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Text(mode == .required
        ? "LidGuard requires a newer version of the helper daemon for full functionality. Some features may not work until the helper is updated."
        : "A newer version of the helper daemon is available.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding(.horizontal)

      Spacer()

      if isInstalling {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Updating helper...")
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
      } else {
        HStack(spacing: 12) {
          Button("Not Now") { onDismiss() }
            .keyboardShortcut(.cancelAction)

          if mode == .optional, let onSkip {
            Button("Skip This Version") { onSkip() }
          }

          if #available(macOS 26.0, *) {
            Button("Update Helper") { onInstall() }
              .keyboardShortcut(.defaultAction)
              .buttonStyle(.glassProminent)
          } else {
            Button("Update Helper") { onInstall() }
              .keyboardShortcut(.defaultAction)
          }
        }
        .padding(.bottom, 4)
      }
    }
    .padding(20)
    .frame(width: 400, height: mode == .optional ? 260 : 240)
  }
}
