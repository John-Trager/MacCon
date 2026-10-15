import AppKit

/// What the menu bar dot reports.
enum ConnectivityState: Equatable {
    /// Internet is reachable.
    case online
    /// A network link exists but the internet is not reachable
    /// (dead router uplink, captive portal, DNS outage).
    case noInternet
    /// No network route at all.
    case offline

    var title: String {
        switch self {
        case .online: "Online"
        case .noInternet: "Connected, no internet"
        case .offline: "Offline"
        }
    }

    var color: NSColor {
        switch self {
        case .online: .systemGreen
        case .noInternet: .systemOrange
        case .offline: .systemRed
        }
    }

    /// A small filled circle in the state's color, sized for the menu bar.
    var dotImage: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            self.color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 5, dy: 5)).fill()
            return true
        }
        image.isTemplate = false  // keep the color instead of tinting to match the menu bar
        return image
    }
}
