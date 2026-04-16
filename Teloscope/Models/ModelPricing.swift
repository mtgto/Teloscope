// SPDX-License-Identifier: MIT
import Foundation

struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheReadPerMillion: Double

    // Ordered list — first prefix match wins.
    private static let table: [(prefix: String, pricing: ModelPricing)] = [
        ("claude-opus-4",    ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0,  cacheReadPerMillion: 1.50)),
        ("claude-sonnet-4",  ModelPricing(inputPerMillion:  3.0, outputPerMillion: 15.0,  cacheReadPerMillion: 0.30)),
        ("claude-haiku-4-5", ModelPricing(inputPerMillion:  0.8, outputPerMillion:  4.0,  cacheReadPerMillion: 0.08)),
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
