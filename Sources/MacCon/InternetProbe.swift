import Foundation

/// Checks real internet reachability by fetching small, well-known HTTPS endpoints.
struct InternetProbe {
    private struct Endpoint {
        let url: URL
        let expectedStatus: Int
    }

    private let endpoints = [
        Endpoint(url: URL(string: "https://www.gstatic.com/generate_204")!, expectedStatus: 204),
        Endpoint(url: URL(string: "https://www.apple.com/library/test/success.html")!, expectedStatus: 200),
    ]

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    /// True as soon as any endpoint answers with its expected status.
    func isInternetReachable() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            for endpoint in endpoints {
                group.addTask { await fetchSucceeds(endpoint) }
            }
            for await succeeded in group where succeeded {
                group.cancelAll()
                return true
            }
            return false
        }
    }

    private func fetchSucceeds(_ endpoint: Endpoint) async -> Bool {
        do {
            let (_, response) = try await session.data(from: endpoint.url, delegate: RedirectBlocker())
            return (response as? HTTPURLResponse)?.statusCode == endpoint.expectedStatus
        } catch {
            return false
        }
    }
}

/// Refuses redirects, so a captive portal's login redirect counts as "no internet".
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
