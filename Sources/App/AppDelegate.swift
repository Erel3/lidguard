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
  private var allowQuit = false  // Set true after Touch ID authentication

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupMainMenu()
    setupMenuBar()
    theftProtection.delegate = self
    theftProtection.start()

    ActivityLog.logAsync(.system, "LidGuard v\(Config.App.version) started")

    // Start with no Dock icon (protection disabled)
    NSApp.setActivationPolicy(.accessory)

    // Show settings on first launch if not configured
    if !SettingsService.shared.isConfigured() {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.showSettings()
      }
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Allow quit if user authenticated with Touch ID
    if allowQuit {
      return .terminateNow
    }

    // Allow quit if protection disabled
    if theftProtection.state == .disabled {
      return .terminateNow
    }

    // In theft mode, always block termination
    // In enabled state, check shutdownBlocking setting
    if theftProtection.state == .enabled && !SettingsService.shared.behaviorShutdownBlocking {
      return .terminateNow
    }

    ActivityLog.logAsync(.trigger, "Shutdown/quit BLOCKED")
    theftProtection.sendShutdownAlert(blocked: true)

    // This will show system dialog: "LidGuard is preventing shutdown"
    // User must click Cancel or we get force-killed after timeout
    return .terminateCancel
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

    statusMenuItem = NSMenuItem(title: "Status: Monitoring", action: nil, keyEquivalent: "")
    menu.addItem(statusMenuItem)

    menu.addItem(.separator())

    toggleMenuItem = NSMenuItem(title: "Disable Protection", action: #selector(toggleProtection), keyEquivalent: "d")
    toggleMenuItem.target = self
    menu.addItem(toggleMenuItem)

    testMenuItem = NSMenuItem(title: "Send Test Alert", action: #selector(sendTestAlert), keyEquivalent: "")
    testMenuItem.target = self
    testMenuItem.image = menuSymbol("paperplane", color: .systemBlue)
    testMenuItem.isHidden = true
    menu.addItem(testMenuItem)

    activityLogMenuItem = NSMenuItem(title: "Activity Log", action: #selector(showActivityLog), keyEquivalent: "")
    activityLogMenuItem.target = self
    activityLogMenuItem.image = menuSymbol("list.bullet.rectangle", color: .secondaryLabelColor)
    activityLogMenuItem.isHidden = true
    menu.addItem(activityLogMenuItem)

    menu.addItem(.separator())

    let settingsItem = NSMenuItem(title: "Settings... (Touch ID)", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    settingsItem.image = menuSymbol("gearshape", color: .secondaryLabelColor)
    menu.addItem(settingsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Quit (Touch ID)", action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    quitItem.image = menuSymbol("power", color: .secondaryLabelColor)
    menu.addItem(quitItem)

    updateStatus()
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }

    // Pre-fetch location before menu blocks run loop
    theftProtection.refreshLocation()

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

  private func menuSymbol(_ name: String, color: NSColor) -> NSImage? {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
      .applying(.init(paletteColors: [color]))
    return image.withSymbolConfiguration(config)
  }

  private func updateStatus() {
    switch theftProtection.state {
    case .disabled:
      statusMenuItem.title = "Status: Disabled"
      statusMenuItem.image = menuSymbol("circle.fill", color: .systemRed)
      toggleMenuItem.title = "Enable Protection"
      toggleMenuItem.image = menuSymbol("checkmark.shield", color: .systemGreen)
      statusItem.button?.image = NSImage(
        systemSymbolName: "laptopcomputer.slash",
        accessibilityDescription: "Disabled"
      )

    case .enabled:
      statusMenuItem.title = "Status: Monitoring"
      statusMenuItem.image = menuSymbol("checkmark.circle.fill", color: .systemGreen)
      toggleMenuItem.title = "Disable Protection"
      toggleMenuItem.image = menuSymbol("xmark.shield", color: .systemRed)
      statusItem.button?.image = NSImage(
        systemSymbolName: "lock.laptopcomputer",
        accessibilityDescription: "Monitoring"
      )

    case .theftMode:
      statusMenuItem.title = "THEFT MODE ACTIVE"
      statusMenuItem.image = menuSymbol("exclamationmark.triangle.fill", color: .systemRed)
      toggleMenuItem.title = "Deactivate Theft Mode"
      toggleMenuItem.image = menuSymbol("lock.open", color: .systemOrange)
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
    authService.authenticate(reason: "Authenticate to quit \(Config.App.name)") { [weak self] success in
      if success {
        self?.allowQuit = true
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
    ActivityLog.logAsync(.system, "LidGuard shutting down")
    theftProtection.shutdown()
  }
}

// MARK: - TheftProtectionDelegate
extension AppDelegate: TheftProtectionDelegate {
  func theftProtectionStateDidChange(_ service: TheftProtectionService, state: ProtectionState) {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
      // Force close menu if open (critical for theft mode activation)
      if state == .theftMode {
        self?.menu.cancelTracking()
      }
      self?.updateStatus()

      // Show Dock icon when protection enabled (required to block shutdown)
      // Hide Dock icon when disabled (cleaner UX)
      let policy: NSApplication.ActivationPolicy = (state == .disabled) ? .accessory : .regular
      NSApp.setActivationPolicy(policy)
    }
    CFRunLoopWakeUp(CFRunLoopGetMain())
  }
}
