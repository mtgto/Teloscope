// SPDX-License-Identifier: MIT
import Testing
@testable import Teloscope

struct ModelPricingTests {
    @Test func knownModelOpusCost() throws {
        let p = try #require(ModelPricing.pricing(for: "claude-opus-4"))
        // 1M input tokens at $15/M
        #expect(abs(p.cost(inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0) - 15.0) < 0.001)
    }

    @Test func prefixMatchingSonnet() throws {
        // "claude-sonnet-4-6-20251022" should match "claude-sonnet-4" prefix
        let p = try #require(ModelPricing.pricing(for: "claude-sonnet-4-6-20251022"))
        #expect(abs(p.cost(inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0) - 3.0) < 0.001)
    }

    @Test func unknownModelReturnsNil() {
        #expect(ModelPricing.pricing(for: "gpt-4") == nil)
    }

    @Test func costSumsAllTokenTypes() throws {
        let p = try #require(ModelPricing.pricing(for: "claude-opus-4"))
        // 0 input, 1M output at $75, 1M cache read at $1.5 → $76.5
        #expect(abs(p.cost(inputTokens: 0, outputTokens: 1_000_000, cacheReadTokens: 1_000_000) - 76.5) < 0.001)
    }
}
