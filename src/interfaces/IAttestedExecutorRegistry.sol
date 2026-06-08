// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IAttestedExecutorRegistry Interface
/// @notice Owner-curated allowlist of TEE executor addresses that are permitted to resolve markets.
///         Protocol-layer attestation against `TEEServiceRegistry` is enforced by the Ritual block
///         builder; this registry is an application-layer overlay that lets the owner narrow the
///         set of attested executors a market will accept.
interface IAttestedExecutorRegistry {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Stored record for a registered executor
    /// @param enabled Whether the executor is currently allowed to deliver verdicts
    /// @param registeredAt Block timestamp at registration
    struct Executor {
        bool enabled;
        uint64 registeredAt;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when an executor is registered
    /// @param executor TEE executor address
    event ExecutorRegistered(address indexed executor);

    /// @notice Emitted when an executor is enabled or disabled
    /// @param executor TEE executor address
    /// @param enabled New enabled state
    event ExecutorEnabledSet(address indexed executor, bool enabled);

    // ============================================================================
    // ERRORS
    // ============================================================================

    /// @notice Reverts when an executor address has already been registered
    /// @param executor TEE executor address
    error ExecutorAlreadyRegistered(address executor);

    /// @notice Reverts when interacting with an unregistered executor
    /// @param executor TEE executor address
    error ExecutorNotRegistered(address executor);

    /// @notice Reverts when registration is attempted with the zero address
    error ZeroExecutor();

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Register a new TEE executor address
    /// @param executor TEE executor address
    function register(address executor) external;

    /// @notice Enable or disable a registered executor
    /// @param executor TEE executor address
    /// @param enabled New enabled state
    function setEnabled(address executor, bool enabled) external;

    /// @notice Fetch the full executor record for a given address
    /// @param executor TEE executor address
    /// @return record The stored executor record
    function get(address executor) external view returns (Executor memory record);

    /// @notice Check whether an executor is currently registered AND enabled
    /// @param executor TEE executor address
    /// @return attested True when the executor is registered and currently enabled
    function isAttested(address executor) external view returns (bool attested);
}
