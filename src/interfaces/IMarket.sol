// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ResolutionTypes} from "../libraries/ResolutionTypes.sol";

/// @title IMarket Interface
/// @notice Singleton registry of interpretive markets on Ritual L1. Each market pins a
///         framework + source allowlist + dossier manifest at creation; resolution flows through
///         a single AsyncDelivery callback (`onSovereignAgentResult`) that decodes the dossier,
///         calls the 0x0802 LLM precompile SPC inline, applies harness rules, and finalizes.
///         v0 stub: no trading mechanics.
interface IMarket {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Parameters for creating a new market
    /// @param question Human-readable question text
    /// @param frameworkId Registered framework id (sha256 of tarball)
    /// @param sourceAllowlist URLs the investigator is permitted to fetch
    /// @param dossierPathPrefix Required prefix for every citation (e.g. "dossier://")
    /// @param dossierSubjects Allowed subject_ref identifiers
    /// @param resolutionTime Earliest timestamp at which startInvestigation may be called
    /// @param cliType Sovereign Agent harness selector (0=ClaudeCode, 5=Crush, 6=ZeroClaw)
    /// @param model LLM model identifier for the judge (e.g. "zai-org/GLM-4.7-FP8")
    /// @param maxTurns Cap on investigator agentic turns
    /// @param maxTokens Cap on investigator output tokens
    /// @param callbackGasLimit Gas budget for the resolution callback (covers SPC + finalize)
    /// @param investigationTtl Phase-1 TTL in blocks for the investigation job
    struct MarketInit {
        string question;
        bytes32 frameworkId;
        string[] sourceAllowlist;
        string dossierPathPrefix;
        string[] dossierSubjects;
        uint64 resolutionTime;
        uint16 cliType;
        string model;
        uint16 maxTurns;
        uint32 maxTokens;
        uint256 callbackGasLimit;
        uint256 investigationTtl;
    }

    /// @notice Stored record for a market
    /// @param init Immutable market parameters set at creation
    /// @param creator Address that created the market
    /// @param createdAt Block timestamp at creation
    /// @param investigationJobId AsyncJobTracker job id; bytes32(0) until startInvestigation
    /// @param investigationStartedAt Block timestamp at startInvestigation; 0 until then
    /// @param dossierCid IPFS CID of the dossier produced by the investigator
    /// @param verdict Verdict struct populated on resolution callback
    /// @param finalized True once a well-formed verdict has been applied
    /// @param malformed True when the LLM emitted a malformed payload (challengeable, not finalized)
    /// @param disputed True when a watcher has filed a consistency-audit dispute
    struct Market {
        MarketInit init;
        address creator;
        uint64 createdAt;
        bytes32 investigationJobId;
        uint64 investigationStartedAt;
        string dossierCid;
        ResolutionTypes.Verdict verdict;
        bool finalized;
        bool malformed;
        bool disputed;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when a market is created
    /// @param marketId Unique identifier for the market
    /// @param frameworkId Framework id used to evaluate
    /// @param creator Address that created the market
    event MarketCreated(uint256 indexed marketId, bytes32 indexed frameworkId, address creator);

    /// @notice Emitted when startInvestigation submits the 0x080C call
    /// @dev jobId is not known at submission — it arrives in the Phase-2 callback. Use
    ///      `InvestigationDelivered` to learn the jobId post-hoc.
    /// @param marketId The market id
    /// @param requestBinding keccak256 of the canonical investigation inputs
    event InvestigationStarted(uint256 indexed marketId, bytes32 requestBinding);

    /// @notice Emitted when AsyncDelivery hands back the investigator's result
    /// @param marketId The market id
    /// @param jobId The AsyncJobTracker job id
    /// @param dossierCid IPFS CID of the produced dossier
    event InvestigationDelivered(uint256 indexed marketId, bytes32 indexed jobId, string dossierCid);

    /// @notice Emitted before the inline 0x0802 SPC judge call
    /// @param marketId The market id
    /// @param promptHash keccak256 of the assembled judge prompt
    event JudgmentStarted(uint256 indexed marketId, bytes32 promptHash);

    /// @notice Emitted after the 0x0802 SPC returns the completionData
    /// @param marketId The market id
    /// @param verdictHash keccak256 over the canonical verdict serialization
    event JudgmentDelivered(uint256 indexed marketId, bytes32 verdictHash);

    /// @notice Emitted when a HarnessRule mutates an LLM-emitted field
    /// @param marketId The market id
    /// @param ruleId Identifier for the rule that fired (1=confidence floor, 2=tier-3 cap, etc.)
    event HarnessRuleFired(uint256 indexed marketId, uint8 ruleId);

    /// @notice Emitted when the LLM emitted a malformed payload (range/type/citation/subject violation)
    /// @param marketId The market id
    /// @param reason Human-readable reason tag (e.g. "parse-failed", "confidence-out-of-range")
    event MalformedVerdict(uint256 indexed marketId, string reason);

    /// @notice Emitted when the investigator returned a dossier StorageRef with a non-IPFS platform
    /// @dev Defends against an executor swapping a mutable HF dossier post-callback.
    /// @param marketId The market id
    /// @param offendingPlatform The platform string the investigator returned (e.g. "hf", "gcs")
    event MalformedDossierPlatform(uint256 indexed marketId, string offendingPlatform);

    /// @notice Emitted when the investigator returned a dossier StorageRef whose path is not a valid IPFS CID
    /// @dev CIDv1 (bafy/bafk/bafz) and CIDv0 (Qm) are accepted; everything else is rejected.
    /// @param marketId The market id
    /// @param offendingCid The path string the investigator returned in artifacts[0].path
    event MalformedDossierCid(uint256 indexed marketId, string offendingCid);

    /// @notice Emitted when a well-formed verdict has been applied and the market is resolved
    /// @param marketId The market id
    /// @param outcome The enforced outcome code
    /// @param confidenceBps The enforced confidence in basis points
    event VerdictFinalized(uint256 indexed marketId, uint8 outcome, uint16 confidenceBps);

    /// @notice Emitted when a watcher files a consistency-audit dispute
    /// @param marketId The market id
    /// @param disputer The address that filed the dispute
    /// @param evidence Opaque evidence blob describing the inconsistency
    event VerdictDisputed(uint256 indexed marketId, address indexed disputer, bytes evidence);

    // ============================================================================
    // ERRORS
    // ============================================================================

    /// @notice Reverts when an unknown framework id is referenced at market creation
    error UnknownFramework(bytes32 frameworkId);

    /// @notice Reverts when resolutionTime is not in the future at creation
    error InvalidResolutionTime();

    /// @notice Reverts when interacting with a non-existent market
    error UnknownMarket(uint256 marketId);

    /// @notice Reverts when startInvestigation is called before resolutionTime
    error TooEarly(uint256 marketId, uint64 resolutionTime);

    /// @notice Reverts when startInvestigation is called twice for the same market
    error InvestigationAlreadyStarted(uint256 marketId);

    /// @notice Reverts when the resolution callback fires for a market that has not started investigation
    error InvestigationNotStarted(uint256 marketId);

    /// @notice Reverts when the resolution callback fires after the market is already finalized
    error AlreadyFinalized(uint256 marketId);

    /// @notice Reverts when startInvestigation is called while another market's investigation is in flight
    /// @dev Mirrors the chain's per-sender single-pending-job invariant on
    ///      `AsyncJobTracker.hasPendingJobForSender(address(this))`.
    error AnotherInvestigationPending(uint256 pendingMarketId);

    /// @notice Reverts when AsyncDelivery delivers a callback while no investigation is pending
    error NoPendingInvestigation();

    /// @notice Reverts when a non-AsyncDelivery address invokes onSovereignAgentResult
    error Unauthorized(address caller);

    /// @notice Reverts when a dispute is filed against a market that has not been delivered
    error NotResolved(uint256 marketId);

    /// @notice Reverts when a dispute is filed twice for the same market
    error AlreadyDisputed(uint256 marketId);

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Create a new market with immutable parameters
    /// @param params The market creation parameters
    /// @return marketId The id assigned to the new market
    function createMarket(MarketInit calldata params) external returns (uint256 marketId);

    /// @notice Operator-supplied parameters for the Phase-1 submission
    /// @dev See `IRitualSystem.InvestigationRequest` for the empirical node-side constraints. The
    ///      operator picks `executor` from `TEEServiceRegistry.getServicesByCapability(0, true)`,
    ///      builds `encryptedSecrets` off-chain (ECIES against the executor's pubkey, MUST include
    ///      `LLM_PROVIDER` in the encrypted JSON), and picks gas/poll parameters per chain conditions.
    /// @param executor TEE address from the registry (NOT address(0))
    /// @param encryptedSecrets ECIES-encrypted secrets JSON (must include `LLM_PROVIDER`)
    /// @param userPublicKey 65-byte uncompressed pubkey for encrypted result (empty = plaintext)
    /// @param pollIntervalBlocks Phase-2 polling cadence (5 is canonical)
    /// @param maxPollBlock Phase-2 deadline RELATIVE offset (≤ 70000)
    /// @param maxFeePerGas Delivery callback fee (≥ 1 gwei)
    /// @param maxPriorityFeePerGas Delivery callback priority fee (≥ 0.1 gwei)
    struct SovereignSubmissionParams {
        address executor;
        bytes encryptedSecrets;
        bytes userPublicKey;
        uint64 pollIntervalBlocks;
        uint64 maxPollBlock;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
    }

    /// @notice Submit the investigation job to the Sovereign Agent precompile (0x080C)
    /// @dev Anyone may call after resolutionTime. The operator MUST off-chain: (1) pick an executor
    ///      from `TEEServiceRegistry.getServicesByCapability(0, true)`, (2) ECIES-encrypt the secrets
    ///      JSON (including the mandatory `LLM_PROVIDER` field) against the executor's pubkey using
    ///      `symmetric_nonce_length=12`, and (3) deposit ≥ 0.124 RIT in `RitualWallet` with a lock
    ///      extending past `currentBlock + ttl`. Only one investigation may be in flight at a time
    ///      across all markets.
    /// @param marketId The market id
    /// @param params Operator-supplied submission parameters
    function startInvestigation(uint256 marketId, SovereignSubmissionParams calldata params) external;

    /// @notice AsyncDelivery callback handler — the single resolution entrypoint
    /// @dev Reverts if msg.sender != AsyncDelivery. Runs decode → SPC judge → harness → finalize
    ///      atomically. Malformed payloads route to the dispute path via MalformedVerdict event.
    /// @param jobId The AsyncJobTracker job id this callback delivers
    /// @param result Phase-2 bytes payload from the Sovereign Agent precompile
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external;

    /// @notice File a consistency-audit dispute against a delivered verdict
    /// @param marketId The market id
    /// @param evidence Opaque evidence blob (e.g. recomputed request-binding diff)
    function disputeAttestation(uint256 marketId, bytes calldata evidence) external;

    /// @notice Fetch the full market record for a given id
    /// @param marketId The market id
    /// @return market The stored market record
    function get(uint256 marketId) external view returns (Market memory market);

    /// @notice The next market id that will be assigned by createMarket
    /// @return nextId The next market id
    function nextMarketId() external view returns (uint256 nextId);

    /// @notice The market id currently awaiting Phase-2 callback delivery, or 0 if none
    /// @dev At most one investigation can be in flight at a time. Enforced at the contract layer
    ///      (this view returns non-zero while in flight) AND at the protocol layer
    ///      (`AsyncJobTracker.hasPendingJobForSender(address(this))`).
    /// @return marketId The market awaiting callback; 0 when none
    function pendingInvestigationMarket() external view returns (uint256 marketId);

    /// @notice Lookup the market id associated with an AsyncJobTracker jobId
    /// @dev Populated lazily — jobId is learned at callback time, not at submission.
    /// @param jobId The AsyncJobTracker job id
    /// @return marketId The corresponding market id; 0 when not found
    function marketIdForJob(bytes32 jobId) external view returns (uint256 marketId);
}
