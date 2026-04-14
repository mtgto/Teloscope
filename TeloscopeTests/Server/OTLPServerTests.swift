// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import Teloscope

struct OTLPServerTests {
    @Test func serverStartsAndStops() async throws {
        let server = OTLPServer()
        #expect(!server.isRunning)
        try await server.start(port: 14318) { _ in }
        #expect(server.isRunning)
        try await server.stop()
        #expect(!server.isRunning)
    }

    @Test func serverReceivesTracesRequest() async throws {
        let server = OTLPServer()
        var receivedRequests: [OTLPRequest] = []
        try await server.start(port: 14319) { request in
            receivedRequests.append(request)
        }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:14319/v1/traces")!)
        req.httpMethod = "POST"
        req.httpBody = Data([0x01, 0x02])
        req.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        _ = try await URLSession.shared.data(for: req)

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(receivedRequests.count == 1)
        if case .traces(let data) = receivedRequests[0] {
            #expect(data == Data([0x01, 0x02]))
        } else {
            Issue.record("Expected .traces request")
        }

        try await server.stop()
    }

    @Test func serverReturns404ForUnknownPath() async throws {
        let server = OTLPServer()
        try await server.start(port: 14320) { _ in }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:14320/v1/unknown")!)
        req.httpMethod = "POST"
        req.httpBody = Data()
        let (_, response) = try await URLSession.shared.data(for: req)
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 404)

        try await server.stop()
    }
}
