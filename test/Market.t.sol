// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {FrameworkRegistry} from "../src/core/FrameworkRegistry.sol";
import {Market} from "../src/core/Market.sol";
import {RitualSystem} from "../src/core/RitualSystem.sol";
import {IFrameworkRegistry} from "../src/interfaces/IFrameworkRegistry.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";
import {IRitualSystem} from "../src/interfaces/IRitualSystem.sol";
import {ResolutionTypes} from "../src/libraries/ResolutionTypes.sol";
import {MockPrecompiles} from "./helpers/MockPrecompiles.sol";

contract MarketTest is Test {
    // --- Types & state ---

    FrameworkRegistry internal frameworks;
    RitualSystem internal ritualSystem;
    Market internal market;

    address internal creator;
    address internal disputer;
    address internal asyncDelivery;
    address internal stranger;
    address internal executor;

    bytes32 internal constant FRAMEWORK_ID = keccak256("pedri-framework-v1");
    bytes32 internal constant JOB_ID = bytes32(uint256(0xC0DEBEEF));
    string internal constant DOSSIER_CID = "bafyfakecid";
    string internal constant DOSSIER_PREFIX = "dossier://";

    uint64 internal resolutionTime;

    // --- Core functions ---

    function setUp() public {
        creator = makeAddr("creator");
        disputer = makeAddr("disputer");
        stranger = makeAddr("stranger");
        executor = makeAddr("executor");

        frameworks = new FrameworkRegistry();
        ritualSystem = new RitualSystem();
        market = new Market(frameworks, ritualSystem);
        asyncDelivery = ritualSystem.asyncDelivery();

        frameworks.register(FRAMEWORK_ID, "ipfs://cid", hex"");
        resolutionTime = uint64(block.timestamp + 1 days);
    }

    // ------ createMarket ------

    function test_createMarket_storesRecord() public {
        uint256 id = _create();

        IMarket.Market memory m = market.get(id);
        assertEq(m.init.frameworkId, FRAMEWORK_ID);
        assertEq(m.creator, creator);
        assertEq(m.createdAt, uint64(block.timestamp));
        assertEq(market.nextMarketId(), id + 1);
    }

    function test_createMarket_revertsOnUnknownFramework() public {
        IMarket.MarketInit memory params = _params();
        params.frameworkId = keccak256("nope");
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IMarket.UnknownFramework.selector, params.frameworkId));
        market.createMarket(params);
    }

    function test_createMarket_revertsOnPastResolutionTime() public {
        IMarket.MarketInit memory params = _params();
        params.resolutionTime = uint64(block.timestamp);
        vm.prank(creator);
        vm.expectRevert(IMarket.InvalidResolutionTime.selector);
        market.createMarket(params);
    }

    // ------ startInvestigation ------

    function test_startInvestigation_recordsJobAndEmits() public {
        uint256 id = _create();
        vm.warp(resolutionTime + 1);

        MockPrecompiles.mockSovereignAgentSubmit(vm, JOB_ID);

        market.startInvestigation(id);

        IMarket.Market memory m = market.get(id);
        assertEq(m.investigationJobId, JOB_ID);
        assertEq(m.investigationStartedAt, uint64(block.timestamp));
        assertEq(market.marketIdForJob(JOB_ID), id);
    }

    function test_startInvestigation_revertsBeforeResolutionTime() public {
        uint256 id = _create();
        vm.expectRevert(abi.encodeWithSelector(IMarket.TooEarly.selector, id, resolutionTime));
        market.startInvestigation(id);
    }

    function test_startInvestigation_revertsOnDouble() public {
        uint256 id = _create();
        vm.warp(resolutionTime + 1);
        MockPrecompiles.mockSovereignAgentSubmit(vm, JOB_ID);
        market.startInvestigation(id);
        vm.expectRevert(abi.encodeWithSelector(IMarket.InvestigationAlreadyStarted.selector, id));
        market.startInvestigation(id);
    }

    function test_startInvestigation_revertsOnUnknownMarket() public {
        vm.expectRevert(abi.encodeWithSelector(IMarket.UnknownMarket.selector, uint256(999)));
        market.startInvestigation(999);
    }

    // ------ onSovereignAgentResult — happy path ------

    function test_onSovereignAgentResult_finalizesHappyPath() public {
        uint256 id = _createAndStart();

        string memory verdictJson = MockPrecompiles.buildVerdictJson(
            1,
            7200,
            1,
            "haaland",
            _zeroHashHex(),
            _citations("dossier://stats.x")
        );
        MockPrecompiles.mockJudgeSuccess(vm, bytes(verdictJson));

        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());

        IMarket.Market memory m = market.get(id);
        assertTrue(m.finalized);
        assertFalse(m.malformed);
        assertEq(m.dossierCid, DOSSIER_CID);
        assertEq(m.verdict.outcome, 1);
        assertEq(m.verdict.confidenceBps, 7200);
        assertEq(m.verdict.drivingTier, 1);
        assertEq(m.verdict.subjectRef, "haaland");
        // Per ADR-005/ADR-011, executor identity is resolved by the watcher off-chain via the
        // resolution-tx receipt + TEEServiceRegistry lookup. On-chain we record address(0).
        assertEq(m.verdict.executor, address(0));
    }

    // ------ onSovereignAgentResult — authorization + routing ------

    function test_onSovereignAgentResult_revertsOnUnauthorized() public {
        _createAndStart();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IMarket.Unauthorized.selector, stranger));
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());
    }

    function test_onSovereignAgentResult_revertsOnUnknownJobId() public {
        _createAndStart();
        bytes32 fakeJob = bytes32(uint256(0xDEAD));
        vm.prank(asyncDelivery);
        vm.expectRevert(abi.encodeWithSelector(IMarket.UnknownMarket.selector, uint256(0)));
        market.onSovereignAgentResult(fakeJob, _investigatorResult());
    }

    // ------ HarnessRules firing in isolation ------

    function test_harness_confidenceFloor_forcesUnresolvable() public {
        uint256 id = _createAndStart();

        string memory verdictJson = MockPrecompiles.buildVerdictJson(
            1,
            5400,
            1,
            "haaland",
            _zeroHashHex(),
            _citations("dossier://stats.x")
        );
        MockPrecompiles.mockJudgeSuccess(vm, bytes(verdictJson));

        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());

        IMarket.Market memory m = market.get(id);
        assertEq(m.verdict.outcome, 2);
    }

    function test_harness_tier3_capsConfidence() public {
        uint256 id = _createAndStart();

        string memory verdictJson = MockPrecompiles.buildVerdictJson(
            1,
            9000,
            3,
            "haaland",
            _zeroHashHex(),
            _citations("dossier://stats.x")
        );
        MockPrecompiles.mockJudgeSuccess(vm, bytes(verdictJson));

        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());

        IMarket.Market memory m = market.get(id);
        assertEq(m.verdict.confidenceBps, 6500);
    }

    // ------ Malformed verdicts — event NOT revert ------

    function test_malformed_parseFailsRoutesToDispute() public {
        uint256 id = _createAndStart();
        MockPrecompiles.mockJudgeSuccess(vm, bytes("not-json"));

        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());

        IMarket.Market memory m = market.get(id);
        assertTrue(m.malformed);
        assertFalse(m.finalized);
    }

    function test_malformed_confidenceOutOfRangeRoutesToDispute() public {
        uint256 id = _createAndStart();

        string memory verdictJson = MockPrecompiles.buildVerdictJson(
            1,
            10001,
            1,
            "haaland",
            _zeroHashHex(),
            _citations("dossier://stats.x")
        );
        MockPrecompiles.mockJudgeSuccess(vm, bytes(verdictJson));

        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());

        IMarket.Market memory m = market.get(id);
        assertTrue(m.malformed);
        assertFalse(m.finalized);
    }

    function test_malformed_drivingTierOutOfRangeRoutesToDispute() public {
        uint256 id = _createAndStart();

        string memory verdictJson = MockPrecompiles.buildVerdictJson(
            1,
            7000,
            4,
            "haaland",
            _zeroHashHex(),
            _citations("dossier://stats.x")
        );
        MockPrecompiles.mockJudgeSuccess(vm, bytes(verdictJson));

        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());

        IMarket.Market memory m = market.get(id);
        assertTrue(m.malformed);
        assertFalse(m.finalized);
    }

    function test_malformed_invalidCitationRoutesToDispute() public {
        uint256 id = _createAndStart();

        string memory verdictJson = MockPrecompiles.buildVerdictJson(
            1,
            7000,
            1,
            "haaland",
            _zeroHashHex(),
            _citations("http://example.com/x")
        );
        MockPrecompiles.mockJudgeSuccess(vm, bytes(verdictJson));

        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());

        IMarket.Market memory m = market.get(id);
        assertTrue(m.malformed);
        assertFalse(m.finalized);
    }

    // ------ ADR-016 — Dossier StorageRef must be content-addressed (IPFS) ------

    function test_malformed_nonIpfsDossierPlatformRoutesToDispute() public {
        uint256 id = _createAndStart();

        // Adversarial: investigator returns an HF dataset path masquerading as a dossier.
        bytes memory adversarialResult = MockPrecompiles.buildInvestigatorResultWithStorageRef(
            "hf",
            "alice/probe-workspace/sessions/dossier.json",
            "irrelevant"
        );

        // Pin to the specific event + offending platform string. Anything firing other than
        // MalformedDossierPlatform with platform="hf" fails the test — incidental breakage
        // (e.g. a generic MalformedVerdict) would not satisfy the assertion.
        vm.expectEmit(true, false, false, true);
        emit IMarket.MalformedDossierPlatform(id, "hf");

        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, adversarialResult);

        IMarket.Market memory m = market.get(id);
        assertTrue(m.malformed, "market must be marked malformed");
        assertFalse(m.finalized, "market must not be finalized");
        assertEq(m.dossierCid, "", "dossierCid must not be persisted from a non-IPFS platform");
    }

    function test_malformed_nonIpfsCidShapeRoutesToDispute() public {
        uint256 id = _createAndStart();

        // Adversarial: investigator claims "ipfs" platform but supplies an HF-shaped path with
        // slashes and no recognisable CID prefix. Catches the case where a tampered investigator
        // says "ipfs" but the path string was substituted from a mutable backend.
        string memory adversarialPath = "alice/probe-workspace/sessions/dossier.json";
        bytes memory adversarialResult = MockPrecompiles.buildInvestigatorResultWithStorageRef(
            "ipfs",
            adversarialPath,
            "irrelevant"
        );

        vm.expectEmit(true, false, false, true);
        emit IMarket.MalformedDossierCid(id, adversarialPath);

        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, adversarialResult);

        IMarket.Market memory m = market.get(id);
        assertTrue(m.malformed, "market must be marked malformed");
        assertFalse(m.finalized, "market must not be finalized");
        assertEq(m.dossierCid, "", "dossierCid must not be persisted from a malformed CID path");
    }

    function test_malformed_unknownSubjectRoutesToDispute() public {
        uint256 id = _createAndStart();

        string memory verdictJson = MockPrecompiles.buildVerdictJson(
            1,
            7000,
            1,
            "ronaldo",
            _zeroHashHex(),
            _citations("dossier://stats.x")
        );
        MockPrecompiles.mockJudgeSuccess(vm, bytes(verdictJson));

        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());

        IMarket.Market memory m = market.get(id);
        assertTrue(m.malformed);
        assertFalse(m.finalized);
    }

    // ------ disputeAttestation ------

    function test_disputeAttestation_flagsAfterFinalize() public {
        uint256 id = _finalizeHappyPath();

        vm.prank(disputer);
        market.disputeAttestation(id, hex"beef");

        assertTrue(market.get(id).disputed);
    }

    function test_disputeAttestation_revertsBeforeDelivery() public {
        uint256 id = _create();
        vm.expectRevert(abi.encodeWithSelector(IMarket.NotResolved.selector, id));
        market.disputeAttestation(id, hex"");
    }

    function test_disputeAttestation_revertsOnDouble() public {
        uint256 id = _finalizeHappyPath();
        market.disputeAttestation(id, hex"");
        vm.expectRevert(abi.encodeWithSelector(IMarket.AlreadyDisputed.selector, id));
        market.disputeAttestation(id, hex"");
    }

    function test_disputeAttestation_worksAfterMalformed() public {
        uint256 id = _createAndStart();
        MockPrecompiles.mockJudgeSuccess(vm, bytes("not-json"));
        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());

        market.disputeAttestation(id, hex"");
        assertTrue(market.get(id).disputed);
    }

    // ------ ADR-018 — Framework is frozen at market creation ------
    //
    // The pre-commitment property: a market's framework (question + framework id + source
    // allowlist + dossier manifest + judge model + agent budgets) is declared at createMarket
    // and cannot mutate through the full investigation+callback+finalize lifecycle. Mutation
    // would let a financially-interested creator rewrite the rulebook after seeing evidence.
    //
    // Two layers, two tests:
    //   1. Market-side: m.init fields stay byte-equal through the full lifecycle.
    //   2. Registry-side: a registered (frameworkId -> uri) binding cannot be overwritten.

    function test_market_initIsFrozenThroughLifecycle() public {
        IMarket.MarketInit memory pre = _params();
        uint256 id = _create();

        // Capture init AT createMarket — the canonical pre-commitment.
        IMarket.MarketInit memory atCreate = market.get(id).init;
        _assertInitEq(atCreate, pre);

        // Move through every state transition that mutates the Market struct: startInvestigation
        // sets investigationJobId/investigationStartedAt; onSovereignAgentResult sets dossierCid,
        // verdict, finalized. None of them should touch m.init.
        vm.warp(resolutionTime + 1);
        MockPrecompiles.mockSovereignAgentSubmit(vm, JOB_ID);
        market.startInvestigation(id);
        _assertInitEq(market.get(id).init, pre);

        string memory verdictJson = MockPrecompiles.buildVerdictJson(
            1,
            7200,
            1,
            "haaland",
            _zeroHashHex(),
            _citations("dossier://stats.x")
        );
        MockPrecompiles.mockJudgeSuccess(vm, bytes(verdictJson));
        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());

        IMarket.Market memory m = market.get(id);
        assertTrue(
            m.finalized,
            "lifecycle prerequisite: market must reach finalized for this assertion to be meaningful"
        );
        _assertInitEq(m.init, pre);
    }

    function test_registry_cannotOverwriteFrameworkIdUri() public {
        bytes32 id = keccak256("adr-018-overwrite-fixture");
        frameworks.register(id, "ipfs://original", hex"");

        vm.expectRevert(abi.encodeWithSelector(IFrameworkRegistry.FrameworkAlreadyRegistered.selector, id));
        frameworks.register(id, "ipfs://tampered", hex"");

        // Confirm the original is intact.
        assertEq(frameworks.get(id).uri, "ipfs://original");
    }

    // --- Helper functions ---

    function _params() internal view returns (IMarket.MarketInit memory params) {
        string[] memory subjects = new string[](1);
        subjects[0] = "haaland";
        string[] memory allowlist = new string[](1);
        allowlist[0] = "https://stats.example/x";

        params = IMarket.MarketInit({
            question: "Is Haaland the most valuable striker in 2024?",
            frameworkId: FRAMEWORK_ID,
            sourceAllowlist: allowlist,
            dossierPathPrefix: DOSSIER_PREFIX,
            dossierSubjects: subjects,
            resolutionTime: resolutionTime,
            cliType: 0,
            model: "zai-org/GLM-4.7-FP8",
            maxTurns: 20,
            maxTokens: 4096,
            callbackGasLimit: 5_000_000,
            investigationTtl: 1000
        });
    }

    function _create() internal returns (uint256 id) {
        vm.prank(creator);
        id = market.createMarket(_params());
    }

    function _createAndStart() internal returns (uint256 id) {
        id = _create();
        vm.warp(resolutionTime + 1);
        MockPrecompiles.mockSovereignAgentSubmit(vm, JOB_ID);
        market.startInvestigation(id);
    }

    function _finalizeHappyPath() internal returns (uint256 id) {
        id = _createAndStart();
        string memory verdictJson = MockPrecompiles.buildVerdictJson(
            1,
            7200,
            1,
            "haaland",
            _zeroHashHex(),
            _citations("dossier://stats.x")
        );
        MockPrecompiles.mockJudgeSuccess(vm, bytes(verdictJson));
        vm.prank(asyncDelivery);
        market.onSovereignAgentResult(JOB_ID, _investigatorResult());
    }

    function _investigatorResult() internal view returns (bytes memory) {
        return MockPrecompiles.buildInvestigatorResult(DOSSIER_CID, executor);
    }

    function _citations(string memory one) internal pure returns (string[] memory c) {
        c = new string[](1);
        c[0] = one;
    }

    function _zeroHashHex() internal pure returns (string memory) {
        return "0x0000000000000000000000000000000000000000000000000000000000000000";
    }

    // Field-by-field equality check for MarketInit. Built explicitly (not via abi.encode) so a
    // future field added to MarketInit forces a compile error here — the test cannot silently
    // miss a new mutable field.
    function _assertInitEq(IMarket.MarketInit memory got, IMarket.MarketInit memory want) internal pure {
        assertEq(got.question, want.question, "question mutated");
        assertEq(got.frameworkId, want.frameworkId, "frameworkId mutated");
        assertEq(got.sourceAllowlist.length, want.sourceAllowlist.length, "sourceAllowlist length mutated");
        for (uint256 i = 0; i < want.sourceAllowlist.length; i++) {
            assertEq(got.sourceAllowlist[i], want.sourceAllowlist[i], "sourceAllowlist entry mutated");
        }
        assertEq(got.dossierPathPrefix, want.dossierPathPrefix, "dossierPathPrefix mutated");
        assertEq(got.dossierSubjects.length, want.dossierSubjects.length, "dossierSubjects length mutated");
        for (uint256 i = 0; i < want.dossierSubjects.length; i++) {
            assertEq(got.dossierSubjects[i], want.dossierSubjects[i], "dossierSubjects entry mutated");
        }
        assertEq(got.resolutionTime, want.resolutionTime, "resolutionTime mutated");
        assertEq(uint256(got.cliType), uint256(want.cliType), "cliType mutated");
        assertEq(got.model, want.model, "model mutated");
        assertEq(uint256(got.maxTurns), uint256(want.maxTurns), "maxTurns mutated");
        assertEq(uint256(got.maxTokens), uint256(want.maxTokens), "maxTokens mutated");
        assertEq(got.callbackGasLimit, want.callbackGasLimit, "callbackGasLimit mutated");
        assertEq(got.investigationTtl, want.investigationTtl, "investigationTtl mutated");
    }
}
