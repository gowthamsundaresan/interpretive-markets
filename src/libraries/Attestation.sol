// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title Attestation
/// @notice Thin helper for recording TEE executor identity at callback delivery time
/// @dev Per ADR-002 and ADR-005, this library does NOT perform DCAP-style quote verification.
///      Attestation is enforced upstream by the Ritual block builder against TEEServiceRegistry.
///      The consumer's trust boundary is `msg.sender == ASYNC_DELIVERY`; this helper exists so
///      the watcher can do off-chain consistency auditing from the recorded executor and block.
library Attestation {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Executor identity recorded at callback delivery
    /// @param executor Address of the TEE executor that returned the callback
    /// @param attestedAtBlock Block number at which the callback was delivered
    /// @param requestBinding keccak256 of the canonical request inputs (recomputable by the watcher)
    struct Record {
        address executor;
        uint64 attestedAtBlock;
        bytes32 requestBinding;
    }

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @notice Build a Record from the current callback context
    /// @param executor The attested executor address (read from the delivery context)
    /// @param requestBinding keccak256 of the canonical request inputs serialized off-chain
    /// @return record The freshly built record bound to the current block
    function recordOf(address executor, bytes32 requestBinding) internal view returns (Record memory record) {
        record = Record({executor: executor, attestedAtBlock: uint64(block.number), requestBinding: requestBinding});
    }
}
