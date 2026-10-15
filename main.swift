import AppKit
import Network

enum State {
    case online      // internet reachable
    case noInternet  // network link up, but probes fail (dead AP uplink, captive portal, DNS outage)
    case offline     // no network route at all

    var color: NSColor {
        switch self {
        case .online: return .systemGreen
        case .noInternet: return .systemOrange
        case .offline: return .systemRed
        }
    }
    var title: String {
        switch self {
        case .online: return "Online"
        case .noInternet: return "Connected, no internet"
        case .offline: return "Offline"
        }
    }
}

/// Probes real internet reachability. Succeeds if any endpoint answers with the expected status
/// (redirects are not followed, so captive portals count as failure).
final class Prober: NSObject, URLSessionTaskDelegate {
    private let endpoints: [(url: URL, status: Int)] = [
        (URL(string: "https://www.gstatic.com/generate_204")!, 204),
        (URL(string: "https://www.apple.com/library/test/success.html")!, 200),
    ]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func probe(_ completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var ok = false
        for endpoint in endpoints {
            group.enter()
            session.dataTask(with: endpoint.url) { _, response, _ in
                if (response as? HTTPURLResponse)?.statusCode == endpoint.status {
                    lock.lock(); ok = true; lock.unlock()
                }
                group.leave()
            }.resume()
        }
        group.notify(queue: .main) { completion(ok) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = NWPathMonitor()
    private let prober = Prober()
    private let statusLine = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")

    private var hasRoute = false
    private var consecutiveFailures = 0
    private var state: State = .offline
    private var probing = false
    private var timer: Timer?

    private let failuresBeforeDown = 2   // avoid flapping on a single dropped probe
    private let interval: TimeInterval = 10

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        render()

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.pathChanged(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "net"))

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.check() }

        // Re-check right after wake from sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.check()
        }
    }

    private func pathChanged(_ route: Bool) {
        hasRoute = route
        if route {
            check()
        } else {
            consecutiveFailures = 0
            state = .offline
            render()
        }
    }

    private func check() {
        guard hasRoute, !probing else { return }
        probing = true
        prober.probe { [weak self] ok in
            guard let self else { return }
            self.probing = false
            guard self.hasRoute else { return }
            if ok {
                self.consecutiveFailures = 0
                self.state = .online
            } else {
                self.consecutiveFailures += 1
                if self.consecutiveFailures >= self.failuresBeforeDown || self.state != .online {
                    self.state = .noInternet
                }
            }
            self.render()
        }
    }

    private func render() {
        item.button?.image = dot(state.color)
        statusLine.title = state.title
    }

    private func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 5, dy: 5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
