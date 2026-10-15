import Foundation

/// A snapshot of the router and local network details shown in the menu.
struct NetworkDetails: Sendable {
    /// A titled group of rows in the menu.
    struct Section {
        let title: String
        let rows: [String]
    }

    private(set) var gateways: [String]
    private(set) var gatewayPingMilliseconds: Double?
    private(set) var dnsServers: [String]
    private(set) var internetPingMilliseconds: Double?
    private(set) var localAddresses: [String]  // IPv4 first, then IPv6

    /// Host pinged to measure internet latency.
    private static let internetPingHost = "1.1.1.1"

    /// Collects a fresh snapshot without blocking the caller's thread.
    static func gather() async -> NetworkDetails {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: collect())
            }
        }
    }

    /// Menu content, in display order. Empty groups are omitted.
    var sections: [Section] {
        [
            Section(title: "Router", rows: gateways + [Self.pingText(gatewayPingMilliseconds)]),
            Section(title: "DNS", rows: dnsServers),
            Section(title: "Internet", rows: [Self.pingText(internetPingMilliseconds)]),
            Section(title: "This Mac", rows: localAddresses),
        ].filter { !$0.rows.isEmpty }
    }

    private static func pingText(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "Ping timed out" }
        return "Ping \(milliseconds.formatted(.number.precision(.fractionLength(0...1)))) ms"
    }

    private static func collect() -> NetworkDetails {
        let gateway4 = SystemQueries.defaultGateway(.v4)
        let gateway6 = SystemQueries.defaultGateway(.v6)
        let interface4 = SystemQueries.defaultInterface(.v4)
        let interface6 = SystemQueries.defaultInterface(.v6) ?? interface4
        let gateways = [gateway4, gateway6].compactMap { $0 }

        let ipv4 = interface4.map { SystemQueries.localAddresses(on: $0, .v4) } ?? []
        let ipv6 = interface6.map { SystemQueries.localAddresses(on: $0, .v6) } ?? []

        return NetworkDetails(
            gateways: gateways.map(withoutZone),
            gatewayPingMilliseconds: gateways.first.flatMap(SystemQueries.ping),
            dnsServers: SystemQueries.dnsServers().map(withoutZone),
            internetPingMilliseconds: SystemQueries.ping(internetPingHost),
            localAddresses: ipv4 + ipv6
        )
    }

    /// Drops the interface suffix of scoped IPv6 addresses ("fe80::1%en0" becomes "fe80::1").
    private static func withoutZone(_ address: String) -> String {
        String(address.prefix { $0 != "%" })
    }
}
