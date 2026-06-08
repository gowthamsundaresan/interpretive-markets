// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {JSONParserLib} from "solady/utils/JSONParserLib.sol";

import {IMarket} from "../interfaces/IMarket.sol";
import {IFrameworkRegistry} from "../interfaces/IFrameworkRegistry.sol";
import {IRitualSystem} from "../interfaces/IRitualSystem.sol";
import {ResolutionTypes} from "../libraries/ResolutionTypes.sol";
import {HarnessRules} from "../libraries/HarnessRules.sol";
import {DossierManifest} from "../libraries/DossierManifest.sol";

/// @title Market
/// @notice Singleton registry of interpretive markets resolved via Ritual L1 single-callback flow
contract Market is IMarket {
    using JSONParserLib for JSONParserLib.Item;
    using JSONParserLib for string;

    // ------------------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------------------

    /// @notice Rule id emitted when enforceConfidenceFloor flips the outcome to UNRESOLVABLE
    uint8 internal constant RULE_CONFIDENCE_FLOOR = 1;

    /// @notice Rule id emitted when capByDrivingTier reduces the confidence
    uint8 internal constant RULE_TIER_CAP = 2;

    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice The framework registry consulted at market creation
    IFrameworkRegistry public immutable frameworkRegistry;

    /// @notice Typed wrapper over Ritual L1 system primitives (precompiles + AsyncDelivery)
    IRitualSystem public immutable ritualSystem;

    /// @notice Cached AsyncDelivery address — the trust boundary for onSovereignAgentResult
    address public immutable asyncDelivery;

    mapping(uint256 => Market) private _markets;

    /// @notice Audit trail: jobId → marketId. Populated when the callback fires (jobId is unknown
    ///         at submission time — see SovereignAgent flow), not at submission.
    mapping(bytes32 => uint256) private _jobToMarket;

    /// @notice The market currently awaiting Phase-2 delivery, or 0 if none. Mirrors the chain's
    ///         per-sender single-pending invariant (`AsyncJobTracker.hasPendingJobForSender`) so
    ///         the callback can resolve marketId without needing jobId at submission.
    uint256 private _pendingInvestigationMarket;

    uint256 private _nextMarketId;

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Wires the framework registry and Ritual system primitives
    constructor(IFrameworkRegistry _frameworkRegistry, IRitualSystem _ritualSystem) {
        frameworkRegistry = _frameworkRegistry;
        ritualSystem = _ritualSystem;
        asyncDelivery = _ritualSystem.asyncDelivery();
        _nextMarketId = 1;
    }

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IMarket
    function createMarket(MarketInit calldata params) external returns (uint256 marketId) {
        if (!frameworkRegistry.isRegistered(params.frameworkId)) revert UnknownFramework(params.frameworkId);
        if (params.resolutionTime <= block.timestamp) revert InvalidResolutionTime();

        marketId = _nextMarketId++;

        Market storage m = _markets[marketId];
        m.init = params;
        m.creator = msg.sender;
        m.createdAt = uint64(block.timestamp);

        emit MarketCreated(marketId, params.frameworkId, msg.sender);
    }

    /// @inheritdoc IMarket
    function startInvestigation(uint256 marketId, SovereignSubmissionParams calldata params) external {
        Market storage m = _markets[marketId];
        if (m.createdAt == 0) revert UnknownMarket(marketId);
        if (block.timestamp < m.init.resolutionTime) revert TooEarly(marketId, m.init.resolutionTime);
        if (m.investigationStartedAt != 0) revert InvestigationAlreadyStarted(marketId);
        if (_pendingInvestigationMarket != 0) revert AnotherInvestigationPending(_pendingInvestigationMarket);

        _pendingInvestigationMarket = marketId;

        IRitualSystem.InvestigationRequest memory request = _buildInvestigationRequest(m, params);
        ritualSystem.investigate(request);

        m.investigationStartedAt = uint64(block.timestamp);

        bytes32 requestBinding = _requestBindingForInvestigation(marketId, m);
        emit InvestigationStarted(marketId, requestBinding);
    }

    /// @inheritdoc IMarket
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external {
        if (msg.sender != asyncDelivery) revert Unauthorized(msg.sender);

        uint256 marketId = _pendingInvestigationMarket;
        if (marketId == 0) revert NoPendingInvestigation();
        _pendingInvestigationMarket = 0;

        Market storage m = _markets[marketId];
        if (m.investigationStartedAt == 0) revert InvestigationNotStarted(marketId);
        if (m.finalized) revert AlreadyFinalized(marketId);

        m.investigationJobId = jobId;
        _jobToMarket[jobId] = marketId;

        (
            string memory dossierPlatform,
            string memory dossierCid,
            string memory messagesJson
        ) = _decodeInvestigatorResult(result);

        // Reject non-IPFS platforms at point of detection — content-addressed bytes are required
        // for the watcher's recompute-and-compare audit; trusting downstream parsing to choke
        // would couple the security check to a side effect two steps away.
        if (!DossierManifest.validateIpfsPlatform(dossierPlatform)) {
            m.malformed = true;
            emit MalformedDossierPlatform(marketId, dossierPlatform);
            return;
        }
        if (!DossierManifest.validateIpfsCidShape(dossierCid)) {
            m.malformed = true;
            emit MalformedDossierCid(marketId, dossierCid);
            return;
        }

        m.dossierCid = dossierCid;
        emit InvestigationDelivered(marketId, jobId, dossierCid);

        bytes32 promptHash = keccak256(bytes(messagesJson));
        emit JudgmentStarted(marketId, promptHash);

        bytes memory completionData = ritualSystem.judge(_buildJudgeRequest(messagesJson, m.init.model, marketId));
        bytes32 verdictHash = keccak256(completionData);
        emit JudgmentDelivered(marketId, verdictHash);

        // Executor identity is resolved off-chain by the watcher (resolution-tx receipt +
        // TEEServiceRegistry workloadId match). We pass address(0) on-chain.
        _applyVerdict(marketId, m, completionData, dossierCid, address(0), verdictHash);
    }

    /// @inheritdoc IMarket
    function disputeAttestation(uint256 marketId, bytes calldata evidence) external {
        Market storage m = _markets[marketId];
        if (m.createdAt == 0) revert UnknownMarket(marketId);
        if (!m.finalized && !m.malformed) revert NotResolved(marketId);
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

    /// @inheritdoc IMarket
    function pendingInvestigationMarket() external view returns (uint256 marketId) {
        marketId = _pendingInvestigationMarket;
    }

    /// @inheritdoc IMarket
    function marketIdForJob(bytes32 jobId) external view returns (uint256 marketId) {
        marketId = _jobToMarket[jobId];
    }

    // ------------------------------------------------------------------------------
    // Verdict parsing entrypoint (external for try/catch)
    // ------------------------------------------------------------------------------

    /// @notice Parse a completionData JSON payload into a ParsedVerdict
    /// @dev External so onSovereignAgentResult can wrap in try/catch; reverts on any structural
    ///      failure and the caller routes to MalformedVerdict.
    function parseVerdictPayload(
        bytes calldata completionData
    ) external pure returns (ResolutionTypes.ParsedVerdict memory parsed) {
        string memory text = string(completionData);
        JSONParserLib.Item memory root = text.parse();

        if (!root.isObject()) revert JSONParserLib.ParsingFailed();

        parsed.outcome = uint8(JSONParserLib.parseUint(root.at('"outcome"').value()));
        parsed.confidenceBps = uint16(JSONParserLib.parseUint(root.at('"confidence_bps"').value()));
        parsed.drivingTier = uint8(JSONParserLib.parseUint(root.at('"driving_tier"').value()));
        parsed.subjectRef = JSONParserLib.decodeString(root.at('"subject_ref"').value());

        string memory rationaleHashHex = JSONParserLib.decodeString(root.at('"rationale_hash"').value());
        parsed.rationaleHash = _parseBytes32Hex(rationaleHashHex);

        JSONParserLib.Item memory citationsItem = root.at('"citations"');
        if (!citationsItem.isArray()) revert JSONParserLib.ParsingFailed();
        JSONParserLib.Item[] memory items = citationsItem.children();
        string[] memory citations = new string[](items.length);
        for (uint256 i = 0; i < items.length; i++) {
            citations[i] = JSONParserLib.decodeString(items[i].value());
        }
        parsed.citations = citations;
    }

    // ------------------------------------------------------------------------------
    // Helper functions
    // ------------------------------------------------------------------------------

    /// @dev Apply harness rules to the parsed verdict and either finalize or mark malformed
    function _applyVerdict(
        uint256 marketId,
        Market storage m,
        bytes memory completionData,
        string memory dossierCid,
        address executor,
        bytes32 verdictHash
    ) internal {
        ResolutionTypes.ParsedVerdict memory parsed;
        try this.parseVerdictPayload(completionData) returns (ResolutionTypes.ParsedVerdict memory p) {
            parsed = p;
        } catch {
            m.malformed = true;
            emit MalformedVerdict(marketId, "parse-failed");
            return;
        }

        if (!HarnessRules.isWellFormed(parsed)) {
            m.malformed = true;
            emit MalformedVerdict(marketId, "field-out-of-range");
            return;
        }

        ResolutionTypes.DossierManifest memory manifest = ResolutionTypes.DossierManifest({
            pathPrefix: m.init.dossierPathPrefix,
            subjects: m.init.dossierSubjects
        });

        if (!HarnessRules.validateCitations(parsed.citations, manifest)) {
            m.malformed = true;
            emit MalformedVerdict(marketId, "invalid-citation");
            return;
        }
        if (!HarnessRules.validateSubject(parsed.subjectRef, manifest)) {
            m.malformed = true;
            emit MalformedVerdict(marketId, "invalid-subject");
            return;
        }

        uint8 outcome = HarnessRules.enforceConfidenceFloor(parsed.outcome, parsed.confidenceBps);
        if (outcome != parsed.outcome) emit HarnessRuleFired(marketId, RULE_CONFIDENCE_FLOOR);

        uint16 confidence = HarnessRules.capByDrivingTier(parsed.confidenceBps, parsed.drivingTier);
        if (confidence != parsed.confidenceBps) emit HarnessRuleFired(marketId, RULE_TIER_CAP);

        m.verdict = ResolutionTypes.Verdict({
            outcome: outcome,
            confidenceBps: confidence,
            drivingTier: parsed.drivingTier,
            subjectRef: parsed.subjectRef,
            rationaleHash: parsed.rationaleHash,
            verdictHash: verdictHash,
            dossierCid: dossierCid,
            executor: executor,
            attestedAtBlock: uint64(block.number)
        });
        m.finalized = true;
        emit VerdictFinalized(marketId, outcome, confidence);
    }

    /// @dev Build the SovereignAgent investigation request from market state + operator submission params
    function _buildInvestigationRequest(
        Market storage m,
        SovereignSubmissionParams calldata params
    ) internal view returns (IRitualSystem.InvestigationRequest memory request) {
        IRitualSystem.StorageRef[] memory emptySkills = new IRitualSystem.StorageRef[](0);
        IRitualSystem.StorageRef memory systemPrompt = IRitualSystem.StorageRef({
            platform: "ipfs",
            path: _frameworkUri(m.init.frameworkId),
            keyRef: ""
        });

        request = IRitualSystem.InvestigationRequest({
            cliType: m.init.cliType,
            prompt: m.init.question,
            systemPrompt: systemPrompt,
            skills: emptySkills,
            model: m.init.model,
            tools: m.init.sourceAllowlist,
            maxTurns: m.init.maxTurns,
            maxTokens: m.init.maxTokens,
            callbackSelector: this.onSovereignAgentResult.selector,
            callbackGasLimit: m.init.callbackGasLimit,
            ttl: m.init.investigationTtl,
            executor: params.executor,
            encryptedSecrets: params.encryptedSecrets,
            userPublicKey: params.userPublicKey,
            pollIntervalBlocks: params.pollIntervalBlocks,
            maxPollBlock: params.maxPollBlock,
            maxFeePerGas: params.maxFeePerGas,
            maxPriorityFeePerGas: params.maxPriorityFeePerGas
        });
    }

    /// @dev Build the LLM Inference judge request
    function _buildJudgeRequest(
        string memory messagesJson,
        string memory model,
        uint256 marketId
    ) internal pure returns (IRitualSystem.JudgeRequest memory request) {
        request = IRitualSystem.JudgeRequest({
            messagesJson: messagesJson,
            model: model,
            maxCompletionTokens: int256(2000),
            reasoningEffort: "medium",
            responseFormatData: bytes(""),
            seed: int256(marketId),
            temperature: int256(0),
            topP: int256(1000)
        });
    }

    /// @dev Canonical hash of the investigation inputs; watcher recomputes this off-chain
    function _requestBindingForInvestigation(uint256 marketId, Market storage m) internal view returns (bytes32) {
        return keccak256(abi.encode(marketId, m.init.frameworkId, m.init.question, m.init.sourceAllowlist));
    }

    /// @dev Decode the Phase-2 result using the canonical 6-field shape:
    ///      `(bool success, string error, string text, StorageRef ref1, StorageRef ref2, StorageRef[] artifacts)`.
    ///      The investigator pre-assembles the judge messagesJson into `text` and pins the dossier
    ///      StorageRef in `artifacts[0]`. Caller MUST validate `dossierPlatform == "ipfs"` and
    ///      `validateIpfsCidShape(dossierCid)` — non-content-addressed paths defeat the audit trail.
    function _decodeInvestigatorResult(
        bytes calldata result
    ) internal pure returns (string memory dossierPlatform, string memory dossierCid, string memory messagesJson) {
        (
            bool success,
            ,
            string memory text,
            IRitualSystem.StorageRef memory ref1,
            IRitualSystem.StorageRef memory ref2,
            IRitualSystem.StorageRef[] memory artifacts
        ) = abi.decode(
                result,
                (bool, string, string, IRitualSystem.StorageRef, IRitualSystem.StorageRef, IRitualSystem.StorageRef[])
            );
        // Phase-2 envelope fields the watcher records off-chain from the raw bytes; on-chain we
        // only need the dossier StorageRef + assembled judge prompt.
        success;
        ref1;
        ref2;
        messagesJson = text;
        if (artifacts.length > 0) {
            dossierPlatform = artifacts[0].platform;
            dossierCid = artifacts[0].path;
        }
    }

    /// @dev Lookup the framework's content URI from the registry
    function _frameworkUri(bytes32 frameworkId) internal view returns (string memory) {
        return frameworkRegistry.get(frameworkId).uri;
    }

    /// @dev Parse a "0x"-prefixed 64-hex-char string into bytes32. Reverts on invalid input.
    function _parseBytes32Hex(string memory s) internal pure returns (bytes32 result) {
        bytes memory b = bytes(s);
        if (b.length != 66 || b[0] != "0" || b[1] != "x") revert JSONParserLib.ParsingFailed();

        uint256 acc;
        for (uint256 i = 2; i < 66; i++) {
            uint8 c = uint8(b[i]);
            uint8 nibble;
            if (c >= 0x30 && c <= 0x39) nibble = c - 0x30;
            else if (c >= 0x61 && c <= 0x66) nibble = c - 0x61 + 10;
            else if (c >= 0x41 && c <= 0x46) nibble = c - 0x41 + 10;
            else revert JSONParserLib.ParsingFailed();
            acc = (acc << 4) | nibble;
        }
        result = bytes32(acc);
    }
}
