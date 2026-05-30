// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IJudgeRegistry Interface
/// @notice Registry binding an EigenCompute image digest to the Ethereum signer address derived
///         inside that image's TEE. Markets only accept verdict signatures from registered judges.
interface IJudgeRegistry {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Stored record for a registered judge
    /// @param signer Ethereum address derived from the TEE mnemonic inside the judge image
    /// @param enabled Whether the judge is currently allowed to resolve markets
    /// @param registeredAt Block timestamp at registration
    struct Judge {
        address signer;
        bool enabled;
        uint64 registeredAt;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when a judge image is registered
    /// @param imageDigest The EigenCompute image digest (sha256 of the Docker image)
    /// @param signer Ethereum address derived from the TEE mnemonic
    event JudgeRegistered(bytes32 indexed imageDigest, address indexed signer);

    /// @notice Emitted when a judge is enabled or disabled
    /// @param imageDigest The EigenCompute image digest
    /// @param enabled New enabled state
    event JudgeEnabledSet(bytes32 indexed imageDigest, bool enabled);

    // ============================================================================
    // ERRORS
    // ============================================================================

    /// @notice Reverts when a judge image has already been registered
    /// @param imageDigest The judge image digest
    error JudgeAlreadyRegistered(bytes32 imageDigest);

    /// @notice Reverts when interacting with an unregistered judge image
    /// @param imageDigest The judge image digest
    error JudgeNotRegistered(bytes32 imageDigest);

    /// @notice Reverts when registration is attempted with a zero image digest
    error ZeroImageDigest();

    /// @notice Reverts when registration is attempted with a zero signer address
    error ZeroSigner();

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Register a new judge image
    /// @param imageDigest The EigenCompute image digest
    /// @param signer Ethereum address derived from the TEE mnemonic
    function register(bytes32 imageDigest, address signer) external;

    /// @notice Enable or disable a registered judge
    /// @param imageDigest The EigenCompute image digest
    /// @param enabled New enabled state
    function setEnabled(bytes32 imageDigest, bool enabled) external;

    /// @notice Fetch the full judge record for a given image digest
    /// @param imageDigest The EigenCompute image digest
    /// @return judge The stored judge record
    function get(bytes32 imageDigest) external view returns (Judge memory judge);

    /// @notice Check whether a (imageDigest, signer) pair is currently authorized
    /// @param imageDigest The EigenCompute image digest
    /// @param signer The candidate signer address
    /// @return authorized True if the judge is registered, enabled, and the signer matches
    function isAuthorized(bytes32 imageDigest, address signer) external view returns (bool authorized);
}
