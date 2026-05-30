// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title ResolutionTypes
/// @notice Shared structs for market verdicts and re-execution bundles
library ResolutionTypes {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice The judge's resolution of a market
    /// @param outcome Application-defined outcome code (e.g. 0=NO, 1=YES, 2=UNRESOLVABLE)
    /// @param confidence Confidence score scaled to 1e18 (0 = none, 1e18 = max)
    /// @param verdictHash keccak256 of the canonical verdict payload (JSON serialization defined off-chain)
    struct Verdict {
        uint8 outcome;
        uint256 confidence;
        bytes32 verdictHash;
    }
}
