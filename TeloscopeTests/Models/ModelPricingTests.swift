// SPDX-License-Identifier: MIT
import Testing
@testable import Teloscope

struct ModelPricingTests {
    /// One row of the published price table, in USD per million tokens.
    /// Source: https://platform.claude.com/docs/en/about-claude/pricing
    ///
    /// `model` is the id passed to `pricing(for:)`. Rows using a dated or longer id
    /// double as prefix-matching cases: they must fall through to a shorter entry
    /// (`claude-opus-4-1-...` → `claude-opus-4`) or, for `claude-opus-5-5`, must *not*
    /// fall through to the shorter `claude-opus-5`.
    ///
    /// Haiku 5.5 is absent on purpose: the test below bills one token type at a time, so
    /// the prompt length — and with it Haiku 5.5's tier — differs from call to call. Its
    /// two tiers get their own tests further down.
    struct Rates: Sendable, CustomTestStringConvertible {
        let model: String
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double

        var testDescription: String { model }
    }

    @Test(arguments: [
        Rates(model: "claude-fable-5-1",           input: 10.0, output: 50.0, cacheRead: 0.25, cacheWrite: 12.50),
        Rates(model: "claude-mythos-5-1",          input: 10.0, output: 50.0, cacheRead: 0.25, cacheWrite: 12.50),
        Rates(model: "claude-fable-5",             input: 10.0, output: 50.0, cacheRead: 1.00, cacheWrite: 12.50),
        Rates(model: "claude-mythos-5",            input: 10.0, output: 50.0, cacheRead: 1.00, cacheWrite: 12.50),
        Rates(model: "claude-opus-5-5",            input:  4.0, output: 20.0, cacheRead: 0.20, cacheWrite:  5.00),
        Rates(model: "claude-opus-5",              input:  5.0, output: 25.0, cacheRead: 0.50, cacheWrite:  6.25),
        Rates(model: "claude-sonnet-5-5",          input:  2.0, output: 10.0, cacheRead: 0.10, cacheWrite:  2.50),
        Rates(model: "claude-sonnet-5",            input:  2.0, output: 10.0, cacheRead: 0.20, cacheWrite:  2.50),
        Rates(model: "claude-opus-4-8",            input:  5.0, output: 25.0, cacheRead: 0.50, cacheWrite:  6.25),
        Rates(model: "claude-opus-4-7",            input:  5.0, output: 25.0, cacheRead: 0.50, cacheWrite:  6.25),
        Rates(model: "claude-opus-4-6",            input:  5.0, output: 25.0, cacheRead: 0.50, cacheWrite:  6.25),
        Rates(model: "claude-opus-4-5",            input:  5.0, output: 25.0, cacheRead: 0.50, cacheWrite:  6.25),
        Rates(model: "claude-opus-4-1-20250805",   input: 15.0, output: 75.0, cacheRead: 1.50, cacheWrite: 18.75),
        Rates(model: "claude-sonnet-4-6-20251022", input:  3.0, output: 15.0, cacheRead: 0.30, cacheWrite:  3.75),
        Rates(model: "claude-haiku-4-5-20251001",  input:  1.0, output:  5.0, cacheRead: 0.10, cacheWrite:  1.25),
        Rates(model: "claude-haiku-3-5",           input:  0.8, output:  4.0, cacheRead: 0.08, cacheWrite:  1.00),
    ])
    func costMatchesPublishedRates(_ rates: Rates) throws {
        let p = try #require(ModelPricing.pricing(for: rates.model))
        let million: Int64 = 1_000_000

        // Bill one token type at a time so a wrong rate names itself, then all four
        // together to cover the summing.
        #expect(abs(p.cost(inputTokens: million, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0) - rates.input) < 0.001)
        #expect(abs(p.cost(inputTokens: 0, outputTokens: million, cacheReadTokens: 0, cacheCreationTokens: 0) - rates.output) < 0.001)
        #expect(abs(p.cost(inputTokens: 0, outputTokens: 0, cacheReadTokens: million, cacheCreationTokens: 0) - rates.cacheRead) < 0.001)
        #expect(abs(p.cost(inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: million) - rates.cacheWrite) < 0.001)

        let total = rates.input + rates.output + rates.cacheRead + rates.cacheWrite
        #expect(abs(p.cost(inputTokens: million, outputTokens: million, cacheReadTokens: million, cacheCreationTokens: million) - total) < 0.001)
    }

    @Test func unknownModelReturnsNil() {
        #expect(ModelPricing.pricing(for: "gpt-4") == nil)
    }

    /// Haiku 5.5's published rates, both tiers, billing every token category in one
    /// request so the prompt length that picks the tier stays fixed across the four rates.
    /// Source: https://platform.claude.com/docs/en/about-claude/pricing
    @Test func haiku55BillsEachTierAtPublishedRates() throws {
        let p = try #require(ModelPricing.pricing(for: "claude-haiku-5-5"))

        // 80k prompt — under the boundary, so $0.10 / $0.50 / $0.01 / $0.125.
        let short = p.cost(inputTokens: 50_000, outputTokens: 10_000, cacheReadTokens: 20_000, cacheCreationTokens: 10_000)
        let shortExpected = 50_000 * 0.10 / 1_000_000
            + 10_000 * 0.50 / 1_000_000
            + 20_000 * 0.01 / 1_000_000
            + 10_000 * 0.125 / 1_000_000
        #expect(abs(short - shortExpected) < 1e-9)

        // 270k prompt — over the boundary, so 5x each rate.
        let long = p.cost(inputTokens: 200_000, outputTokens: 10_000, cacheReadTokens: 50_000, cacheCreationTokens: 20_000)
        let longExpected = 200_000 * 0.50 / 1_000_000
            + 10_000 * 2.50 / 1_000_000
            + 50_000 * 0.05 / 1_000_000
            + 20_000 * 0.625 / 1_000_000
        #expect(abs(long - longExpected) < 1e-9)
    }

    /// The boundary is inclusive: 100k tokens is still a short prompt, 100k + 1 is not.
    @Test(arguments: [
        (promptTokens: Int64(100_000), expected: 100_000 * 0.10 / 1_000_000),
        (promptTokens: Int64(100_001), expected: 100_001 * 0.50 / 1_000_000),
    ])
    func haiku55SwitchesTierAtTheBoundary(promptTokens: Int64, expected: Double) throws {
        let p = try #require(ModelPricing.pricing(for: "claude-haiku-5-5"))

        let cost = p.cost(inputTokens: promptTokens, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0)
        #expect(abs(cost - expected) < 1e-9)
    }

    /// Cached tokens were part of the prompt, so they count toward the tier even though
    /// they are billed at the cache rates.
    @Test func haiku55CountsCachedTokensTowardThePromptLength() throws {
        let p = try #require(ModelPricing.pricing(for: "claude-haiku-5-5"))

        // 50k uncached + 50,001 cache reads = 100,001 prompt tokens, one past the boundary,
        // even though neither count exceeds it alone.
        let cost = p.cost(inputTokens: 50_000, outputTokens: 0, cacheReadTokens: 50_001, cacheCreationTokens: 0)
        let longTier = 50_000 * 0.50 / 1_000_000 + 50_001 * 0.05 / 1_000_000
        #expect(abs(cost - longTier) < 1e-9)
    }

    /// Prompt length must not move the rates on a model that publishes a single tier.
    @Test func flatRateModelIgnoresPromptLength() throws {
        let p = try #require(ModelPricing.pricing(for: "claude-sonnet-5-5"))

        let short = p.cost(inputTokens: 1_000, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0)
        let long  = p.cost(inputTokens: 200_000, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0)
        #expect(abs(short - 1_000 * 2.0 / 1_000_000) < 1e-9)
        #expect(abs(long - 200_000 * 2.0 / 1_000_000) < 1e-9)
    }
}
