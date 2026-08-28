import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, menu bar only

        guard !anotherCopyIsRunning() else {
            // A second paw in the menu bar with no way to tell them apart is
            // just confusing, so the newcomer bows out.
            NSApp.terminate(nil)
            return
        }

        guard SpriteLibrary.resourcesAvailable() else {
            // Without this, the first missing-bundle failure happens deep
            // inside SpriteLibrary's lazy init, triggered by a background
            // peek timer minutes later — a silent crash with no dialog.
            // Fail loud and immediately instead.
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "DeskPet can't find its sprite images"
            alert.informativeText = "The DeskPet_DeskPet.bundle is missing from this app copy. Try reinstalling DeskPet."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "DeskPet")
            image?.isTemplate = true
            button.image = image
        }
        let menu = buildMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        PeekScheduler.shared.start()

    }

    /// True when a different process is already running this same app —
    /// which happens after an upgrade if an older copy is still open from
    /// another folder.
    private func anotherCopyIsRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != mine }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = Settings.shared.enabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        let frequencyMenu = NSMenu()
        for freq in Frequency.allCases {
            let freqItem = NSMenuItem(title: freq.displayName, action: #selector(selectFrequency(_:)), keyEquivalent: "")
            freqItem.target = self
            freqItem.representedObject = freq
            freqItem.state = Settings.shared.frequency == freq ? .on : .off
            frequencyMenu.addItem(freqItem)
        }
        let frequencyItem = NSMenuItem(title: "Frequency", action: nil, keyEquivalent: "")
        frequencyItem.submenu = frequencyMenu
        menu.addItem(frequencyItem)

        let animalsItem = NSMenuItem(title: "Animals", action: nil, keyEquivalent: "")
        animalsItem.submenu = buildSpeciesMenu()
        menu.addItem(animalsItem)

        menu.addItem(.separator())

        let peekNowItem = NSMenuItem(title: "Peek Now", action: #selector(peekNow), keyEquivalent: "")
        peekNowItem.target = self
        menu.addItem(peekNowItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "Open at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: ""
        )
        loginItem.target = self
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem
        refreshLaunchAtLogin()

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func buildSpeciesMenu() -> NSMenu {
        let menu = NSMenu()

        let selectAll = NSMenuItem(title: "Select All", action: #selector(selectAllSpecies), keyEquivalent: "")
        selectAll.target = self
        menu.addItem(selectAll)

        let selectNone = NSMenuItem(title: "Select None", action: #selector(selectNoSpecies), keyEquivalent: "")
        selectNone.target = self
        menu.addItem(selectNone)

        menu.addItem(.separator())

        for species in Species.all {
            let item = NSMenuItem(title: species.displayName, action: #selector(toggleSpecies(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = species.id
            item.state = Settings.shared.isSpeciesEnabled(species.id) ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        Settings.shared.enabled.toggle()
        sender.state = Settings.shared.enabled ? .on : .off
    }

    @objc private func selectFrequency(_ sender: NSMenuItem) {
        guard let freq = sender.representedObject as? Frequency else { return }
        Settings.shared.frequency = freq
        sender.menu?.items.forEach { $0.state = ($0.representedObject as? Frequency) == freq ? .on : .off }
        PeekScheduler.shared.frequencyDidChange()
    }

    @objc private func toggleSpecies(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let newValue = sender.state != .on
        Settings.shared.setSpecies(id, enabled: newValue)
        sender.state = newValue ? .on : .off
    }

    @objc private func selectAllSpecies(_ sender: NSMenuItem) {
        Settings.shared.setAllSpecies(enabled: true)
        sender.menu?.items.forEach { $0.state = ($0.representedObject is String) ? .on : $0.state }
    }

    @objc private func selectNoSpecies(_ sender: NSMenuItem) {
        Settings.shared.setAllSpecies(enabled: false)
        sender.menu?.items.forEach { $0.state = ($0.representedObject is String) ? .off : $0.state }
    }

    // MARK: - Launch at login

    /// Re-read rather than cached: the user can also flip this in System
    /// Settings, and enabling it can land in "pending approval" there.
    private func refreshLaunchAtLogin() {
        launchAtLoginItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    /// Keeps the menu honest if the setting changed elsewhere.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshLaunchAtLogin()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("DeskPet: could not change the login item — \(error.localizedDescription)")
        }
        refreshLaunchAtLogin()
    }

    @objc private func peekNow() {
        PeekScheduler.shared.peekNow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
