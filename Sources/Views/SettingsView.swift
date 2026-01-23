import Contacts
import SwiftUI

struct SettingsView: View {
  @State private var contactName: String = ""
  @State private var contactPhone: String = ""

  @State private var telegramBotToken: String = ""
  @State private var telegramChatId: String = ""
  @State private var telegramEnabled: Bool = true

  @State private var pushoverUserKey: String = ""
  @State private var pushoverApiToken: String = ""
  @State private var pushoverEnabled: Bool = true

  @State private var showingResetConfirmation = false
  @State private var startAtLogin: Bool = false
  @State private var sleepPreventionInstalled: Bool = false
  @State private var selectedAlarmSound: String = "Sosumi"
  @Environment(\.dismiss) private var dismiss

  private let alarmSounds = [
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
    "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
    "Submarine", "Tink"
  ]

  private let settings = SettingsService.shared
  private let pmset = PmsetService.shared
  private let loginItem = LoginItemService.shared

  var body: some View {
    Form {
      Section {
        LabeledContent("Name") {
          TextField("", text: $contactName)
            .textFieldStyle(.plain)
        }
        LabeledContent("Phone") {
          TextField("", text: $contactPhone)
            .textFieldStyle(.plain)
        }
        LabeledContent {
          Button("Retrieve from Contacts") {
            retrieveFromContacts()
          }
          .buttonStyle(.borderless)
        } label: {
          EmptyView()
        }
      } header: {
        Text("Contact Information")
      }

      Section {
        LabeledContent("Bot Token") {
          SecureField("", text: $telegramBotToken)
            .textFieldStyle(.plain)
        }
        LabeledContent("Chat ID") {
          TextField("", text: $telegramChatId)
            .textFieldStyle(.plain)
        }
        Toggle("Enable notifications", isOn: $telegramEnabled)
      } header: {
        Text("Telegram")
      }

      Section {
        LabeledContent("User Key") {
          SecureField("", text: $pushoverUserKey)
            .textFieldStyle(.plain)
        }
        LabeledContent("API Token") {
          SecureField("", text: $pushoverApiToken)
            .textFieldStyle(.plain)
        }
        Toggle("Enable notifications", isOn: $pushoverEnabled)
      } header: {
        Text("Pushover")
      }

      Section {
        Toggle("Start at Login", isOn: $startAtLogin)
          .onChange(of: startAtLogin) { _, newValue in
            toggleLoginItem(newValue)
          }
        LabeledContent("Sleep Prevention") {
          Button(sleepPreventionInstalled ? "Uninstall" : "Install") {
            toggleSleepPrevention()
          }
          .buttonStyle(.borderless)
        }
        Picker("Alarm Sound", selection: $selectedAlarmSound) {
          ForEach(alarmSounds, id: \.self) { sound in
            Text(sound).tag(sound)
          }
        }
        .onChange(of: selectedAlarmSound) { _, newValue in
          NSSound(named: newValue)?.play()
        }
      } header: {
        Text("System")
      }

      Section {
        HStack {
          Spacer()
          Button("Reset All Settings", role: .destructive) {
            showingResetConfirmation = true
          }
          .buttonStyle(.borderless)
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
    .frame(width: 400, height: 560)
    .onAppear(perform: loadSettings)
    .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Reset", role: .destructive) {
        resetSettings()
      }
    } message: {
      Text("This will clear all stored credentials and preferences.")
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          saveSettings()
          dismiss()
        }
      }
    }
  }

  private func loadSettings() {
    contactName = settings.contactName ?? ""
    contactPhone = settings.contactPhone ?? ""
    telegramBotToken = settings.telegramBotToken ?? ""
    telegramChatId = settings.telegramChatId ?? ""
    telegramEnabled = settings.telegramEnabled
    pushoverUserKey = settings.pushoverUserKey ?? ""
    pushoverApiToken = settings.pushoverApiToken ?? ""
    pushoverEnabled = settings.pushoverEnabled
    startAtLogin = loginItem.isEnabled
    sleepPreventionInstalled = pmset.isInstalled()
    selectedAlarmSound = settings.alarmSound
  }

  private func saveSettings() {
    settings.contactName = contactName.isEmpty ? nil : contactName
    settings.contactPhone = contactPhone.isEmpty ? nil : contactPhone
    settings.telegramBotToken = telegramBotToken.isEmpty ? nil : telegramBotToken
    settings.telegramChatId = telegramChatId.isEmpty ? nil : telegramChatId
    settings.telegramEnabled = telegramEnabled
    settings.pushoverUserKey = pushoverUserKey.isEmpty ? nil : pushoverUserKey
    settings.pushoverApiToken = pushoverApiToken.isEmpty ? nil : pushoverApiToken
    settings.pushoverEnabled = pushoverEnabled
    settings.alarmSound = selectedAlarmSound

    ActivityLog.shared.logAsync(.system, "Settings saved")
  }

  private func resetSettings() {
    settings.resetAll()
    loadSettings()
    ActivityLog.shared.logAsync(.system, "All settings reset")
  }

  private func toggleSleepPrevention() {
    if sleepPreventionInstalled {
      _ = pmset.uninstall()
    } else {
      _ = pmset.install()
    }
    sleepPreventionInstalled = pmset.isInstalled()
  }

  private func toggleLoginItem(_ enable: Bool) {
    if enable {
      _ = loginItem.enable()
    } else {
      _ = loginItem.disable()
    }
  }

  private func retrieveFromContacts() {
    let ownerName = NSFullUserName()
    if !ownerName.isEmpty {
      contactName = ownerName
    }

    settings.requestContactsAccess { granted in
      if granted {
        DispatchQueue.main.async {
          if let phone = getMyCardPhone() {
            contactPhone = phone
          }
        }
      }
    }
  }

  private func getMyCardPhone() -> String? {
    let store = CNContactStore()
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
      return nil
    }
    let keys: [CNKeyDescriptor] = [CNContactPhoneNumbersKey as CNKeyDescriptor]
    guard let me = try? store.unifiedMeContactWithKeys(toFetch: keys) else {
      return nil
    }
    let mobile = me.phoneNumbers.first { $0.label == CNLabelPhoneNumberMobile }
    return mobile?.value.stringValue ?? me.phoneNumbers.first?.value.stringValue
  }
}
