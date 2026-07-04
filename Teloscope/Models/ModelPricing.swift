// SPDX-License-Identifier: MIT

struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheReadPerMillion: Double

    // Ordered list — first prefix match wins. Uses standard (non-introductory) pricing.
    // Source: https://docs.anthropic.com/en/docs/about-claude/pricing
    private static let table: [(prefix: String, pricing: ModelPricing)] = [
        ("claude-fable-5",   ModelPricing(inputPerMillion: 10.0, outputPerMillion: 50.0,  cacheReadPerMillion: 1.00)),
        ("claude-sonnet-5",  ModelPricing(inputPerMillion:  3.0, outputPerMillion: 15.0,  cacheReadPerMillion: 0.30)),
        ("claude-opus-4",    ModelPricing(inputPerMillion:  5.0, outputPerMillion: 25.0,  cacheReadPerMillion: 0.50)),
        ("claude-sonnet-4",  ModelPricing(inputPerMillion:  3.0, outputPerMillion: 15.0,  cacheReadPerMillion: 0.30)),
        ("claude-haiku-4-5", ModelPricing(inputPerMillion:  1.0, outputPerMillion:  5.0,  cacheReadPerMillion: 0.10)),
    ]

    /// Returns pricing for the given model name using prefix matching, or nil if unknown.
    static func pricing(for model: String) -> ModelPricing? {
        table.first { model.hasPrefix($0.prefix) }?.pricing
    }

    /// Total cost in USD for the given token counts.
    func cost(inputTokens: Int64, outputTokens: Int64, cacheReadTokens: Int64) -> Double {
        Double(inputTokens)      * inputPerMillion      / 1_000_000
            + Double(outputTokens)    * outputPerMillion     / 1_000_000
            + Double(cacheReadTokens) * cacheReadPerMillion  / 1_000_000
    }
}
