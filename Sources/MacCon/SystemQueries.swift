import Foundation

/// Thin wrappers over macOS command-line tools and C APIs. All calls are blocking;
/// run them off the main thread.
enum SystemQueries {
    enum IPFamily {
        case v4, v6

        fileprivate var posixFamily: Int32 { self == .v4 ? AF_INET : AF_INET6 }
    }

    // MARK: - Routing

    static func defaultGateway(_ family: IPFamily) -> String? {
        defaultRouteField("gateway", family)
    }

    static func defaultInterface(_ family: IPFamily) -> String? {
        defaultRouteField("interface", family)
    }

    /// Reads one `key: value` line from `route -n get default`.
    private static func defaultRouteField(_ key: String, _ family: IPFamily) -> String? {
        let arguments = family == .v4 ? ["-n", "get", "default"] : ["-n", "get", "-inet6", "default"]
        return keyValueLines(of: run("/sbin/route", arguments))[key]
    }

    // MARK: - DNS

    /// Unique nameservers across all resolvers in `scutil --dns`.
    /// VPN resolvers (e.g. Tailscale MagicDNS) are listed alongside the router's.
    static func dnsServers() -> [String] {
        var servers: [String] = []
        for line in run("/usr/sbin/scutil", ["--dns"]).split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("nameserver["),
                  let address = trimmed.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces),
                  !servers.contains(address) else { continue }
            servers.append(address)
        }
        return servers
    }

    // MARK: - Addresses

    /// Local addresses on `interface`. For IPv6, link-local (fe80::) addresses are
    /// returned only when there is nothing else.
    static func localAddresses(on interface: String, _ family: IPFamily) -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        var addresses: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let info = entry.pointee
            guard String(cString: info.ifa_name) == interface,
                  let socketAddress = info.ifa_addr,
                  Int32(socketAddress.pointee.sa_family) == family.posixFamily,
                  let text = numericHost(of: socketAddress) else { continue }
            addresses.append(text)
        }

        if family == .v6 {
            let global = addresses.filter { !$0.hasPrefix("fe80") }
            return global.isEmpty ? addresses : global
        }
        return addresses
    }

    private static func numericHost(of address: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address, socklen_t(address.pointee.sa_len),
            &buffer, socklen_t(buffer.count),
            nil, 0, NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Ping

    /// Round-trip time of one ICMP echo in milliseconds, or nil on timeout.
    static func ping(_ host: String) -> Double? {
        let tool = host.contains(":") ? "/sbin/ping6" : "/sbin/ping"
        let output = run(tool, ["-c", "1", "-t", "2", host])
        guard let marker = output.range(of: "time=") else { return nil }
        return Double(output[marker.upperBound...].prefix { !$0.isWhitespace })
    }

    // MARK: - Helpers

    private static func keyValueLines(of text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return "" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
