// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IRitualSystem} from "../interfaces/IRitualSystem.sol";

/// @title RitualSystem
/// @notice Typed wrappers over Ritual L1 system contracts and precompiles
/// @dev Constants captured from docs.ritualfoundation.org (PLAN.md §5 Phase 0).
///      Phase 0.5 testnet probe finalizes the `bytes result` decode shape and any executor
///      auto-selection conventions; until then this contract accepts the precompile return
///      blob and exposes it to the caller without interpretation.
contract RitualSystem is IRitualSystem {
    // ------------------------------------------------------------------------------
    // Constants — system contracts (genesis-deployed on Ritual L1, chainId 1979)
    // ------------------------------------------------------------------------------

    /// @notice AsyncDelivery system contract (msg.sender check in delivery callbacks)
    address internal constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;

    /// @notice TEEServiceRegistry system contract (off-chain consistency audit lookups)
    address internal constant TEE_SERVICE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;

    /// @notice AsyncJobTracker system contract (lifecycle events)
    address internal constant ASYNC_JOB_TRACKER = 0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5;

    /// @notice RitualWallet system contract (EOA fee escrow)
    address internal constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;

    // ------------------------------------------------------------------------------
    // Constants — precompiles
    // ------------------------------------------------------------------------------

    /// @notice Sovereign Agent precompile (two-phase async; callback delivery)
    address internal constant SOVEREIGN_AGENT = address(0x080C);

    /// @notice LLM Inference precompile (SPC / Short Async; inline result)
    address internal constant LLM_INFERENCE = address(0x0802);

    // ------------------------------------------------------------------------------
    // Constants — investigation defaults
    // ------------------------------------------------------------------------------

    /// @notice Default polling interval for AsyncJobTracker Phase-1 settlement (blocks)
    uint64 internal constant DEFAULT_POLLING_INTERVAL_BLOCKS = 5;

    /// @notice Maximum extra blocks granted for Phase-2 delivery before expiry
    uint64 internal constant DEFAULT_MAX_POLL_BLOCK_OFFSET = 5000;

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IRitualSystem
    function investigate(InvestigationRequest calldata request) external returns (bytes32 jobId) {
        bytes memory encoded = _encodeSovereignAgentParams(request);
        (bool ok, bytes memory ret) = SOVEREIGN_AGENT.call(encoded);
        if (!ok) revert InvestigatePrecompileFailed();

        // Phase-1 return: (bytes32 jobId, bool hasError, bytes result, string errorMessage, StorageRef updatedConvoHistory)
        (jobId, , , , ) = abi.decode(ret, (bytes32, bool, bytes, string, StorageRef));
    }

    /// @inheritdoc IRitualSystem
    function judge(JudgeRequest calldata request) external returns (bytes memory completionData) {
        bytes memory encoded = _encodeLLMInferenceParams(request);
        (bool ok, bytes memory ret) = LLM_INFERENCE.call(encoded);
        if (!ok) revert JudgePrecompileFailed();

        // SPC return: (bool hasError, bytes completionData, bytes modelMetadata, string errorMessage, StorageRef updatedConvoHistory)
        bool hasError;
        string memory errorMessage;
        (hasError, completionData, , errorMessage, ) = abi.decode(ret, (bool, bytes, bytes, string, StorageRef));
        if (hasError) revert JudgeRuntimeError(errorMessage);
    }

    /// @inheritdoc IRitualSystem
    function asyncDelivery() external pure returns (address delivery) {
        delivery = ASYNC_DELIVERY;
    }

    /// @inheritdoc IRitualSystem
    function teeServiceRegistry() external pure returns (address registry) {
        registry = TEE_SERVICE_REGISTRY;
    }

    /// @inheritdoc IRitualSystem
    function asyncJobTracker() external pure returns (address tracker) {
        tracker = ASYNC_JOB_TRACKER;
    }

    /// @inheritdoc IRitualSystem
    function ritualWallet() external pure returns (address wallet) {
        wallet = RITUAL_WALLET;
    }

    // ------------------------------------------------------------------------------
    // Helper functions
    // ------------------------------------------------------------------------------

    /// @dev Build the full 23-field SovereignAgentParams calldata from the caller's slim request.
    ///      Unset fields default per Day-1 findings; executor=0 lets the precompile auto-select.
    function _encodeSovereignAgentParams(InvestigationRequest calldata r) internal view returns (bytes memory) {
        StorageRef memory emptyRef = StorageRef({platform: "", path: "", keyRef: ""});
        return
            abi.encode(
                address(0), // executor (auto-select)
                r.ttl,
                bytes(""), // userPublicKey
                DEFAULT_POLLING_INTERVAL_BLOCKS,
                uint64(block.number) + DEFAULT_MAX_POLL_BLOCK_OFFSET,
                string(""), // taskIdMarker
                msg.sender, // callbackAddress
                r.callbackSelector,
                r.gasLimit,
                uint256(0), // maxFeePerGas
                uint256(0), // maxPriorityFeePerGas
                r.cliType,
                r.prompt,
                bytes(""), // encryptedSecrets
                emptyRef, // convoHistory
                emptyRef, // previousOutput
                r.skills,
                r.systemPrompt,
                r.model,
                r.tools,
                r.maxTurns,
                r.maxTokens,
                string("") // rpcUrls
            );
    }

    /// @dev Build the full 0x0802 LLM Inference calldata from the caller's slim request.
    ///      Tool-calling and streaming fields are left at zero per ADR-006.
    function _encodeLLMInferenceParams(JudgeRequest calldata r) internal pure returns (bytes memory) {
        StorageRef memory emptyRef = StorageRef({platform: "", path: "", keyRef: ""});
        bytes[] memory emptyBytesArr = new bytes[](0);
        return
            abi.encode(
                address(0), // executor (auto-select)
                emptyBytesArr, // encryptedSecrets
                uint256(0), // ttl
                emptyBytesArr, // secretSignatures
                bytes(""), // userPublicKey
                r.messagesJson,
                r.model,
                int256(0), // frequencyPenalty
                string(""), // logitBiasJson
                false, // logprobs
                r.maxCompletionTokens,
                string(""), // metadataJson
                string(""), // modalitiesJson
                uint256(1), // n
                false, // parallelToolCalls
                int256(0), // presencePenalty
                r.reasoningEffort,
                r.responseFormatData,
                r.seed,
                string(""), // serviceTier
                string(""), // stopJson
                false, // stream
                r.temperature,
                bytes(""), // toolChoiceData
                bytes(""), // toolsData
                int256(-1), // topLogprobs
                r.topP,
                string(""), // user
                false, // piiEnabled
                emptyRef // convoHistory
            );
    }
}
