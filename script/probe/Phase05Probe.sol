// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title Phase05Probe — Phase-0.5 testnet probe consumer
/// @notice Modelled on examples/sovereign-agent/SovereignAgentConsumer.sol from the Ritual skill
///         repo, with extra event instrumentation so the three Phase-0.5 concerns can be answered
///         from chain logs alone — no off-chain reconstruction required.
/// @dev The probe consumer is intentionally NOT Market.sol. We want to isolate testnet observations
///      from Market.sol's harness rules + verdict parsing. Findings inform Phase 4 wiring.
contract Phase05Probe {
    // ============================================================================
    // CONSTANTS
    // ============================================================================

    address public constant SOVEREIGN_AGENT = address(0x080C);
    address public constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address public constant TEE_SERVICE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address public constant ASYNC_JOB_TRACKER = 0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5;

    // ============================================================================
    // STORAGE
    // ============================================================================

    /// @notice Job ids submitted via this contract, keyed by submitter
    mapping(address => bytes32) public lastJobIdBySubmitter;

    /// @notice Most recent raw callback bytes (for off-chain decode + inspection)
    bytes public lastResultRaw;

    /// @notice Most recent callback's decoded fields (best-effort)
    bool public lastSuccess;
    string public lastError;
    string public lastText;

    /// @notice Counter of submissions seen
    uint256 public submitCount;

    /// @notice Counter of callbacks received
    uint256 public callbackCount;

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when callSovereignAgent is invoked. `requestInput` is the full ABI-encoded
    ///         23-field SovereignAgentRequest as passed to 0x080C — the probe captures it so
    ///         analysts can recompute the request binding off-chain.
    event PhaseOneSubmitted(
        uint256 indexed submitNo,
        address indexed submitter,
        bytes32 indexed jobId,
        bytes requestInput
    );

    /// @notice Emitted by `onSovereignAgentResult` for every callback delivery. `result` is the
    ///         raw Phase-2 payload exactly as AsyncDelivery hands it back.
    event SovereignAgentResultDelivered(bytes32 indexed jobId, bytes result);

    /// @notice Emitted after attempting to decode the canonical 6-field shape
    ///         (bool, string, string, StorageRef, StorageRef, StorageRef[]). `decoded` records
    ///         whether the abi.decode succeeded.
    event ResultDecodedAttempt(
        bytes32 indexed jobId,
        bool decoded,
        bool success,
        string errorMessage,
        string textResponse,
        uint256 artifactsLen
    );

    /// @notice Emitted when the AsyncDelivery msg.sender check fails — captures the unauthorized
    ///         caller for forensic logging. Useful if a probe variant is run to confirm the auth
    ///         path stays tight.
    event UnauthorizedCallback(address indexed caller, bytes32 indexed jobId);

    // ============================================================================
    // ERRORS
    // ============================================================================

    error PrecompileFailed(bytes returnData);
    error Unauthorized(address caller);

    // ============================================================================
    // PHASE 1 SUBMISSION
    // ============================================================================

    /// @notice Submit a Sovereign Agent job. `input` is the full 23-field ABI-encoded
    ///         SovereignAgentRequest produced by the off-chain encoder.
    /// @return jobId The Phase-1 job id returned by the precompile
    function callSovereignAgent(bytes calldata input) external returns (bytes32 jobId) {
        (bool ok, bytes memory ret) = SOVEREIGN_AGENT.call(input);
        if (!ok) revert PrecompileFailed(ret);

        // Phase-1 output shape: (bytes32 jobId, bool hasError, bytes result, string errorMessage, (string,string,string) updatedConvoHistory)
        (jobId, , , , ) = abi.decode(ret, (bytes32, bool, bytes, string, StorageRef));

        unchecked {
            submitCount += 1;
        }
        lastJobIdBySubmitter[msg.sender] = jobId;

        emit PhaseOneSubmitted(submitCount, msg.sender, jobId, input);
    }

    // ============================================================================
    // PHASE 2 CALLBACK
    // ============================================================================

    /// @notice AsyncDelivery callback. Records raw result + attempts a best-effort 6-field decode.
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external {
        if (msg.sender != ASYNC_DELIVERY) {
            emit UnauthorizedCallback(msg.sender, jobId);
            revert Unauthorized(msg.sender);
        }

        unchecked {
            callbackCount += 1;
        }
        lastResultRaw = result;

        emit SovereignAgentResultDelivered(jobId, result);
        _tryDecode(jobId, result);
    }

    // ============================================================================
    // INTERNAL
    // ============================================================================

    /// @dev Try the canonical 6-field decode pattern; record success in storage + event.
    function _tryDecode(bytes32 jobId, bytes calldata result) internal {
        try this.decodeCanonical(result) returns (
            bool success,
            string memory errorMessage,
            string memory textResponse,
            StorageRef memory,
            StorageRef memory,
            StorageRef[] memory artifacts
        ) {
            lastSuccess = success;
            lastError = errorMessage;
            lastText = textResponse;
            emit ResultDecodedAttempt(jobId, true, success, errorMessage, textResponse, artifacts.length);
        } catch {
            emit ResultDecodedAttempt(jobId, false, false, "", "", 0);
        }
    }

    /// @notice External wrapper around the canonical decode so the constructor can try/catch it.
    function decodeCanonical(
        bytes calldata result
    )
        external
        pure
        returns (
            bool success,
            string memory errorMessage,
            string memory textResponse,
            StorageRef memory ref1,
            StorageRef memory ref2,
            StorageRef[] memory artifacts
        )
    {
        (success, errorMessage, textResponse, ref1, ref2, artifacts) = abi.decode(
            result,
            (bool, string, string, StorageRef, StorageRef, StorageRef[])
        );
    }

    // ============================================================================
    // TYPES
    // ============================================================================

    /// @notice Ritual L1 off-chain content reference
    struct StorageRef {
        string platform;
        string path;
        string keyRef;
    }
}
