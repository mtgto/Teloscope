// SPDX-License-Identifier: MIT
import Foundation

enum OTLPRequest: Sendable {
    case traces(Data)
    case metrics(Data)
    case logs(Data)
}
