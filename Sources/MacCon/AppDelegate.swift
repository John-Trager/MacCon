import AppKit
import os
import ServiceManagement

/// Owns the menu bar item and keeps it in sync with connectivity.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = ConnectivityMonitor()
    private let menu = NSMenu()
    private let header = NSMenuItem()

    private var details: NetworkDetails?
    private var isMenuOpen = false

    private let detailsRefreshInterval = Duration.seconds(30)

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        statusItem.autosaveName = "MacCon"  // remembers where the user dragged it
        statusItem.menu = menu
        updateIcon()  // also sets the menu header
        rebuildMenu()

        monitor.onChange = { [weak self] _ in
            self?.updateIcon()
            Task { await self?.refreshDetails() }
        }
        monitor.start()
        refreshDetailsPeriodically()
    }

    // MARK: - Status icon

    private func updateIcon() {
        statusItem.button?.image = monitor.state.dotImage
        statusItem.button?.setAccessibilityLabel(monitor.state.title)
        updateHeader()
    }

    // MARK: - Menu

    /// Details are refreshed in the background, never while the menu is open,
    /// so the values and the menu's height stay still while you read it.
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        rebuildMenu()  // pick up any refresh that finished while it was open
    }

    private func refreshDetailsPeriodically() {
        Task { [weak self, detailsRefreshInterval] in
            while !Task.isCancelled {
                await self?.refreshDetails()
                try? await Task.sleep(for: detailsRefreshInterval)
            }
        }
    }

    private func refreshDetails() async {
        details = await NetworkDetails.gather()
        if !isMenuOpen { rebuildMenu() }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(header)

        if let details {
            for section in details.sections {
                menu.addItem(.separator())
                menu.addItem(.sectionHeader(title: section.title))
                section.rows.forEach { menu.addItem(makeRow($0)) }
            }
        }

        menu.addItem(.separator())
        menu.addItem(makeLaunchAtLoginItem())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// The state name next to a matching colored dot. It has no action, so macOS would dim it;
    /// an explicit color keeps it at full strength, matching the rows below.
    private func updateHeader() {
        header.attributedTitle = NSAttributedString(
            string: monitor.state.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        header.image = monitor.state.dotImage
    }

    /// A value row; clicking it copies the text.
    private func makeRow(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: #selector(copyToPasteboard(_:)), keyEquivalent: "")
        item.target = self
        item.toolTip = "Click to copy"
        return item
    }

    @objc private func copyToPasteboard(_ item: NSMenuItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.title, forType: .string)
    }

    // MARK: - Launch at login

    private func makeLaunchAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.target = self
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        return item
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            Logger().error("Launch at login failed: \(error.localizedDescription)")
        }
        rebuildMenu()
    }
}
