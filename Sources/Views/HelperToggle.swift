import SwiftUI

/// A toggle for a setting that depends on the privileged helper daemon.
/// When the daemon is disconnected the row is disabled and annotated
/// "(requires Helper)". Shared across the settings tab views.
struct HelperToggle: View {
  private let title: String
  @Binding private var isOn: Bool
  private let isDaemonConnected: Bool

  init(_ title: String, isOn: Binding<Bool>, isDaemonConnected: Bool) {
    self.title = title
    self._isOn = isOn
    self.isDaemonConnected = isDaemonConnected
  }

  var body: some View {
    Toggle(isOn: $isOn) {
      HStack(spacing: 6) {
        Text(title)
        if !isDaemonConnected {
          Text("(requires Helper)")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
    }
    .disabled(!isDaemonConnected)
  }
}
