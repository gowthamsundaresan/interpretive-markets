// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IRitualSystem Interface
/// @notice Typed wrappers over Ritual L1 system primitives used by Market.sol
/// @dev Addresses captured from docs.ritualfoundation.org (PLAN.md §5 Phase 0).
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

    /// @notice Subset of `0x080C` SovereignAgentParams that Market.sol composes
    /// @dev Remaining fields (executor selection, encryptedSecrets, convoHistory, previousOutput,
    ///      pollingIntervalBlocks, maxPollBlock, maxFeePerGas, maxPriorityFeePerGas, rpcUrls) are
    ///      defaulted inside RitualSystem when constructing the full 23-field precompile call.
    /// @param cliType Harness selector (0 = Claude Code per ADR-004)
    /// @param prompt Investigation task prompt
    /// @param systemPrompt StorageRef pointing at investigator.md
    /// @param skills StorageRefs pointing at dossier schema and other skill manifests
    /// @param model LLM model identifier the harness should use
    /// @param tools Allowlist of tool names exposed to the harness
    /// @param maxTurns Cap on agentic reasoning turns
    /// @param maxTokens Cap on output tokens
    /// @param callbackSelector Function selector on Market that receives the delivery
    /// @param gasLimit Gas budget for the callback transaction (must cover SPC + finalize)
    /// @param ttl Phase-1 time-to-live in blocks
    struct InvestigationRequest {
        uint16 cliType;
        string prompt;
        StorageRef systemPrompt;
        StorageRef[] skills;
        string model;
        string[] tools;
        uint16 maxTurns;
        uint32 maxTokens;
        bytes4 callbackSelector;
        uint256 gasLimit;
        uint256 ttl;
    }

    /// @notice Subset of `0x0802` LLM Inference fields used by the judge
    /// @dev Remaining fields (logitBiasJson, logprobs, metadataJson, modalitiesJson, n,
    ///      parallelToolCalls, presencePenalty, frequencyPenalty, serviceTier, stream, toolsData,
    ///      toolChoiceData, topLogprobs, user, encryptedSecrets, secretSignatures, userPublicKey)
    ///      are defaulted inside RitualSystem when constructing the full 30-field precompile call.
    /// @param messagesJson OpenAI-compatible messages array as JSON
    /// @param model LLM model identifier (e.g. "zai-org/GLM-4.7-FP8")
    /// @param maxCompletionTokens Token cap on the completion; -1 = model default
    /// @param reasoningEffort String knob ("low" | "medium" | "high"); see ADR pending Phase 4
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
    /// @param request Investigation-specific parameters composed by the caller
    /// @return jobId The AsyncJobTracker job identifier returned by the precompile
    function investigate(InvestigationRequest calldata request) external returns (bytes32 jobId);

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
