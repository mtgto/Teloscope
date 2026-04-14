// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class ScopeSpans {
    var scopeName: String
    var scopeVersion: String
    @Relationship(deleteRule: .cascade)
    var spans: [Span]

    init(scopeName: String = "", scopeVersion: String = "", spans: [Span] = []) {
        self.scopeName = scopeName
        self.scopeVersion = scopeVersion
        self.spans = spans
    }
}
