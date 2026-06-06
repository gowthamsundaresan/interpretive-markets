// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ResolutionTypes} from "./ResolutionTypes.sol";
import {DossierManifest} from "./DossierManifest.sol";

/// @title HarnessRules
/// @notice Pure functions enforcing the rule-of-engagement constraints on parsed verdicts
/// @dev Rules and their motivations are described in PLAN.md §2 and DECISIONS.md ADR-009.
///      Range/structure failures detected here route the verdict to the dispute path, not revert.
library HarnessRules {
    // ------------------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------------------

    /// @notice Confidence floor below which outcome is forced to UNRESOLVABLE (2)
    uint16 internal constant CONFIDENCE_FLOOR_BPS = 5500;

    /// @notice Confidence cap applied when the driving tier is the weakest tier (3)
    uint16 internal constant TIER_3_CAP_BPS = 6500;

    /// @notice Maximum permissible confidence value (basis points)
    uint16 internal constant CONFIDENCE_MAX_BPS = 10000;

    /// @notice Outcome code reserved for abstention / unresolvable markets
    uint8 internal constant OUTCOME_UNRESOLVABLE = 2;

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @notice Force outcome to UNRESOLVABLE when confidence falls below the floor
    /// @param outcome The LLM's emitted outcome
    /// @param confidenceBps The LLM's emitted confidence in basis points
    /// @return enforcedOutcome The outcome after applying the confidence floor
    function enforceConfidenceFloor(uint8 outcome, uint16 confidenceBps) internal pure returns (uint8 enforcedOutcome) {
        enforcedOutcome = confidenceBps < CONFIDENCE_FLOOR_BPS ? OUTCOME_UNRESOLVABLE : outcome;
    }

    /// @notice Cap confidence when the driving tier is the weakest tier
    /// @param confidenceBps The LLM's emitted confidence
    /// @param drivingTier The LLM's declared driving tier (1, 2, or 3)
    /// @return cappedConfidenceBps The confidence after tier-3 capping
    function capByDrivingTier(
        uint16 confidenceBps,
        uint8 drivingTier
    ) internal pure returns (uint16 cappedConfidenceBps) {
        if (drivingTier == 3 && confidenceBps > TIER_3_CAP_BPS) {
            cappedConfidenceBps = TIER_3_CAP_BPS;
        } else {
            cappedConfidenceBps = confidenceBps;
        }
    }

    /// @notice Validate that every citation starts with the manifest's required prefix
    /// @param citations The citation strings emitted by the LLM
    /// @param manifest The dossier manifest active for this market
    /// @return ok True when every citation has the required prefix and the list is non-empty
    function validateCitations(
        string[] memory citations,
        ResolutionTypes.DossierManifest memory manifest
    ) internal pure returns (bool ok) {
        if (citations.length == 0) return false;
        for (uint256 i = 0; i < citations.length; i++) {
            if (!DossierManifest.hasPrefix(citations[i], manifest.pathPrefix)) return false;
        }
        ok = true;
    }

    /// @notice Validate that the subject reference is one of the manifest's allowed subjects
    /// @param subjectRef The subject identifier emitted by the LLM
    /// @param manifest The dossier manifest active for this market
    /// @return ok True when subjectRef matches one of manifest.subjects
    function validateSubject(
        string memory subjectRef,
        ResolutionTypes.DossierManifest memory manifest
    ) internal pure returns (bool ok) {
        bytes32 target = keccak256(bytes(subjectRef));
        for (uint256 i = 0; i < manifest.subjects.length; i++) {
            if (keccak256(bytes(manifest.subjects[i])) == target) return true;
        }
        ok = false;
    }

    /// @notice Determine whether a parsed verdict is well-formed in its typed fields
    /// @param parsed The parsed verdict to inspect
    /// @return wellFormed True when outcome/confidence/driving_tier are all in range
    function isWellFormed(ResolutionTypes.ParsedVerdict memory parsed) internal pure returns (bool wellFormed) {
        wellFormed =
            parsed.outcome <= OUTCOME_UNRESOLVABLE &&
            parsed.confidenceBps <= CONFIDENCE_MAX_BPS &&
            parsed.drivingTier >= 1 &&
            parsed.drivingTier <= 3;
    }
}
