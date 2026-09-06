// SPDX-License-Identifier: MIT

struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheReadPerMillion: Double

    /// Writing to the cache costs 1.25x the base input rate on every Claude model
    /// (5-minute TTL, the default). The OTLP attribute does not carry the TTL, so
    /// 1-hour-TTL writes (2x base input) are under-counted.
    var cacheWritePerMillion: Double { inputPerMillion * 1.25 }

    // Ordered list — first prefix match wins. Uses standard (non-introductory) pricing.
    // More specific prefixes must come before their shorter generic fallback.
    // Source: https://docs.anthropic.com/en/docs/about-claude/pricing
    private static let table: [(prefix: String, pricing: ModelPricing)] = [
        ("claude-fable-5",   ModelPricing(inputPerMillion: 10.0, outputPerMillion: 50.0, cacheReadPerMillion: 1.00)),
        ("claude-mythos-5",  ModelPricing(inputPerMillion: 10.0, outputPerMillion: 50.0, cacheReadPerMillion: 1.00)),
        ("claude-opus-5",    ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50)),
        ("claude-sonnet-5",  ModelPricing(inputPerMillion:  3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.30)),
        ("claude-opus-4-8",  ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50)),
        ("claude-opus-4-7",  ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50)),
        ("claude-opus-4-6",  ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50)),
        ("claude-opus-4-5",  ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50)),
        // Claude Opus 4 / 4.1 predate the Opus 4.5 price drop.
        ("claude-opus-4",    ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.50)),
        ("claude-sonnet-4",  ModelPricing(inputPerMillion:  3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.30)),
        ("claude-haiku-4-5", ModelPricing(inputPerMillion:  1.0, outputPerMillion:  5.0, cacheReadPerMillion: 0.10)),
        ("claude-haiku-3-5", ModelPricing(inputPerMillion:  0.8, outputPerMillion:  4.0, cacheReadPerMillion: 0.08)),
    ]

    /// Returns pricing for the given model name using prefix matching, or nil if unknown.
    static func pricing(for model: String) -> ModelPricing? {
        table.first { model.hasPrefix($0.prefix) }?.pricing
    }

    /// Total cost in USD for the given token counts.
    func cost(
        inputTokens: Int64,
        outputTokens: Int64,
        cacheReadTokens: Int64,
        cacheCreationTokens: Int64
    ) -> Double {
        Double(inputTokens)          * inputPerMillion      / 1_000_000
            + Double(outputTokens)       * outputPerMillion     / 1_000_000
            + Double(cacheReadTokens)    * cacheReadPerMillion  / 1_000_000
            + Double(cacheCreationTokens) * cacheWritePerMillion / 1_000_000
    }
}
