import AppKit
import Network

/// Feeds route changes and internet probes into a `ConnectivityTracker`.
@MainActor
final class ConnectivityMonitor {
    /// Called whenever `state` changes.
    var onChange: ((ConnectivityState) -> Void)?

    var state: ConnectivityState { tracker.state }

    private var tracker = ConnectivityTracker()
    private let pathMonitor = NWPathMonitor()
    private let probe = InternetProbe()
    private var isProbing = false

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
            Task { @MainActor in await self?.routeChanged(hasRoute) }
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

    private func routeChanged(_ hasRoute: Bool) async {
        update { $0.routeChanged(hasRoute) }
        if hasRoute { await checkInternet() }
    }

    private func checkInternet() async {
        guard tracker.hasRoute, !isProbing else { return }
        isProbing = true
        let reachable = await probe.isInternetReachable()
        isProbing = false
        update { $0.probeFinished(reachable: reachable) }
    }

    private func update(_ change: (inout ConnectivityTracker) -> Void) {
        let previous = tracker.state
        change(&tracker)
        if tracker.state != previous { onChange?(tracker.state) }
    }
}
