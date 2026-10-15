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


/// Network details for the menu, gathered on demand via system tools.
enum NetInfo {
    static func run(_ path: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Value after "key:" in `route -n get` output.
    private static func routeField(_ key: String, inet6: Bool) -> String? {
        let args = inet6 ? ["-n", "get", "-inet6", "default"] : ["-n", "get", "default"]
        for line in run("/sbin/route", args).split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == key { return parts[1] }
        }
        return nil
    }

    static func gateway(inet6: Bool) -> String? { routeField("gateway", inet6: inet6) }
    static func interface(inet6: Bool) -> String? { routeField("interface", inet6: inet6) }

    /// Unique nameservers across all resolvers in `scutil --dns` (VPN/MagicDNS resolvers come first).
    static func dnsServers() -> [String] {
        var servers: [String] = []
        for line in run("/usr/sbin/scutil", ["--dns"]).split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("nameserver["), let v = t.split(separator: ":", maxSplits: 1).last {
                let ip = v.trimmingCharacters(in: .whitespaces)
                if !servers.contains(ip) { servers.append(ip) }
            }
        }
        return servers
    }

    /// Local addresses of an interface. IPv6 prefers non-link-local addresses.
    static func addresses(interface name: String, family: Int32) -> [String] {
        var result: [String] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard String(cString: ifa.ifa_name) == name, let sa = ifa.ifa_addr,
                  Int32(sa.pointee.sa_family) == family else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        if family == AF_INET6 {
            let global = result.filter { !$0.hasPrefix("fe80") }
            return global.isEmpty ? result : global
        }
        return result
    }

    /// Round-trip time in ms from a single ICMP ping, or nil on timeout.
    static func ping(_ host: String) -> String? {
        let bin = host.contains(":") ? "/sbin/ping6" : "/sbin/ping"
        let out = run(bin, ["-c", "1", "-t", "2", host])
        guard let r = out.range(of: "time=") else { return nil }
        let value = out[r.upperBound...].prefix { $0 != " " }
        return "\(value) ms"
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = NWPathMonitor()
    private let prober = Prober()
    private let statusLine = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
    private let infoItems = ["Gateway", "Gateway ping", "DNS", "Internet ping", "IPv4", "IPv6"]
        .map { NSMenuItem(title: "\($0): …", action: nil, keyEquivalent: "") }

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
        infoItems.forEach(menu.addItem)
        menu.addItem(.separator())
        menu.delegate = self
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

    func menuWillOpen(_ menu: NSMenu) {
        DispatchQueue.global().async { [weak self] in
            let gw4 = NetInfo.gateway(inet6: false)
            let gw6 = NetInfo.gateway(inet6: true)
            let if4 = NetInfo.interface(inet6: false)
            let if6 = NetInfo.interface(inet6: true) ?? if4
            let dns = NetInfo.dnsServers()
            let ip4 = if4.map { NetInfo.addresses(interface: $0, family: AF_INET) } ?? []
            let ip6 = if6.map { NetInfo.addresses(interface: $0, family: AF_INET6) } ?? []
            let gwPing = (gw4 ?? gw6).flatMap(NetInfo.ping)
            let netPing = NetInfo.ping("1.1.1.1")

            func join(_ v: [String]) -> String { v.isEmpty ? "none" : v.joined(separator: ", ") }
            let gateways = [gw4, gw6].compactMap { $0 }
            let lines = [
                "Gateway: \(join(gateways))",
                "Gateway ping: \(gwPing ?? "timeout")",
                "DNS: \(join(dns))",
                "Internet ping: \(netPing ?? "timeout")",
                "IPv4: \(join(ip4))",
                "IPv6: \(join(ip6))",
            ]
            DispatchQueue.main.async {
                guard let self else { return }
                for (item, line) in zip(self.infoItems, lines) { item.title = line }
            }
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
