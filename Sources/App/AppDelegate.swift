import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let statusBar = StatusBarController()
  private let theftProtection = TheftProtectionService()
  private let authService = BiometricAuthService()
  private var allowQuit = false

  func allowQuitForUpdate() {
    allowQuit = true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupMainMenu()
    statusBar.delegate = self
    statusBar.setup()
    theftProtection.delegate = self
    theftProtection.start()
    theftProtection.resumeTheftModeIfNeeded()
    statusBar.update(state: theftProtection.state, trigger: theftProtection.currentTrigger)

    NotificationCenter.default.addObserver(
      forName: .bluetoothSettingsChanged, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.statusBar.update(state: self.theftProtection.state, trigger: self.theftProtection.currentTrigger)
      }
    }

    ActivityLog.logAsync(.system, "LidGuard v\(Config.App.version) started")
    UpdateService.shared.startPeriodicChecks()
    HelperInstallService.shared.startPeriodicHelperChecks()

    // Start with no Dock icon (protection disabled)
    NSApp.setActivationPolicy(.accessory)

    // First launch: unregister stale login item, show settings
    if !SettingsService.shared.isConfigured() {
      _ = LoginItemService.shared.disable()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        MainActor.assumeIsolated {
          self?.showSettings()
        }
      }
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if allowQuit {
      return .terminateNow
    }

    if theftProtection.state == .disabled {
      return .terminateNow
    }

    if (theftProtection.state == .enabled || theftProtection.state == .enabledBluetooth)
       && !SettingsService.shared.behaviorShutdownBlocking {
      return .terminateNow
    }

    ActivityLog.logAsync(.trigger, "Shutdown/quit BLOCKED")
    theftProtection.sendShutdownAlert(blocked: true)

    return .terminateCancel
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    return false
  }

  func applicationWillTerminate(_ notification: Notification) {
    ActivityLog.logAsync(.system, "LidGuard shutting down")
    theftProtection.shutdown()
  }

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(NSMenuItem(title: "About \(Config.App.name)", action: #selector(showAbout), keyEquivalent: ""))
    appMenu.addItem(.separator())
    appMenu.addItem(NSMenuItem(title: "Quit \(Config.App.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
    editMenu.addItem(.separator())
    editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    let helpMenuItem = NSMenuItem()
    let helpMenu = NSMenu(title: "Help")
    helpMenu.addItem(NSMenuItem(title: "\(Config.App.name) on GitHub", action: #selector(openGitHub), keyEquivalent: ""))
    helpMenu.addItem(NSMenuItem(title: "Report an Issue", action: #selector(openIssues), keyEquivalent: ""))
    helpMenuItem.submenu = helpMenu
    mainMenu.addItem(helpMenuItem)

    NSApp.mainMenu = mainMenu
  }

  // MARK: - Action handlers

  fileprivate func toggleProtection() {
    switch theftProtection.state {
    case .disabled:
      theftProtection.enableProtection()

    case .enabled, .enabledBluetooth:
      authService.authenticate(reason: "Authenticate to disable protection") { [weak self] success in
        MainActor.assumeIsolated {
          if success { self?.theftProtection.disableProtection() }
        }
      }

    case .theftMode:
      authService.authenticate(reason: "Authenticate to deactivate theft mode") { [weak self] success in
        MainActor.assumeIsolated {
          if success { self?.theftProtection.deactivateTheftMode() }
        }
      }
    }
  }

  fileprivate func toggleBluetoothAutoArm() {
    let settings = SettingsService.shared
    let turningOff = settings.bluetoothAutoArmEnabled

    if turningOff {
      authService.authenticate(reason: "Authenticate to disable Bluetooth auto-arm") { [weak self] success in
        MainActor.assumeIsolated {
          guard success else { return }
          self?.performBluetoothAutoArmToggle()
        }
      }
    } else {
      performBluetoothAutoArmToggle()
    }
  }

  private func performBluetoothAutoArmToggle() {
    let settings = SettingsService.shared
    settings.bluetoothAutoArmEnabled = !settings.bluetoothAutoArmEnabled
    NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)
    if !settings.bluetoothAutoArmEnabled && theftProtection.state == .enabledBluetooth {
      theftProtection.disableProtection()
    }
    statusBar.update(state: theftProtection.state, trigger: theftProtection.currentTrigger)
    ActivityLog.logAsync(.bluetooth, "Bluetooth auto-arm \(settings.bluetoothAutoArmEnabled ? "enabled" : "disabled")")
  }

  fileprivate func openSettings() {
    authService.authenticate(reason: "Authenticate to open Settings") { [weak self] success in
      MainActor.assumeIsolated {
        if success { self?.showSettings() }
      }
    }
  }

  private func showSettings() {
    SettingsWindowController.shared.show()
  }

  fileprivate func quit() {
    authService.authenticate(reason: "Authenticate to quit \(Config.App.name)") { [weak self] success in
      MainActor.assumeIsolated {
        if success {
          self?.allowQuit = true
          NSApplication.shared.terminate(nil)
        }
      }
    }
  }

  @objc private func showAbout() {
    let credits = NSAttributedString(
      string: "Laptop theft protection for macOS",
      attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
    )
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: Config.App.name,
      .applicationVersion: Config.App.version,
      .version: "",
      .credits: credits
    ])
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openGitHub() {
    NSWorkspace.shared.open(URL(string: "https://github.com/Erel3/lidguard")!)
  }

  @objc private func openIssues() {
    NSWorkspace.shared.open(URL(string: "https://github.com/Erel3/lidguard/issues")!)
  }
}

// MARK: - StatusBarControllerDelegate

extension AppDelegate: StatusBarControllerDelegate {
  func statusBarLeftClickPreOpen() {
    theftProtection.refreshLocation()
  }

  func statusBarRightClick() {
    switch theftProtection.state {
    case .disabled:
      theftProtection.enableProtection()

    case .enabled, .enabledBluetooth:
      authService.authenticate(reason: "Authenticate to disable protection") { [weak self] success in
        MainActor.assumeIsolated {
          if success { self?.theftProtection.disableProtection() }
        }
      }

    case .theftMode:
      authService.authenticate(reason: "Authenticate to deactivate theft mode") { [weak self] success in
        MainActor.assumeIsolated {
          if success { self?.theftProtection.deactivateTheftMode() }
        }
      }
    }
  }

  func statusBarToggleProtection() { toggleProtection() }
  func statusBarSendTestAlert() { theftProtection.sendTestAlert() }
  func statusBarShowActivityLog() { ActivityLogWindowController.shared.show() }
  func statusBarToggleBluetoothAutoArm() { toggleBluetoothAutoArm() }
  func statusBarOpenSettings() { openSettings() }
  func statusBarShowAbout() { showAbout() }
  func statusBarOpenGitHub() { openGitHub() }
  func statusBarOpenIssues() { openIssues() }
  func statusBarQuit() { quit() }
}

// MARK: - TheftProtectionDelegate

extension AppDelegate: TheftProtectionDelegate {
  func theftProtectionShortcutTriggered(_ service: TheftProtectionService) {
    switch service.state {
    case .disabled:
      service.enableProtection(lockScreen: SettingsService.shared.lockScreenOnShortcut)
    case .enabled, .enabledBluetooth:
      authService.authenticate(reason: "Authenticate to disable protection") { [weak self] success in
        MainActor.assumeIsolated {
          guard success else { return }
          self?.theftProtection.disableProtection()
        }
      }
    case .theftMode:
      break
    }
  }

  func theftProtectionBluetoothShortcutTriggered(_ service: TheftProtectionService) {
    let settings = SettingsService.shared
    guard settings.hasTrustedBLEDevices else { return }

    if settings.bluetoothAutoArmEnabled {
      authService.authenticate(reason: "Authenticate to disable Bluetooth auto-arm") { [weak self] success in
        MainActor.assumeIsolated {
          guard success else { return }
          settings.bluetoothAutoArmEnabled = false
          NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)
          if self?.theftProtection.state == .enabledBluetooth {
            self?.theftProtection.disableProtection()
          }
          if let self {
            self.statusBar.update(state: self.theftProtection.state, trigger: self.theftProtection.currentTrigger)
          }
          ActivityLog.logAsync(.bluetooth, "Bluetooth auto-arm disabled via shortcut")
        }
      }
    } else {
      settings.bluetoothAutoArmEnabled = true
      NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)
      statusBar.update(state: theftProtection.state, trigger: theftProtection.currentTrigger)
      ActivityLog.logAsync(.bluetooth, "Bluetooth auto-arm enabled via shortcut")
    }
  }

  func theftProtectionStateDidChange(_ service: TheftProtectionService, state: ProtectionState) {
    // Defer to the next main-runloop turn so this status-bar / activation-policy
    // mutation doesn't run inside an in-flight state transition or menu event.
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        if state == .theftMode {
          self.statusBar.cancelMenuTracking()
        }
        self.statusBar.update(state: state, trigger: self.theftProtection.currentTrigger)
        self.statusBar.updateBluetoothMenuItem()

        let policy: NSApplication.ActivationPolicy = (state == .disabled) ? .accessory : .regular
        NSApp.setActivationPolicy(policy)
      }
    }
  }
}
