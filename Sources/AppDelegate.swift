import AppKit

/// Owns the menu bar item and keeps it in sync with connectivity.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = ConnectivityMonitor()
    private let menu = NSMenu()
    private let header = NSMenuItem()

    private var details: NetworkDetails?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()  // also sets the menu header
        rebuildMenu()

        monitor.onChange = { [weak self] _ in
            self?.updateIcon()
        }
        monitor.start()
    }

    // MARK: - Status icon

    private func updateIcon() {
        statusItem.button?.image = monitor.state.dotImage
        statusItem.button?.setAccessibilityLabel(monitor.state.title)
        updateHeader()
    }

    // MARK: - Menu

    /// Shows the last known details immediately, then refreshes them while the menu is open.
    /// Fetching only on open keeps the app idle otherwise.
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        Task {
            details = await NetworkDetails.gather()
            rebuildMenu()
        }
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
}
