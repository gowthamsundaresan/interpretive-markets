// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IFrameworkRegistry Interface
/// @notice Append-only registry of interpretive frameworks. A framework is a content-addressed
///         tarball describing how an AI judge should evaluate a class of questions.
interface IFrameworkRegistry {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Stored record for a registered framework
    /// @param uri Pointer to the framework tarball (e.g. ipfs://<cid>, https://...)
    /// @param metadata Opaque application-defined metadata (e.g. encoded manifest summary)
    /// @param author Address that registered the framework
    /// @param registeredAt Block timestamp at registration
    struct Framework {
        string uri;
        bytes metadata;
        address author;
        uint64 registeredAt;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when a framework is registered
    /// @param id The framework id (sha256 of the tarball bytes)
    /// @param uri Pointer to the framework tarball
    /// @param author Address that registered the framework
    /// @param metadata Opaque application-defined metadata
    event FrameworkRegistered(bytes32 indexed id, string uri, address indexed author, bytes metadata);

    // ============================================================================
    // ERRORS
    // ============================================================================

    /// @notice Reverts when a framework with the given id has already been registered
    /// @param id The framework id
    error FrameworkAlreadyRegistered(bytes32 id);

    /// @notice Reverts when registration is attempted with an empty URI
    error EmptyURI();

    /// @notice Reverts when registration is attempted with a zero id
    error ZeroId();

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Register a new framework. Append-only; ids cannot be re-registered or updated.
    /// @param id The framework id (sha256 of the tarball bytes)
    /// @param uri Pointer to the framework tarball
    /// @param metadata Opaque application-defined metadata
    function register(bytes32 id, string calldata uri, bytes calldata metadata) external;

    /// @notice Fetch the full framework record for a given id
    /// @param id The framework id
    /// @return framework The stored framework record
    function get(bytes32 id) external view returns (Framework memory framework);

    /// @notice Check whether a framework id has been registered
    /// @param id The framework id
    /// @return registered True if a framework with this id exists
    function isRegistered(bytes32 id) external view returns (bool registered);
}
