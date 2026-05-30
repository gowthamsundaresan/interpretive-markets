// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IFrameworkRegistry} from "../interfaces/IFrameworkRegistry.sol";

/// @title FrameworkRegistry
/// @notice Append-only registry of interpretive frameworks
/// @dev Anyone may register a new framework id. Ids are never updated or removed.
contract FrameworkRegistry is IFrameworkRegistry {
    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice Mapping of framework id to stored record
    mapping(bytes32 => Framework) private _frameworks;

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IFrameworkRegistry
    function register(bytes32 id, string calldata uri, bytes calldata metadata) external {
        if (id == bytes32(0)) revert ZeroId();
        if (bytes(uri).length == 0) revert EmptyURI();
        if (_frameworks[id].registeredAt != 0) revert FrameworkAlreadyRegistered(id);

        _frameworks[id] = Framework({
            uri: uri,
            metadata: metadata,
            author: msg.sender,
            registeredAt: uint64(block.timestamp)
        });

        emit FrameworkRegistered(id, uri, msg.sender, metadata);
    }

    /// @inheritdoc IFrameworkRegistry
    function get(bytes32 id) external view returns (Framework memory framework) {
        framework = _frameworks[id];
    }

    /// @inheritdoc IFrameworkRegistry
    function isRegistered(bytes32 id) external view returns (bool registered) {
        registered = _frameworks[id].registeredAt != 0;
    }
}
