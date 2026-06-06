// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";

import {HarnessRules} from "../../src/libraries/HarnessRules.sol";
import {ResolutionTypes} from "../../src/libraries/ResolutionTypes.sol";

/// @title HarnessOracle — replay a verdict through the actual HarnessRules.sol
/// @notice The eval-harness's TS scorer subprocess-invokes this script per verdict so the
///         ground-truth enforcement is the canonical Solidity logic, not a TS literal mirror.
///         Drift between Solidity and TS becomes structurally impossible.
///
/// @dev Invocation (from interpretive-markets repo root):
///     forge script script/eval/HarnessOracle.s.sol:HarnessOracle \
///         --sig "enforce(uint8,uint16,uint8,string[],string,string,string[])" \
///         --no-storage-caching \
///         -- <outcome> <confidenceBps> <drivingTier> <citations> <subjectRef> <pathPrefix> <subjects>
///
///     Output (parsed by the TS subprocess wrapper as the line starting with "ORACLE:"):
///         ORACLE:enforcedOutcome=<u>,enforcedConfidenceBps=<u>,floorFired=<bool>,tierCapFired=<bool>,citationsValid=<bool>,subjectValid=<bool>,wellFormed=<bool>
contract HarnessOracle is Script {
    function enforce(
        uint8 outcome,
        uint16 confidenceBps,
        uint8 drivingTier,
        string[] memory citations,
        string memory subjectRef,
        string memory pathPrefix,
        string[] memory subjects
    ) public pure {
        ResolutionTypes.ParsedVerdict memory parsed = ResolutionTypes.ParsedVerdict({
            outcome: outcome,
            confidenceBps: confidenceBps,
            drivingTier: drivingTier,
            subjectRef: subjectRef,
            citations: citations,
            rationaleHash: bytes32(0)
        });
        ResolutionTypes.DossierManifest memory manifest = ResolutionTypes.DossierManifest({
            pathPrefix: pathPrefix,
            subjects: subjects
        });

        bool wellFormed = HarnessRules.isWellFormed(parsed);
        bool citationsValid = HarnessRules.validateCitations(parsed.citations, manifest);
        bool subjectValid = HarnessRules.validateSubject(parsed.subjectRef, manifest);

        uint8 enforcedOutcome = HarnessRules.enforceConfidenceFloor(parsed.outcome, parsed.confidenceBps);
        bool floorFired = enforcedOutcome != parsed.outcome;

        uint16 enforcedConfidenceBps = HarnessRules.capByDrivingTier(parsed.confidenceBps, parsed.drivingTier);
        bool tierCapFired = enforcedConfidenceBps != parsed.confidenceBps;

        console2.log("ORACLE_BEGIN");
        console2.log("enforcedOutcome", uint256(enforcedOutcome));
        console2.log("enforcedConfidenceBps", uint256(enforcedConfidenceBps));
        console2.log("floorFired", floorFired);
        console2.log("tierCapFired", tierCapFired);
        console2.log("citationsValid", citationsValid);
        console2.log("subjectValid", subjectValid);
        console2.log("wellFormed", wellFormed);
        console2.log("ORACLE_END");
    }
}
