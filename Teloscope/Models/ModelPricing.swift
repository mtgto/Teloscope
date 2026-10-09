// SPDX-License-Identifier: MIT

struct ModelPricing {
    /// Rates in USD per million tokens for one pricing tier.
    struct Rates {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheReadPerMillion: Double

        /// Writing to the cache costs 1.25x the base input rate on every Claude model
        /// (5-minute TTL, the default). The OTLP attribute does not carry the TTL, so
        /// 1-hour-TTL writes (2x base input) are under-counted.
        var cacheWritePerMillion: Double { inputPerMillion * 1.25 }
    }

    let standard: Rates

    /// Rates for prompts longer than `longPromptThreshold`, on models priced by prompt
    /// length (Claude Haiku 5.5). `nil` on every flat-rate model.
    let longPrompt: Rates?

    /// Prompts of this length or shorter bill at `standard`; longer ones at `longPrompt`.
    static let longPromptThreshold: Int64 = 100_000

    init(
        inputPerMillion: Double,
        outputPerMillion: Double,
        cacheReadPerMillion: Double,
        longPrompt: Rates? = nil
    ) {
        self.standard = Rates(
            inputPerMillion: inputPerMillion,
            outputPerMillion: outputPerMillion,
            cacheReadPerMillion: cacheReadPerMillion
        )
        self.longPrompt = longPrompt
    }

    // Ordered list — first prefix match wins. Uses standard (non-introductory) pricing.
    // More specific prefixes must come before their shorter generic fallback.
    // Cache reads are 0.1x the base input rate except where noted below.
    // Source: https://platform.claude.com/docs/en/about-claude/pricing
    private static let table: [(prefix: String, pricing: ModelPricing)] = [
        ("claude-fable-5-1",  ModelPricing(inputPerMillion: 10.0, outputPerMillion: 50.0, cacheReadPerMillion: 0.25)),
        ("claude-mythos-5-1", ModelPricing(inputPerMillion: 10.0, outputPerMillion: 50.0, cacheReadPerMillion: 0.25)),
        ("claude-fable-5",    ModelPricing(inputPerMillion: 10.0, outputPerMillion: 50.0, cacheReadPerMillion: 1.00)),
        ("claude-mythos-5",   ModelPricing(inputPerMillion: 10.0, outputPerMillion: 50.0, cacheReadPerMillion: 1.00)),
        ("claude-opus-5-5",   ModelPricing(inputPerMillion:  4.0, outputPerMillion: 20.0, cacheReadPerMillion: 0.20)),
        ("claude-opus-5",     ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50)),
        ("claude-sonnet-5-5", ModelPricing(inputPerMillion:  2.0, outputPerMillion: 10.0, cacheReadPerMillion: 0.10)),
        ("claude-sonnet-5",   ModelPricing(inputPerMillion:  2.0, outputPerMillion: 10.0, cacheReadPerMillion: 0.20)),
        ("claude-opus-4-8",   ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50)),
        ("claude-opus-4-7",   ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50)),
        ("claude-opus-4-6",   ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50)),
        ("claude-opus-4-5",   ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50)),
        ("claude-opus-4",     ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.50)),
        ("claude-sonnet-4",   ModelPricing(inputPerMillion:  3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.30)),
        // Haiku 5.5 is the only model priced by prompt length: a prompt over 100k tokens
        // bills at 5x the short-prompt rate in every token category.
        ("claude-haiku-5-5",  ModelPricing(inputPerMillion:  0.10, outputPerMillion: 0.50, cacheReadPerMillion: 0.01,
                                           longPrompt: Rates(inputPerMillion: 0.50, outputPerMillion: 2.50, cacheReadPerMillion: 0.05))),
        ("claude-haiku-4-5",  ModelPricing(inputPerMillion:  1.0, outputPerMillion:  5.0, cacheReadPerMillion: 0.10)),
        ("claude-haiku-3-5",  ModelPricing(inputPerMillion:  0.8, outputPerMillion:  4.0, cacheReadPerMillion: 0.08)),
    ]

    /// Returns pricing for the given model name using prefix matching, or nil if unknown.
    static func pricing(for model: String) -> ModelPricing? {
        table.first { model.hasPrefix($0.prefix) }?.pricing
    }

    /// Total cost in USD for the given token counts, billed as a single request.
    ///
    /// Every input token the request was billed for counts toward the prompt length that
    /// picks the tier, cached ones included — so callers must pass one request's counts,
    /// not a sum over several.
    func cost(
        inputTokens: Int64,
        outputTokens: Int64,
        cacheReadTokens: Int64,
        cacheCreationTokens: Int64
    ) -> Double {
        let promptTokens = inputTokens + cacheReadTokens + cacheCreationTokens
        let rates = if let longPrompt, promptTokens > Self.longPromptThreshold {
            longPrompt
        } else {
            standard
        }

        return Double(inputTokens)          * rates.inputPerMillion      / 1_000_000
            + Double(outputTokens)       * rates.outputPerMillion     / 1_000_000
            + Double(cacheReadTokens)    * rates.cacheReadPerMillion  / 1_000_000
            + Double(cacheCreationTokens) * rates.cacheWritePerMillion / 1_000_000
    }
}
