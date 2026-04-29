import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem!
  private var menu: NSMenu!
  private var statusMenuItem: NSMenuItem!
  private var toggleMenuItem: NSMenuItem!
  private var testMenuItem: NSMenuItem!
  private var activityLogMenuItem: NSMenuItem!
  private var bluetoothAutoArmMenuItem: NSMenuItem!
  private var eyeOverlayView: NSImageView?

  private let theftProtection = TheftProtectionService()
  private let authService = BiometricAuthService()
  private var allowQuit = false

  func allowQuitForUpdate() {
    allowQuit = true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupMainMenu()
    setupMenuBar()
    theftProtection.delegate = self
    theftProtection.start()

    NotificationCenter.default.addObserver(
      forName: .bluetoothSettingsChanged, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.updateStatus()
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
    if (theftProtection.state == .enabled || theftProtection.state == .enabledBluetooth)
       && !SettingsService.shared.behaviorShutdownBlocking {
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
    appMenu.addItem(NSMenuItem(title: "About \(Config.App.name)", action: #selector(showAbout), keyEquivalent: ""))
    appMenu.addItem(.separator())
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

    // Help menu
    let helpMenuItem = NSMenuItem()
    let helpMenu = NSMenu(title: "Help")
    helpMenu.addItem(NSMenuItem(title: "\(Config.App.name) on GitHub", action: #selector(openGitHub), keyEquivalent: ""))
    helpMenu.addItem(NSMenuItem(title: "Report an Issue", action: #selector(openIssues), keyEquivalent: ""))
    helpMenuItem.submenu = helpMenu
    mainMenu.addItem(helpMenuItem)

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

    bluetoothAutoArmMenuItem = NSMenuItem(title: "Bluetooth Auto-Arm: Off", action: #selector(toggleBluetoothAutoArm), keyEquivalent: "b")
    bluetoothAutoArmMenuItem.target = self
    bluetoothAutoArmMenuItem.image = menuSymbol("antenna.radiowaves.left.and.right", color: .secondaryLabelColor)
    menu.addItem(bluetoothAutoArmMenuItem)

    menu.addItem(.separator())

    let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    settingsItem.image = menuSymbol("gearshape", color: .secondaryLabelColor)
    menu.addItem(settingsItem)

    let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
    moreItem.image = menuSymbol("ellipsis.circle", color: .secondaryLabelColor)
    let moreMenu = NSMenu()
    moreMenu.addItem(NSMenuItem(title: "About \(Config.App.name)", action: #selector(showAbout), keyEquivalent: ""))
    moreMenu.addItem(NSMenuItem(title: "\(Config.App.name) on GitHub", action: #selector(openGitHub), keyEquivalent: ""))
    moreMenu.addItem(NSMenuItem(title: "Report an Issue", action: #selector(openIssues), keyEquivalent: ""))
    moreItem.submenu = moreMenu
    menu.addItem(moreItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
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

  private func showEyeOverlay(style: MenuBarIconStyle) {
    guard let button = statusItem.button else { return }
    removeEyeOverlay()
    let imageView = NSImageView(image: MenuBarIconRenderer.eyeImage(style))
    imageView.frame = button.bounds
    imageView.imageScaling = .scaleNone
    button.addSubview(imageView)
    eyeOverlayView = imageView
  }

  private func removeEyeOverlay() {
    eyeOverlayView?.removeFromSuperview()
    eyeOverlayView = nil
  }

  private func updateStatus() {
    switch theftProtection.state {
    case .disabled:
      let btWatching = SettingsService.shared.bluetoothAutoArmEnabled && SettingsService.shared.hasTrustedBLEDevices
      statusMenuItem.title = btWatching ? "Status: Watching Bluetooth" : "Status: Disabled"
      statusMenuItem.image = menuSymbol("circle.fill", color: btWatching ? .systemYellow : .systemRed)
      toggleMenuItem.title = "Enable Protection"
      toggleMenuItem.image = menuSymbol("checkmark.shield", color: .systemGreen)
      statusItem.button?.image = MenuBarIconRenderer.laptopIcon(btWatching ? .eyeHalfClosedBluetooth : .eyeClosed)
      if btWatching { showEyeOverlay(style: .eyeHalfClosedBluetooth) } else { removeEyeOverlay() }

    case .enabled:
      statusMenuItem.title = "Status: Monitoring"
      statusMenuItem.image = menuSymbol("checkmark.circle.fill", color: .systemGreen)
      toggleMenuItem.title = "Disable Protection"
      toggleMenuItem.image = menuSymbol("xmark.shield", color: .systemRed)
      statusItem.button?.image = MenuBarIconRenderer.laptopIcon(.eyeOpen)
      showEyeOverlay(style: .eyeOpen)

    case .enabledBluetooth:
      statusMenuItem.title = "Status: Auto-Armed (Bluetooth)"
      statusMenuItem.image = menuSymbol("antenna.radiowaves.left.and.right", color: .systemYellow)
      toggleMenuItem.title = "Disable Protection"
      toggleMenuItem.image = menuSymbol("xmark.shield", color: .systemRed)
      statusItem.button?.image = MenuBarIconRenderer.laptopIcon(.eyeOpenBluetooth)
      showEyeOverlay(style: .eyeOpenBluetooth)

    case .theftMode:
      let cause = theftProtection.currentTrigger?.description
      statusMenuItem.title = cause.map { "THEFT MODE — \($0)" } ?? "THEFT MODE ACTIVE"
      statusMenuItem.image = menuSymbol("exclamationmark.triangle.fill", color: .systemRed)
      toggleMenuItem.title = "Deactivate Theft Mode"
      toggleMenuItem.image = menuSymbol("lock.open", color: .systemOrange)
      statusItem.button?.image = MenuBarIconRenderer.laptopIcon(.eyeAlert)
      showEyeOverlay(style: .eyeAlert)
    }

    updateBluetoothMenuItem()
  }

  private func updateBluetoothMenuItem() {
    let settings = SettingsService.shared
    let hasTrusted = settings.hasTrustedBLEDevices
    let enabled = hasTrusted && settings.bluetoothAutoArmEnabled

    bluetoothAutoArmMenuItem.title = "Bluetooth Auto-Arm: \(enabled ? "On" : "Off")"
    bluetoothAutoArmMenuItem.isEnabled = hasTrusted
    bluetoothAutoArmMenuItem.image = menuSymbol(
      "antenna.radiowaves.left.and.right",
      color: enabled ? .systemYellow : .secondaryLabelColor
    )
  }

  @objc private func toggleProtection() {
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

  @objc private func toggleBluetoothAutoArm() {
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
    updateStatus()
    ActivityLog.logAsync(.bluetooth, "Bluetooth auto-arm \(settings.bluetoothAutoArmEnabled ? "enabled" : "disabled")")
  }

  @objc private func quitApp() {
    authService.authenticate(reason: "Authenticate to quit \(Config.App.name)") { [weak self] success in
      MainActor.assumeIsolated {
        if success {
          self?.allowQuit = true
          NSApplication.shared.terminate(nil)
        }
      }
    }
  }

  @objc private func sendTestAlert() {
    theftProtection.sendTestAlert()
  }

  @objc private func openSettings() {
    authService.authenticate(reason: "Authenticate to open Settings") { [weak self] success in
      MainActor.assumeIsolated {
        if success { self?.showSettings() }
      }
    }
  }

  private func showSettings() {
    SettingsWindowController.shared.show()
  }

  @objc private func showActivityLog() {
    ActivityLogWindowController.shared.show()
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

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    return false
  }

  func applicationWillTerminate(_ notification: Notification) {
    ActivityLog.logAsync(.system, "LidGuard shutting down")
    theftProtection.shutdown()
  }
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
      // Turning off — require Touch ID
      authService.authenticate(reason: "Authenticate to disable Bluetooth auto-arm") { [weak self] success in
        MainActor.assumeIsolated {
          guard success else { return }
          settings.bluetoothAutoArmEnabled = false
          NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)
          if self?.theftProtection.state == .enabledBluetooth {
            self?.theftProtection.disableProtection()
          }
          self?.updateStatus()
          ActivityLog.logAsync(.bluetooth, "Bluetooth auto-arm disabled via shortcut")
        }
      }
    } else {
      // Turning on — no auth needed
      settings.bluetoothAutoArmEnabled = true
      NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)
      updateStatus()
      ActivityLog.logAsync(.bluetooth, "Bluetooth auto-arm enabled via shortcut")
    }
  }

  func theftProtectionStateDidChange(_ service: TheftProtectionService, state: ProtectionState) {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
      // Force close menu if open (critical for theft mode activation)
      if state == .theftMode {
        self?.menu.cancelTracking()
      }
      self?.updateStatus()
      self?.updateBluetoothMenuItem()

      // Show Dock icon when protection enabled (required to block shutdown)
      // Hide Dock icon when disabled (cleaner UX)
      let policy: NSApplication.ActivationPolicy = (state == .disabled) ? .accessory : .regular
      NSApp.setActivationPolicy(policy)
    }
    CFRunLoopWakeUp(CFRunLoopGetMain())
  }
}
