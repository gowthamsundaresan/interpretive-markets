// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IJudgeRegistry} from "../interfaces/IJudgeRegistry.sol";

/// @title JudgeRegistry
/// @notice Owner-gated registry binding EigenCompute image digests to TEE-derived signers
/// @dev Only the owner may register or enable/disable judges
contract JudgeRegistry is IJudgeRegistry, Ownable {
    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice Mapping of image digest to stored record
    mapping(bytes32 => Judge) private _judges;

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Sets the initial owner that may register and toggle judges
    constructor(address initialOwner) Ownable(initialOwner) {}

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IJudgeRegistry
    function register(bytes32 imageDigest, address signer) external onlyOwner {
        if (imageDigest == bytes32(0)) revert ZeroImageDigest();
        if (signer == address(0)) revert ZeroSigner();
        if (_judges[imageDigest].registeredAt != 0) revert JudgeAlreadyRegistered(imageDigest);

        _judges[imageDigest] = Judge({signer: signer, enabled: true, registeredAt: uint64(block.timestamp)});

        emit JudgeRegistered(imageDigest, signer);
    }

    /// @inheritdoc IJudgeRegistry
    function setEnabled(bytes32 imageDigest, bool enabled) external onlyOwner {
        if (_judges[imageDigest].registeredAt == 0) revert JudgeNotRegistered(imageDigest);

        _judges[imageDigest].enabled = enabled;
        emit JudgeEnabledSet(imageDigest, enabled);
    }

    /// @inheritdoc IJudgeRegistry
    function get(bytes32 imageDigest) external view returns (Judge memory judge) {
        judge = _judges[imageDigest];
    }

    /// @inheritdoc IJudgeRegistry
    function isAuthorized(bytes32 imageDigest, address signer) external view returns (bool authorized) {
        Judge memory j = _judges[imageDigest];
        authorized = j.registeredAt != 0 && j.enabled && j.signer == signer;
    }
}
