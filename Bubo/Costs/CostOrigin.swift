import Foundation

/// Where a figure in the CostLedger comes from (spec 18): every figure says it, next to its unit.
nonisolated enum CostOrigin: String, Codable, CaseIterable, Sendable {
    /// The provider wrote it in the answer: OpenRouter's `usage.cost`.
    case reported
    /// The SDK's list-price estimate of a Claude turn, with its `costBasis`.
    case listEstimate
    /// Tokens times the prices of the PriceTable, of the day the table was read.
    case priceTable
    /// A model the PriceTable does not have: only its tokens count, no figure is made up.
    case unpriced
    /// A model on the Mac: nothing to pay.
    case free
}
