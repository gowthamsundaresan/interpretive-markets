// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {HarnessRules} from "../src/libraries/HarnessRules.sol";
import {ResolutionTypes} from "../src/libraries/ResolutionTypes.sol";

contract HarnessRulesTest is Test {
    // --- Types & state ---

    string internal constant PREFIX = "dossier://";

    // --- Core functions ---

    function test_enforceConfidenceFloor_keepsOutcomeAboveFloor() public pure {
        uint8 outcome = HarnessRules.enforceConfidenceFloor(1, 5600);
        assertEq(outcome, 1);
    }

    function test_enforceConfidenceFloor_flipsBelowFloor() public pure {
        uint8 outcome = HarnessRules.enforceConfidenceFloor(1, 5499);
        assertEq(outcome, 2);
    }

    function test_enforceConfidenceFloor_boundaryAtFloorKeepsOutcome() public pure {
        uint8 outcome = HarnessRules.enforceConfidenceFloor(1, 5500);
        assertEq(outcome, 1);
    }

    function test_capByDrivingTier_capsTier3() public pure {
        uint16 conf = HarnessRules.capByDrivingTier(9000, 3);
        assertEq(conf, 6500);
    }

    function test_capByDrivingTier_passesThroughBelowCap() public pure {
        uint16 conf = HarnessRules.capByDrivingTier(6000, 3);
        assertEq(conf, 6000);
    }

    function test_capByDrivingTier_noEffectOnTier1Or2() public pure {
        assertEq(HarnessRules.capByDrivingTier(9000, 1), 9000);
        assertEq(HarnessRules.capByDrivingTier(9000, 2), 9000);
    }

    function test_validateCitations_allOk() public pure {
        string[] memory citations = new string[](2);
        citations[0] = "dossier://stats.x";
        citations[1] = "dossier://quote.y";
        assertTrue(HarnessRules.validateCitations(citations, _manifest("haaland")));
    }

    function test_validateCitations_emptyArrayInvalid() public pure {
        string[] memory empty = new string[](0);
        assertFalse(HarnessRules.validateCitations(empty, _manifest("haaland")));
    }

    function test_validateCitations_badPrefixInvalid() public pure {
        string[] memory citations = new string[](2);
        citations[0] = "dossier://stats.x";
        citations[1] = "http://example.com/y";
        assertFalse(HarnessRules.validateCitations(citations, _manifest("haaland")));
    }

    function test_validateSubject_matchInManifest() public pure {
        assertTrue(HarnessRules.validateSubject("haaland", _manifest("haaland")));
    }

    function test_validateSubject_missFromManifest() public pure {
        assertFalse(HarnessRules.validateSubject("mbappe", _manifest("haaland")));
    }

    function test_isWellFormed_validRanges() public pure {
        ResolutionTypes.ParsedVerdict memory p = _parsedVerdict(1, 7000, 1);
        assertTrue(HarnessRules.isWellFormed(p));
    }

    function test_isWellFormed_outcomeOutOfRange() public pure {
        ResolutionTypes.ParsedVerdict memory p = _parsedVerdict(3, 7000, 1);
        assertFalse(HarnessRules.isWellFormed(p));
    }

    function test_isWellFormed_confidenceOutOfRange() public pure {
        ResolutionTypes.ParsedVerdict memory p = _parsedVerdict(1, 10001, 1);
        assertFalse(HarnessRules.isWellFormed(p));
    }

    function test_isWellFormed_drivingTierOutOfRange() public pure {
        ResolutionTypes.ParsedVerdict memory p0 = _parsedVerdict(1, 7000, 0);
        ResolutionTypes.ParsedVerdict memory p4 = _parsedVerdict(1, 7000, 4);
        assertFalse(HarnessRules.isWellFormed(p0));
        assertFalse(HarnessRules.isWellFormed(p4));
    }

    // --- Helper functions ---

    function _manifest(string memory subject) internal pure returns (ResolutionTypes.DossierManifest memory m) {
        string[] memory subjects = new string[](1);
        subjects[0] = subject;
        m = ResolutionTypes.DossierManifest({pathPrefix: PREFIX, subjects: subjects});
    }

    function _parsedVerdict(
        uint8 outcome,
        uint16 confidenceBps,
        uint8 drivingTier
    ) internal pure returns (ResolutionTypes.ParsedVerdict memory p) {
        p.outcome = outcome;
        p.confidenceBps = confidenceBps;
        p.drivingTier = drivingTier;
        p.subjectRef = "haaland";
        p.citations = new string[](1);
        p.citations[0] = "dossier://stats.x";
        p.rationaleHash = bytes32(0);
    }
}
