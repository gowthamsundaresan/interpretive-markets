// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAttestedExecutorRegistry} from "../interfaces/IAttestedExecutorRegistry.sol";

/// @title AttestedExecutorRegistry
/// @notice Owner-curated allowlist of TEE executor addresses permitted to resolve markets
/// @dev Application-layer overlay on top of Ritual's protocol-enforced attestation.
contract AttestedExecutorRegistry is IAttestedExecutorRegistry, Ownable {
    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice Mapping of executor address to stored record
    mapping(address => Executor) private _executors;

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Sets the initial owner that may register and toggle executors
    constructor(address initialOwner) Ownable(initialOwner) {}

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IAttestedExecutorRegistry
    function register(address executor) external onlyOwner {
        if (executor == address(0)) revert ZeroExecutor();
        if (_executors[executor].registeredAt != 0) revert ExecutorAlreadyRegistered(executor);

        _executors[executor] = Executor({enabled: true, registeredAt: uint64(block.timestamp)});

        emit ExecutorRegistered(executor);
    }

    /// @inheritdoc IAttestedExecutorRegistry
    function setEnabled(address executor, bool enabled) external onlyOwner {
        if (_executors[executor].registeredAt == 0) revert ExecutorNotRegistered(executor);

        _executors[executor].enabled = enabled;
        emit ExecutorEnabledSet(executor, enabled);
    }

    /// @inheritdoc IAttestedExecutorRegistry
    function get(address executor) external view returns (Executor memory record) {
        record = _executors[executor];
    }

    /// @inheritdoc IAttestedExecutorRegistry
    function isAttested(address executor) external view returns (bool attested) {
        Executor memory e = _executors[executor];
        attested = e.registeredAt != 0 && e.enabled;
    }
}
