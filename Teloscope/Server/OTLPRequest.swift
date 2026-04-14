// SPDX-License-Identifier: MIT
import Foundation

enum OTLPRequest {
    case traces(Data)
    case metrics(Data)
    case logs(Data)
}
