// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {FrameworkRegistry} from "../src/core/FrameworkRegistry.sol";
import {JudgeRegistry} from "../src/core/JudgeRegistry.sol";
import {Market} from "../src/core/Market.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";
import {ResolutionTypes} from "../src/libraries/ResolutionTypes.sol";
import {MockJudge} from "./helpers/MockJudge.sol";

contract MarketTest is Test {
    // --- Types ---

    FrameworkRegistry internal frameworks;
    JudgeRegistry internal judges;
    Market internal market;

    address internal owner;
    address internal creator;
    address internal disputer;

    uint256 internal judgeKey = 0xA11CE;
    address internal judgeSigner;

    bytes32 internal constant FRAMEWORK_ID = keccak256("pedri-framework-v1");
    bytes32 internal constant JUDGE_DIGEST = keccak256("judge-image-v0");
    bytes32 internal constant MODEL_ID = keccak256("gpt-oss-120b");
    bytes32 internal constant PROMPT_HASH = keccak256("prompt-template-v1");

    uint64 internal resolutionTime;

    // --- Core functions ---

    function setUp() public {
        owner = makeAddr("owner");
        creator = makeAddr("creator");
        disputer = makeAddr("disputer");
        judgeSigner = vm.addr(judgeKey);

        frameworks = new FrameworkRegistry();
        judges = new JudgeRegistry(owner);
        market = new Market(frameworks, judges);

        frameworks.register(FRAMEWORK_ID, "ipfs://cid", hex"");

        vm.prank(owner);
        judges.register(JUDGE_DIGEST, judgeSigner);

        resolutionTime = uint64(block.timestamp + 1 days);
    }

    function test_createMarket_storesRecord() public {
        uint256 id = _create();

        IMarket.Market memory m = market.get(id);
        assertEq(m.init.frameworkId, FRAMEWORK_ID);
        assertEq(m.init.judgeImageDigest, JUDGE_DIGEST);
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

    function test_createMarket_revertsOnUnknownJudge() public {
        IMarket.MarketInit memory params = _params();
        params.judgeImageDigest = keccak256("nope");
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IMarket.UnknownJudge.selector, params.judgeImageDigest));
        market.createMarket(params);
    }

    function test_createMarket_revertsOnPastResolutionTime() public {
        IMarket.MarketInit memory params = _params();
        params.resolutionTime = uint64(block.timestamp);
        vm.prank(creator);
        vm.expectRevert(IMarket.InvalidResolutionTime.selector);
        market.createMarket(params);
    }

    function test_resolve_storesVerdict() public {
        uint256 id = _create();
        vm.warp(resolutionTime + 1);

        ResolutionTypes.Verdict memory v = _verdict();
        string memory bundleRef = "ipfs://bundle";
        bytes memory sig = MockJudge.signVerdict(vm, judgeKey, id, v, bundleRef);

        market.resolve(id, v, bundleRef, sig);

        IMarket.Market memory m = market.get(id);
        assertEq(m.verdict.outcome, v.outcome);
        assertEq(m.verdict.confidence, v.confidence);
        assertEq(m.verdict.verdictHash, v.verdictHash);
        assertEq(m.bundleRef, bundleRef);
        assertEq(m.resolvedAt, uint64(block.timestamp));
    }

    function test_resolve_revertsBeforeResolutionTime() public {
        uint256 id = _create();
        ResolutionTypes.Verdict memory v = _verdict();
        string memory bundleRef = "ipfs://bundle";
        bytes memory sig = MockJudge.signVerdict(vm, judgeKey, id, v, bundleRef);

        vm.expectRevert(abi.encodeWithSelector(IMarket.TooEarly.selector, id, resolutionTime));
        market.resolve(id, v, bundleRef, sig);
    }

    function test_resolve_revertsOnDoubleResolve() public {
        uint256 id = _create();
        vm.warp(resolutionTime + 1);
        ResolutionTypes.Verdict memory v = _verdict();
        string memory bundleRef = "ipfs://bundle";
        bytes memory sig = MockJudge.signVerdict(vm, judgeKey, id, v, bundleRef);

        market.resolve(id, v, bundleRef, sig);
        vm.expectRevert(abi.encodeWithSelector(IMarket.AlreadyResolved.selector, id));
        market.resolve(id, v, bundleRef, sig);
    }

    function test_resolve_revertsOnUnauthorizedSigner() public {
        uint256 id = _create();
        vm.warp(resolutionTime + 1);

        uint256 wrongKey = 0xBADD;
        ResolutionTypes.Verdict memory v = _verdict();
        string memory bundleRef = "ipfs://bundle";
        bytes memory sig = MockJudge.signVerdict(vm, wrongKey, id, v, bundleRef);

        vm.expectRevert(abi.encodeWithSelector(IMarket.UnauthorizedSigner.selector, vm.addr(wrongKey)));
        market.resolve(id, v, bundleRef, sig);
    }

    function test_resolve_revertsWhenJudgeDisabled() public {
        uint256 id = _create();
        vm.warp(resolutionTime + 1);

        vm.prank(owner);
        judges.setEnabled(JUDGE_DIGEST, false);

        ResolutionTypes.Verdict memory v = _verdict();
        string memory bundleRef = "ipfs://bundle";
        bytes memory sig = MockJudge.signVerdict(vm, judgeKey, id, v, bundleRef);

        vm.expectRevert(abi.encodeWithSelector(IMarket.UnauthorizedSigner.selector, judgeSigner));
        market.resolve(id, v, bundleRef, sig);
    }

    function test_resolve_revertsOnUnknownMarket() public {
        ResolutionTypes.Verdict memory v = _verdict();
        bytes memory sig = MockJudge.signVerdict(vm, judgeKey, 999, v, "ipfs://x");
        vm.expectRevert(abi.encodeWithSelector(IMarket.UnknownMarket.selector, uint256(999)));
        market.resolve(999, v, "ipfs://x", sig);
    }

    function test_disputeVerdict_flagsDisputed() public {
        uint256 id = _create();
        vm.warp(resolutionTime + 1);
        ResolutionTypes.Verdict memory v = _verdict();
        string memory bundleRef = "ipfs://bundle";
        bytes memory sig = MockJudge.signVerdict(vm, judgeKey, id, v, bundleRef);
        market.resolve(id, v, bundleRef, sig);

        vm.prank(disputer);
        vm.expectEmit(true, true, false, true);
        emit IMarket.VerdictDisputed(id, disputer, hex"beef");
        market.disputeVerdict(id, hex"beef");

        assertTrue(market.get(id).disputed);
    }

    function test_disputeVerdict_revertsOnUnresolved() public {
        uint256 id = _create();
        vm.expectRevert(abi.encodeWithSelector(IMarket.NotResolved.selector, id));
        market.disputeVerdict(id, hex"");
    }

    function test_disputeVerdict_revertsOnDoubleDispute() public {
        uint256 id = _create();
        vm.warp(resolutionTime + 1);
        ResolutionTypes.Verdict memory v = _verdict();
        string memory bundleRef = "ipfs://bundle";
        bytes memory sig = MockJudge.signVerdict(vm, judgeKey, id, v, bundleRef);
        market.resolve(id, v, bundleRef, sig);
        market.disputeVerdict(id, hex"");

        vm.expectRevert(abi.encodeWithSelector(IMarket.AlreadyDisputed.selector, id));
        market.disputeVerdict(id, hex"");
    }

    // --- Helper functions ---

    function _params() internal view returns (IMarket.MarketInit memory) {
        return
            IMarket.MarketInit({
                question: "Is Pedri Barcelona's most valuable player?",
                frameworkId: FRAMEWORK_ID,
                dataSourceSpec: hex"1234",
                modelId: MODEL_ID,
                promptTemplateHash: PROMPT_HASH,
                resolutionTime: resolutionTime,
                judgeImageDigest: JUDGE_DIGEST
            });
    }

    function _create() internal returns (uint256 id) {
        vm.prank(creator);
        id = market.createMarket(_params());
    }

    function _verdict() internal pure returns (ResolutionTypes.Verdict memory) {
        return ResolutionTypes.Verdict({outcome: 1, confidence: 0.85e18, verdictHash: keccak256("verdict-payload")});
    }
}
