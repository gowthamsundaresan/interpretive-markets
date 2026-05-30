// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMarket} from "../interfaces/IMarket.sol";
import {IFrameworkRegistry} from "../interfaces/IFrameworkRegistry.sol";
import {IJudgeRegistry} from "../interfaces/IJudgeRegistry.sol";
import {ResolutionTypes} from "../libraries/ResolutionTypes.sol";
import {SignatureVerifier} from "../utils/SignatureVerifier.sol";

/// @title Market
/// @notice Singleton registry of interpretive markets and their verdicts. v0 stub: stores
///         immutable market params, accepts judge-signed verdicts, and records disputes.
/// @dev Market trading mechanics (YES/NO pools, settlement) are deferred to v1.
contract Market is IMarket {
    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice The framework registry consulted at market creation
    IFrameworkRegistry public immutable frameworkRegistry;

    /// @notice The judge registry consulted at market creation and resolution
    IJudgeRegistry public immutable judgeRegistry;

    /// @notice Mapping of market id to stored record
    mapping(uint256 => Market) private _markets;

    /// @notice The next market id to be assigned
    uint256 private _nextMarketId;

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Wires the framework and judge registries that markets are validated against
    constructor(IFrameworkRegistry _frameworkRegistry, IJudgeRegistry _judgeRegistry) {
        frameworkRegistry = _frameworkRegistry;
        judgeRegistry = _judgeRegistry;
        _nextMarketId = 1;
    }

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IMarket
    function createMarket(MarketInit calldata params) external returns (uint256 marketId) {
        if (!frameworkRegistry.isRegistered(params.frameworkId)) revert UnknownFramework(params.frameworkId);
        if (judgeRegistry.get(params.judgeImageDigest).registeredAt == 0) {
            revert UnknownJudge(params.judgeImageDigest);
        }
        if (params.resolutionTime <= block.timestamp) revert InvalidResolutionTime();

        marketId = _nextMarketId++;

        Market storage m = _markets[marketId];
        m.init = params;
        m.creator = msg.sender;
        m.createdAt = uint64(block.timestamp);

        emit MarketCreated(marketId, params.frameworkId, params.judgeImageDigest, msg.sender);
    }

    /// @inheritdoc IMarket
    function resolve(
        uint256 marketId,
        ResolutionTypes.Verdict calldata verdict,
        string calldata bundleRef,
        bytes calldata signature
    ) external {
        Market storage m = _markets[marketId];
        if (m.createdAt == 0) revert UnknownMarket(marketId);
        if (block.timestamp < m.init.resolutionTime) revert TooEarly(marketId, m.init.resolutionTime);
        if (m.resolvedAt != 0) revert AlreadyResolved(marketId);

        address signer = SignatureVerifier.recoverVerdictSigner(marketId, verdict, bundleRef, signature);
        if (!judgeRegistry.isAuthorized(m.init.judgeImageDigest, signer)) revert UnauthorizedSigner(signer);

        m.verdict = verdict;
        m.bundleRef = bundleRef;
        m.resolvedAt = uint64(block.timestamp);

        emit VerdictPosted(marketId, signer, bundleRef);
    }

    /// @inheritdoc IMarket
    function disputeVerdict(uint256 marketId, bytes calldata evidence) external {
        Market storage m = _markets[marketId];
        if (m.createdAt == 0) revert UnknownMarket(marketId);
        if (m.resolvedAt == 0) revert NotResolved(marketId);
        if (m.disputed) revert AlreadyDisputed(marketId);

        m.disputed = true;
        emit VerdictDisputed(marketId, msg.sender, evidence);
    }

    /// @inheritdoc IMarket
    function get(uint256 marketId) external view returns (Market memory market) {
        market = _markets[marketId];
    }

    /// @inheritdoc IMarket
    function nextMarketId() external view returns (uint256 nextId) {
        nextId = _nextMarketId;
    }
}
