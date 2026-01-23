import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem!
  private var menu: NSMenu!
  private var statusMenuItem: NSMenuItem!
  private var toggleMenuItem: NSMenuItem!
  private var testMenuItem: NSMenuItem!
  private var activityLogMenuItem: NSMenuItem!

  private let theftProtection = TheftProtectionService()
  private let authService = BiometricAuthService()
  private let pmsetService = PmsetService.shared

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupMainMenu()
    setupMenuBar()
    theftProtection.delegate = self
    theftProtection.start()
    SettingsService.shared.requestContactsAccessIfNeeded {}

    ActivityLog.shared.logAsync(.system, "LidGuard v\(Config.App.version) started")

    // Show settings on first launch if not configured
    if !SettingsService.shared.isConfigured() {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.showSettings()
      }
    }
  }

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    // App menu
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(NSMenuItem(title: "Quit \(Config.App.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    // Edit menu (enables Cmd+C, Cmd+V, Cmd+X, Cmd+A)
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

    NSApp.mainMenu = mainMenu
  }

  private func setupMenuBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem.button {
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    menu = NSMenu()
    menu.delegate = self

    statusMenuItem = NSMenuItem(title: "✅ Status: Monitoring", action: nil, keyEquivalent: "")
    menu.addItem(statusMenuItem)

    menu.addItem(.separator())

    toggleMenuItem = NSMenuItem(title: "🔴 Disable Protection", action: #selector(toggleProtection), keyEquivalent: "d")
    toggleMenuItem.target = self
    menu.addItem(toggleMenuItem)

    testMenuItem = NSMenuItem(title: "Send Test Alert", action: #selector(sendTestAlert), keyEquivalent: "")
    testMenuItem.target = self
    testMenuItem.isHidden = true
    menu.addItem(testMenuItem)

    activityLogMenuItem = NSMenuItem(title: "Activity Log", action: #selector(showActivityLog), keyEquivalent: "")
    activityLogMenuItem.target = self
    activityLogMenuItem.isHidden = true
    menu.addItem(activityLogMenuItem)

    menu.addItem(.separator())

    let settingsItem = NSMenuItem(title: "Settings... (Touch ID)", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    menu.addItem(settingsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Quit (Touch ID)", action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    updateStatus()
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }

    if event.type == .rightMouseUp {
      handleRightClick()
    } else {
      // Left click: show menu (Option key shows hidden items via menuWillOpen)
      if let button = statusItem.button {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
      }
    }
  }

  private func handleRightClick() {
    switch theftProtection.state {
    case .disabled:
      theftProtection.enableProtection()

    case .enabled:
      authService.authenticate(reason: "Authenticate to disable protection") { [weak self] success in
        if success {
          self?.theftProtection.disableProtection()
        }
      }

    case .theftMode:
      authService.authenticate(reason: "Authenticate to deactivate theft mode") { [weak self] success in
        if success {
          self?.theftProtection.deactivateTheftMode()
        }
      }
    }
  }

  // MARK: - NSMenuDelegate
  func menuWillOpen(_ menu: NSMenu) {
    let optionPressed = NSEvent.modifierFlags.contains(.option)
    testMenuItem.isHidden = !optionPressed
    activityLogMenuItem.isHidden = !optionPressed
  }

  private func updateStatus() {
    switch theftProtection.state {
    case .disabled:
      statusMenuItem.title = "🔴 Status: Disabled"
      toggleMenuItem.title = "🟢 Enable Protection"
      statusItem.button?.image = NSImage(
        systemSymbolName: "laptopcomputer.slash",
        accessibilityDescription: "Disabled"
      )

    case .enabled:
      statusMenuItem.title = "✅ Status: Monitoring"
      toggleMenuItem.title = "🔴 Disable Protection"
      statusItem.button?.image = NSImage(
        systemSymbolName: "lock.laptopcomputer",
        accessibilityDescription: "Monitoring"
      )

    case .theftMode:
      statusMenuItem.title = "🚨 THEFT MODE ACTIVE"
      toggleMenuItem.title = "🔓 Deactivate Theft Mode"
      statusItem.button?.image = NSImage(
        systemSymbolName: "exclamationmark.triangle.fill",
        accessibilityDescription: "Theft Mode"
      )
    }
  }

  @objc private func toggleProtection() {
    switch theftProtection.state {
    case .disabled:
      theftProtection.enableProtection()

    case .enabled:
      authService.authenticate(reason: "Authenticate to disable protection") { [weak self] success in
        if success {
          self?.theftProtection.disableProtection()
        }
      }

    case .theftMode:
      authService.authenticate(reason: "Authenticate to deactivate theft mode") { [weak self] success in
        if success {
          self?.theftProtection.deactivateTheftMode()
        }
      }
    }
  }

  @objc private func quitApp() {
    authService.authenticate(reason: "Authenticate to quit \(Config.App.name)") { success in
      if success {
        NSApplication.shared.terminate(nil)
      }
    }
  }

  @objc private func sendTestAlert() {
    theftProtection.sendTestAlert()
  }

  @objc private func openSettings() {
    authService.authenticate(reason: "Authenticate to open Settings") { [weak self] success in
      if success {
        self?.showSettings()
      }
    }
  }

  private func showSettings() {
    SettingsWindowController.shared.show()
  }

  @objc private func showActivityLog() {
    ActivityLogWindowController.shared.show()
  }

  func applicationWillTerminate(_ notification: Notification) {
    ActivityLog.shared.logAsync(.system, "LidGuard shutting down")
    theftProtection.shutdown()
  }
}

// MARK: - TheftProtectionDelegate
extension AppDelegate: TheftProtectionDelegate {
  func theftProtectionStateDidChange(_ service: TheftProtectionService, state: ProtectionState) {
    DispatchQueue.main.async { [weak self] in
      self?.updateStatus()
    }
  }
}
