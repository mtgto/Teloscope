// SPDX-License-Identifier: MIT
import Testing
@testable import Teloscope

struct ModelPricingTests {
    @Test func knownModelOpusCost() throws {
        let p = try #require(ModelPricing.pricing(for: "claude-opus-4"))
        // 1M input tokens at $5/M
        #expect(abs(p.cost(inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0) - 5.0) < 0.001)
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
        // 0 input, 1M output at $25, 1M cache read at $0.5 → $25.5
        #expect(abs(p.cost(inputTokens: 0, outputTokens: 1_000_000, cacheReadTokens: 1_000_000) - 25.5) < 0.001)
    }

    @Test func fable5Pricing() throws {
        let p = try #require(ModelPricing.pricing(for: "claude-fable-5"))
        // 1M input at $10, 1M output at $50, 1M cache read at $1 → $61
        #expect(abs(p.cost(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadTokens: 1_000_000) - 61.0) < 0.001)
    }

    @Test func sonnet5Pricing() throws {
        let p = try #require(ModelPricing.pricing(for: "claude-sonnet-5"))
        // 1M input at $3/M
        #expect(abs(p.cost(inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0) - 3.0) < 0.001)
    }

    @Test func haiku45Pricing() throws {
        let p = try #require(ModelPricing.pricing(for: "claude-haiku-4-5-20251001"))
        // 1M input at $1/M
        #expect(abs(p.cost(inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0) - 1.0) < 0.001)
    }
}
