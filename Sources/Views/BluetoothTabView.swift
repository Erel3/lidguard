import KeyboardShortcuts
import SwiftUI

struct BluetoothTabView: View {
  @Binding var bluetoothAutoArmEnabled: Bool
  @Binding var bluetoothArmGracePeriod: Double
  @Binding var lockScreenOnBluetoothArm: Bool
  @Binding var trustedBLEDevices: [TrustedBLEDevice]
  var isDaemonConnected: Bool

  var body: some View {
    Form {
      Section {
        Toggle("Enable Bluetooth auto-arm", isOn: $bluetoothAutoArmEnabled)
        if bluetoothAutoArmEnabled {
          HelperToggle("Lock screen when auto-arming", isOn: $lockScreenOnBluetoothArm, isDaemonConnected: isDaemonConnected)
        }
      } header: {
        Text("Auto-Arm")
      } footer: {
        Text("Automatically arms protection when all trusted Bluetooth devices leave range, and disarms when any returns.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        KeyboardShortcuts.Recorder("Shortcut", name: .toggleBluetooth)
      } header: {
        Text("Global Keyboard Shortcut")
      } footer: {
        Text("Press the shortcut anywhere to toggle Bluetooth auto-arm. Requires Input Monitoring permission.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if bluetoothAutoArmEnabled {
        Section {
          LabeledContent("Arm delay") {
            HStack {
              Slider(value: $bluetoothArmGracePeriod, in: 60...300, step: 10)
              Text("\(Int(bluetoothArmGracePeriod))s")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            }
          }
        } header: {
          Text("Arm Delay")
        }

        Section {
          BluetoothDevicePickerView(trustedDevices: $trustedBLEDevices)
        } header: {
          Text("Devices")
        }
      }
    }
    .formStyle(.grouped)
  }
}
