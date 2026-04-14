// SPDX-License-Identifier: MIT
import Foundation
import NIO
import NIOHTTP1
import Observation

@Observable
final class OTLPServer: @unchecked Sendable {
    private(set) var isRunning = false
    var lastError: String?

    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?

    func start(port: Int, onRequest: @escaping (OTLPRequest) -> Void) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.group = group

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(OTLPHTTPHandler(onRequest: onRequest))
                }
            }

        do {
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
            self.channel = channel
            await MainActor.run {
                self.isRunning = true
                self.lastError = nil
            }
        } catch {
            try? await group.shutdownGracefully()
            self.group = nil
            throw error
        }
    }

    func stop() async throws {
        try await channel?.close().get()
        try await group?.shutdownGracefully()
        channel = nil
        group = nil
        await MainActor.run {
            isRunning = false
        }
    }
}
