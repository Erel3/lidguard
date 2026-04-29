import SwiftUI

struct GeneralTabView: View {
  @Binding var startAtLogin: Bool
  @Binding var biometricAuthEnabled: Bool
  @Binding var autoUpdateEnabled: Bool
  @Binding var showingResetConfirmation: Bool

  var isCheckingForUpdates: Bool
  var isInstallingHelper: Bool
  var helperInstallResult: Bool?
  var isDaemonConnected: Bool
  var daemonVersion: String?
  var helperNeedsUpdate: Bool
  var helperDisconnectedForUpdate: Bool
  var isCheckingForHelperUpdates: Bool

  var onToggleLoginItem: (Bool) -> Void
  var onCheckForUpdates: () -> Void
  var onInstallHelper: () -> Void
  var onCheckForHelperUpdates: () -> Void

  var body: some View {
    Form {
      Section {
        Toggle("Start at Login", isOn: $startAtLogin)
          .onChange(of: startAtLogin) { _, newValue in
            onToggleLoginItem(newValue)
          }
      } header: {
        Text("Launch")
      }

      Section {
        Toggle("Require Touch ID", isOn: $biometricAuthEnabled)
      } header: {
        Text("Security")
      } footer: {
        Text("Require Touch ID or password to disable protection, open settings, and quit.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        Toggle("Automatically check for updates", isOn: $autoUpdateEnabled)
        HStack {
          Spacer()
          updatesButton
          Spacer()
        }
      } header: {
        Text("Updates")
      }

      Section {
        helperStatusRow
        if !isDaemonConnected || helperNeedsUpdate {
          HStack {
            Spacer()
            Button(helperNeedsUpdate || helperDisconnectedForUpdate ? "Update Helper" : "Install Helper") {
              onInstallHelper()
            }
            .font(.callout)
            .disabled(isInstallingHelper)
            Spacer()
          }
        }
        if isDaemonConnected && !helperNeedsUpdate && !isInstallingHelper {
          HStack {
            Spacer()
            helperUpdateCheckButton
            Spacer()
          }
        }
      } header: {
        Text("Helper Daemon")
      } footer: {
        Text("Required for power button detection, lock screen overlay, and pmset sleep prevention.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        HStack {
          Spacer()
          if #available(macOS 26.0, *) {
            Button("Reset All Settings", role: .destructive) {
              showingResetConfirmation = true
            }
            .buttonStyle(.glass)
          } else {
            Button("Reset All Settings", role: .destructive) {
              showingResetConfirmation = true
            }
            .buttonStyle(.borderless)
          }
          Spacer()
        }
      }

      Section {
        HStack {
          Spacer()
          Text("\(Config.App.name) v\(Config.App.version)")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Spacer()
        }
      }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder
  private var updatesButton: some View {
    let title = isCheckingForUpdates ? "Checking..." : "Check for Updates"
    if #available(macOS 26.0, *) {
      Button(title) { onCheckForUpdates() }
        .buttonStyle(.glass)
        .disabled(isCheckingForUpdates)
    } else {
      Button(title) { onCheckForUpdates() }
        .buttonStyle(.borderless)
        .disabled(isCheckingForUpdates)
    }
  }

  @ViewBuilder
  private var helperStatusRow: some View {
    HStack {
      if isInstallingHelper {
        ProgressView()
          .controlSize(.small)
        Text("Installing Helper...")
      } else if helperInstallResult == true {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Text("Helper Installed Successfully")
      } else if helperInstallResult == false {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.red)
        Text("Helper Install Failed")
      } else if helperNeedsUpdate {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Helper Outdated (v\(daemonVersion ?? "?"), requires v\(Config.Daemon.minHelperVersion))")
      } else if isDaemonConnected {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Text("Helper Connected (v\(daemonVersion ?? "?"))")
      } else if helperDisconnectedForUpdate {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.orange)
        Text("Disconnected — helper too old (requires v\(Config.Daemon.minHelperVersion))")
      } else {
        Image(systemName: "xmark.circle")
          .foregroundStyle(.secondary)
        Text("Helper Not Connected")
        Text("(requires v\(Config.Daemon.minHelperVersion)+)")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var helperUpdateCheckButton: some View {
    let title = isCheckingForHelperUpdates ? "Checking..." : "Check for Helper Updates"
    if #available(macOS 26.0, *) {
      Button(title) { onCheckForHelperUpdates() }
        .buttonStyle(.glass).disabled(isCheckingForHelperUpdates).font(.callout)
    } else {
      Button(title) { onCheckForHelperUpdates() }
        .buttonStyle(.borderless).disabled(isCheckingForHelperUpdates).font(.callout)
    }
  }
}
