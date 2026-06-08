// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IRitualSystem} from "../interfaces/IRitualSystem.sol";

/// @title RitualSystem
/// @notice Typed wrappers over Ritual L1 system contracts and precompiles
contract RitualSystem is IRitualSystem {
    // --- Constants ---

    address internal constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address internal constant TEE_SERVICE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address internal constant ASYNC_JOB_TRACKER = 0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5;
    address internal constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;

    address internal constant SOVEREIGN_AGENT = address(0x080C);
    address internal constant LLM_INFERENCE = address(0x0802);

    // --- Core functions ---

    /// @inheritdoc IRitualSystem
    function investigate(InvestigationRequest calldata request) external {
        bytes memory encoded = _encodeSovereignAgentParams(request);
        (bool ok, bytes memory ret) = SOVEREIGN_AGENT.call(encoded);
        if (!ok) revert InvestigatePrecompileFailed();
        ret; // upstream consumer treats the Phase-1 return as opaque; jobId arrives via callback
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

    // --- Helper functions ---

    /// @dev Build the 23-field SovereignAgentParams calldata. Node-side constraints the validator
    ///      enforces: `executor != address(0)`, `ttl ≤ 500`, `maxPollBlock ≤ 70000` (relative),
    ///      `maxFeePerGas ≥ 1 gwei`, `encryptedSecrets` must decrypt to JSON containing `LLM_PROVIDER`.
    function _encodeSovereignAgentParams(InvestigationRequest calldata r) internal view returns (bytes memory) {
        StorageRef memory emptyRef = StorageRef({platform: "", path: "", keyRef: ""});
        return
            abi.encode(
                r.executor,
                r.ttl,
                r.userPublicKey,
                r.pollIntervalBlocks,
                r.maxPollBlock,
                string(""), // taskIdMarker
                msg.sender, // deliveryTarget
                r.callbackSelector,
                r.callbackGasLimit,
                r.maxFeePerGas,
                r.maxPriorityFeePerGas,
                r.cliType,
                r.prompt,
                r.encryptedSecrets,
                emptyRef, // convoHistory
                emptyRef, // output
                r.skills,
                r.systemPrompt,
                r.model,
                r.tools,
                r.maxTurns,
                r.maxTokens,
                string("") // rpcUrls
            );
    }

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
