import Testing
@testable import MacCon

@Suite struct ConnectivityTrackerTests {
    private func onlineTracker() -> ConnectivityTracker {
        var tracker = ConnectivityTracker()
        tracker.routeChanged(true)
        tracker.probeFinished(reachable: true)
        return tracker
    }

    @Test func startsOffline() {
        #expect(ConnectivityTracker().state == .offline)
    }

    @Test func goesOnlineAfterSuccessfulProbe() {
        #expect(onlineTracker().state == .online)
    }

    @Test func firstFailureWhileRouteUpDoesNotDropOnline() {
        var tracker = onlineTracker()
        tracker.probeFinished(reachable: false)
        #expect(tracker.state == .online)
    }

    @Test func twoFailuresInARowMeanNoInternet() {
        var tracker = onlineTracker()
        tracker.probeFinished(reachable: false)
        tracker.probeFinished(reachable: false)
        #expect(tracker.state == .noInternet)
    }

    @Test func successBetweenFailuresResetsTheCount() {
        var tracker = onlineTracker()
        tracker.probeFinished(reachable: false)
        tracker.probeFinished(reachable: true)
        tracker.probeFinished(reachable: false)
        #expect(tracker.state == .online)
    }

    @Test func firstFailureRightAfterRouteReturnsMeansNoInternet() {
        var tracker = ConnectivityTracker()
        tracker.routeChanged(true)
        tracker.probeFinished(reachable: false)
        #expect(tracker.state == .noInternet)
    }

    @Test func losingTheRouteMeansOfflineImmediately() {
        var tracker = onlineTracker()
        tracker.routeChanged(false)
        #expect(tracker.state == .offline)
    }

    @Test func probeResultsAreIgnoredWithoutARoute() {
        var tracker = ConnectivityTracker()
        tracker.probeFinished(reachable: true)
        #expect(tracker.state == .offline)
    }

    @Test func recoversOnFirstSuccess() {
        var tracker = onlineTracker()
        tracker.probeFinished(reachable: false)
        tracker.probeFinished(reachable: false)
        tracker.probeFinished(reachable: true)
        #expect(tracker.state == .online)
    }
}
