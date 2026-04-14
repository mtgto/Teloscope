// SPDX-License-Identifier: MIT
import Foundation
import NIO
import NIOHTTP1

final class OTLPHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let onRequest: (OTLPRequest) -> Void
    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(onRequest: @escaping (OTLPRequest) -> Void) {
        self.onRequest = onRequest
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            bodyBuffer = context.channel.allocator.buffer(capacity: 256)
        case .body(var buf):
            bodyBuffer?.writeBuffer(&buf)
        case .end:
            guard let head = requestHead, let bodyBuffer else { return }
            handle(context: context, head: head, body: bodyBuffer)
        }
    }

    private func handle(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer) {
        guard head.method == .POST else {
            respond(context: context, status: .methodNotAllowed)
            return
        }
        let bytes = Data(body.readableBytesView)
        switch head.uri {
        case "/v1/traces":
            onRequest(.traces(bytes))
            respond(context: context, status: .ok)
        case "/v1/metrics":
            onRequest(.metrics(bytes))
            respond(context: context, status: .ok)
        case "/v1/logs":
            onRequest(.logs(bytes))
            respond(context: context, status: .ok)
        default:
            respond(context: context, status: .notFound)
        }
    }

    private func respond(context: ChannelHandlerContext, status: HTTPResponseStatus) {
        let head = HTTPResponseHead(version: .http1_1, status: status)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
