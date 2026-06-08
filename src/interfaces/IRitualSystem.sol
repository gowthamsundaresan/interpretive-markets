// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IRitualSystem Interface
/// @notice Typed wrappers over Ritual L1 system primitives used by Market.sol
/// @dev Addresses captured from docs.ritualfoundation.org (see docs/ARCHITECTURE.md §3).
///      Investigator runs against `0x080C` Sovereign Agent (two-phase async, callback delivery).
///      Judge runs against `0x0802` LLM Inference (Short Async / SPC, result returned inline).
interface IRitualSystem {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Off-chain content reference used by Ritual precompiles
    /// @param platform Storage backend identifier (e.g. "ipfs", "huggingface", "gcs", "pinata")
    /// @param path Locator within the platform (e.g. CID, blob name, key)
    /// @param keyRef Optional decryption key reference; empty when not encrypted
    struct StorageRef {
        string platform;
        string path;
        string keyRef;
    }

    /// @notice Full `0x080C` SovereignAgentParams as Market.sol composes them
    /// @dev Empirically verified against `ritual-foundation/ritual-dapp-skills/skills/ritual-dapp-agents/SKILL.md`
    ///      and a live testnet submission that successfully landed at AsyncJobTracker. Fields fall into
    ///      three groups: (a) market-state fields (`cliType`, `prompt`, `systemPrompt`, `skills`, `model`,
    ///      `tools`, `maxTurns`, `maxTokens`, `callbackSelector`, `callbackGasLimit`, `ttl`) come from
    ///      `MarketInit` + Market.sol; (b) operator-supplied submission fields (`executor`,
    ///      `encryptedSecrets`, `userPublicKey`, `pollIntervalBlocks`, `maxPollBlock`, `maxFeePerGas`,
    ///      `maxPriorityFeePerGas`) come from the off-chain operator script; (c) protocol-fixed fields
    ///      (`taskIdMarker`, `convoHistory`, `output`, `rpcUrls`) are defaulted inside RitualSystem.
    ///
    /// @param cliType Harness selector — MUST be 0 (Claude Code), 5 (Crush), or 6 (ZeroClaw); 1-4 rejected
    /// @param prompt Investigation task prompt
    /// @param systemPrompt StorageRef pointing at investigator.md
    /// @param skills StorageRefs pointing at dossier schema and other skill manifests
    /// @param model LLM model identifier — MUST be a full provider-routable id like `claude-sonnet-4-5-20250929`
    /// @param tools Allowlist of tool names exposed to the harness
    /// @param maxTurns Cap on agentic reasoning turns
    /// @param maxTokens Cap on output tokens
    /// @param callbackSelector Function selector on Market that receives the delivery (4 bytes)
    /// @param callbackGasLimit Gas budget for the callback transaction (must cover SPC + finalize)
    /// @param ttl Phase-1 time-to-live in blocks — chain-enforced MAX of 500
    /// @param executor TEE executor address from `TEEServiceRegistry.getServicesByCapability(0, true)`;
    ///        node rejects `address(0)` with `'executor address cannot be zero'`
    /// @param encryptedSecrets ECIES-encrypted secrets blob (eciespy, `symmetric_nonce_length=12`,
    ///        encrypted against the executor's `publicKey` from the registry). MUST contain a JSON object
    ///        with `LLM_PROVIDER` key (`"anthropic"`/`"openai"`/`"gemini"`/`"openrouter"`/`"ritual"`) plus
    ///        the provider API key. Executor rejects with `'LLM_PROVIDER not found in secrets'` otherwise.
    /// @param userPublicKey Optional 65-byte uncompressed SEC1 pubkey (with `0x04` prefix) for encrypted
    ///        result delivery. Empty = plaintext result.
    /// @param pollIntervalBlocks Phase-2 polling cadence (recommend 5)
    /// @param maxPollBlock Phase-2 deadline RELATIVE offset from Phase-1 submission; chain max 70000
    /// @param maxFeePerGas EIP-1559 max fee for the delivery callback tx (recommend ≥ 1 gwei)
    /// @param maxPriorityFeePerGas EIP-1559 priority fee for the delivery callback tx (recommend ≥ 0.1 gwei)
    struct InvestigationRequest {
        // Market-state fields
        uint16 cliType;
        string prompt;
        StorageRef systemPrompt;
        StorageRef[] skills;
        string model;
        string[] tools;
        uint16 maxTurns;
        uint32 maxTokens;
        bytes4 callbackSelector;
        uint256 callbackGasLimit;
        uint256 ttl;
        // Operator-supplied submission fields
        address executor;
        bytes encryptedSecrets;
        bytes userPublicKey;
        uint64 pollIntervalBlocks;
        uint64 maxPollBlock;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
    }

    /// @notice Subset of `0x0802` LLM Inference fields used by the judge
    /// @dev Remaining fields (logitBiasJson, logprobs, metadataJson, modalitiesJson, n,
    ///      parallelToolCalls, presencePenalty, frequencyPenalty, serviceTier, stream, toolsData,
    ///      toolChoiceData, topLogprobs, user, encryptedSecrets, secretSignatures, userPublicKey)
    ///      are defaulted inside RitualSystem when constructing the full 30-field precompile call.
    /// @param messagesJson OpenAI-compatible messages array as JSON
    /// @param model LLM model identifier (e.g. "zai-org/GLM-4.7-FP8")
    /// @param maxCompletionTokens Token cap on the completion; -1 = model default
    /// @param reasoningEffort String knob ("low" | "medium" | "high")
    /// @param responseFormatData JSON-schema nudge for structured output (best-effort)
    /// @param seed Deterministic seed (we pass marketId)
    /// @param temperature Temperature ×1000 (we pass 0)
    /// @param topP Top-p ×1000 (we pass 1000)
    struct JudgeRequest {
        string messagesJson;
        string model;
        int256 maxCompletionTokens;
        string reasoningEffort;
        bytes responseFormatData;
        int256 seed;
        int256 temperature;
        int256 topP;
    }

    // ============================================================================
    // ERRORS
    // ============================================================================

    /// @notice Reverts when the 0x080C precompile call fails at the EVM layer
    error InvestigatePrecompileFailed();

    /// @notice Reverts when the 0x0802 precompile call fails at the EVM layer
    error JudgePrecompileFailed();

    /// @notice Reverts when 0x0802 returns an explicit error payload
    /// @param message The error message returned by the precompile
    error JudgeRuntimeError(string message);

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Submit an investigation job against the Sovereign Agent precompile
    /// @dev The Phase-1 return is treated as opaque (upstream `SovereignAgentConsumer.sol` does the
    ///      same). The actual jobId is delivered by AsyncDelivery in the Phase-2 callback. Callers
    ///      correlate submission → callback via the chain's single-pending-job invariant on
    ///      `AsyncJobTracker.hasPendingJobForSender(address(this))`.
    /// @param request Investigation-specific parameters composed by the caller
    function investigate(InvestigationRequest calldata request) external;

    /// @notice Run the judge prompt against the LLM Inference precompile (SPC, inline result)
    /// @param request Judge-specific parameters composed by the caller
    /// @return completionData Raw completionData bytes returned by 0x0802
    function judge(JudgeRequest calldata request) external returns (bytes memory completionData);

    /// @notice The AsyncDelivery system contract used as the trust boundary for callbacks
    /// @return delivery The genesis-deployed AsyncDelivery address
    function asyncDelivery() external pure returns (address delivery);

    /// @notice The TEEServiceRegistry consulted for off-chain consistency audits
    /// @return registry The genesis-deployed TEEServiceRegistry address
    function teeServiceRegistry() external pure returns (address registry);

    /// @notice The AsyncJobTracker emitting lifecycle events
    /// @return tracker The genesis-deployed AsyncJobTracker address
    function asyncJobTracker() external pure returns (address tracker);

    /// @notice The RitualWallet used for EOA fee escrow
    /// @return wallet The genesis-deployed RitualWallet address
    function ritualWallet() external pure returns (address wallet);
}
