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
}
