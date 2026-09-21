// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import Teloscope

/// Collects callbacks from the server's NIO event loop; the test thread reads them
/// afterwards, so the buffer must not be a plain captured var.
private actor RequestCollector {
    private(set) var requests: [OTLPRequest] = []

    func append(_ request: OTLPRequest) {
        requests.append(request)
    }
}

struct OTLPServerTests {
    @Test func serverStartsAndStops() async throws {
        let server = OTLPServer()
        #expect(!server.isRunning)
        try await server.start(port: 0) { _ in }
        #expect(server.isRunning)
        #expect(server.boundPort != nil)
        try await server.stop()
        #expect(!server.isRunning)
        #expect(server.boundPort == nil)
    }

    @Test func serverReceivesTracesRequest() async throws {
        let server = OTLPServer()
        let collector = RequestCollector()
        try await server.start(port: 0) { request in
            Task { await collector.append(request) }
        }
        let port = try #require(server.boundPort)

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/traces")!)
        req.httpMethod = "POST"
        req.httpBody = Data([0x01, 0x02])
        req.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        _ = try await URLSession.shared.data(for: req)

        try await Task.sleep(nanoseconds: 100_000_000)
        let receivedRequests = await collector.requests
        #expect(receivedRequests.count == 1)
        if case .traces(let data) = receivedRequests.first {
            #expect(data == Data([0x01, 0x02]))
        } else {
            Issue.record("Expected .traces request")
        }

        try await server.stop()
    }

    @Test func serverReturns404ForUnknownPath() async throws {
        let server = OTLPServer()
        try await server.start(port: 0) { _ in }
        let port = try #require(server.boundPort)

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/unknown")!)
        req.httpMethod = "POST"
        req.httpBody = Data()
        let (_, response) = try await URLSession.shared.data(for: req)
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 404)

        try await server.stop()
    }
}
