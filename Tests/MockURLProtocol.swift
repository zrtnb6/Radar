import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    private static var handler: Handler?
    private static var requests: [URLRequest] = []
    private static var activeRequests = 0
    private static var maximumActiveRequests = 0

    static func setHandler(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        requests = []
        activeRequests = 0
        maximumActiveRequests = 0
        lock.unlock()
    }

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static var maxConcurrentRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumActiveRequests
    }

    static func resetConcurrencyStats() {
        lock.lock()
        maximumActiveRequests = 0
        lock.unlock()
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.activeRequests += 1
        Self.maximumActiveRequests = max(Self.maximumActiveRequests, Self.activeRequests)
        let handler = Self.handler
        Self.lock.unlock()

        defer {
            Self.lock.lock()
            Self.activeRequests -= 1
            Self.lock.unlock()
        }

        do {
            guard let handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func mockResponse(url: URL, status: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
}
