import AppKit
import Network

/// Combines the OS route status with active internet probes into a `ConnectivityState`.
@MainActor
final class ConnectivityMonitor {
    /// Called whenever `state` changes.
    var onChange: ((ConnectivityState) -> Void)?

    private(set) var state = ConnectivityState.offline {
        didSet { if state != oldValue { onChange?(state) } }
    }

    private let pathMonitor = NWPathMonitor()
    private let probe = InternetProbe()

    private var hasRoute = false
    private var isProbing = false
    private var consecutiveFailures = 0

    /// Probe failures in a row needed to drop from online, so one lost request doesn't flap the dot.
    private let failuresBeforeNoInternet = 2
    private let probeInterval = Duration.seconds(10)

    func start() {
        watchRouteChanges()
        probePeriodically()
        probeAfterWake()
    }

    // MARK: - Triggers

    private func watchRouteChanges() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let hasRoute = path.status == .satisfied
            Task { @MainActor in self?.routeChanged(hasRoute) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "MacCon.pathMonitor"))
    }

    private func probePeriodically() {
        Task { [weak self, probeInterval] in
            while !Task.isCancelled {
                await self?.checkInternet()
                try? await Task.sleep(for: probeInterval)
            }
        }
    }

    private func probeAfterWake() {
        Task { [weak self] in
            let wakes = NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification)
            for await _ in wakes {
                await self?.checkInternet()
            }
        }
    }

    // MARK: - State updates

    private func routeChanged(_ hasRoute: Bool) {
        self.hasRoute = hasRoute
        if hasRoute {
            Task { await checkInternet() }
        } else {
            consecutiveFailures = 0
            state = .offline
        }
    }

    private func checkInternet() async {
        guard hasRoute, !isProbing else { return }
        isProbing = true
        let reachable = await probe.isInternetReachable()
        isProbing = false

        guard hasRoute else { return }  // the route vanished while probing
        if reachable {
            consecutiveFailures = 0
            state = .online
        } else {
            consecutiveFailures += 1
            if state != .online || consecutiveFailures >= failuresBeforeNoInternet {
                state = .noInternet
            }
        }
    }
}
