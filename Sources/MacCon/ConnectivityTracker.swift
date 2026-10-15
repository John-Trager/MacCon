/// The pure decision logic behind the dot: route status and probe results in, state out.
struct ConnectivityTracker {
    private(set) var state = ConnectivityState.offline
    private(set) var hasRoute = false

    /// Probe failures in a row needed to drop from online, so one lost request doesn't flap the dot.
    let failuresBeforeNoInternet = 2

    private var consecutiveFailures = 0

    mutating func routeChanged(_ hasRoute: Bool) {
        self.hasRoute = hasRoute
        consecutiveFailures = 0
        if !hasRoute { state = .offline }
    }

    mutating func probeFinished(reachable: Bool) {
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
