// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title ResolutionTypes
/// @notice Shared structs for market verdicts and dossier manifests on Ritual L1
/// @dev confidence is encoded as basis points (0..10000) to avoid float math in Solidity (ADR-003).
///      Free-form rationale text is kept off-chain in the audit bundle; only its keccak256 hash is
///      bound on-chain (ADR-009).
library ResolutionTypes {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice The judge's resolution of a market, parsed from the 0x0802 LLM completionData
    /// @param outcome Application-defined outcome code (0=NO, 1=YES, 2=UNRESOLVABLE)
    /// @param confidenceBps Confidence in basis points (0..10000); >10000 is malformed
    /// @param drivingTier Evidence tier that dominated reasoning (1, 2, or 3); others are malformed
    /// @param subjectRef Subject identifier; must match one of the dossier subjects[]
    /// @param rationaleHash keccak256 of the LLM's full rationale text (text lives in the audit bundle)
    /// @param verdictHash keccak256 over the canonical verdict serialization (binding for the audit bundle)
    /// @param dossierCid IPFS CID of the dossier the verdict was rendered against
    /// @param executor Attested executor address that delivered the resolution callback
    /// @param attestedAtBlock Block number at which the callback delivery was recorded
    struct Verdict {
        uint8 outcome;
        uint16 confidenceBps;
        uint8 drivingTier;
        string subjectRef;
        bytes32 rationaleHash;
        bytes32 verdictHash;
        string dossierCid;
        address executor;
        uint64 attestedAtBlock;
    }

    /// @notice Parsed view of the LLM's verdict JSON before HarnessRules normalization
    /// @param outcome Raw outcome code emitted by the LLM
    /// @param confidenceBps Confidence emitted by the LLM (may be out of range; HarnessRules flags)
    /// @param drivingTier Driving tier emitted by the LLM (may be invalid; HarnessRules flags)
    /// @param subjectRef Subject identifier emitted by the LLM
    /// @param citations Citation strings emitted by the LLM (each must prefix-match a dossier path)
    /// @param rationaleHash keccak256 of the rationale text emitted by the LLM
    struct ParsedVerdict {
        uint8 outcome;
        uint16 confidenceBps;
        uint8 drivingTier;
        string subjectRef;
        string[] citations;
        bytes32 rationaleHash;
    }

    /// @notice Dossier path manifest used to validate citations and subject references
    /// @param pathPrefix Required prefix every citation must start with (e.g. "dossier://")
    /// @param subjects Allowed subject identifiers
    struct DossierManifest {
        string pathPrefix;
        string[] subjects;
    }
}
