// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class ScopeSpans {
    var scopeName: String
    var scopeVersion: String
    @Relationship(deleteRule: .cascade)
    var spans: [OTLPSpan]

    init(scopeName: String = "", scopeVersion: String = "", spans: [OTLPSpan] = []) {
        self.scopeName = scopeName
        self.scopeVersion = scopeVersion
        self.spans = spans
    }
}
