// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title DossierManifest
/// @notice Helpers for validating citation strings against a dossier path manifest
/// @dev Validation is intentionally structural; deep "this citation resolves to a real dossier
///      value" checks live off-chain in the eval-harness.
library DossierManifest {
    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @notice True when `value` starts with the byte sequence of `prefix`
    /// @param value The string to inspect
    /// @param prefix The required leading byte sequence
    /// @return ok True when value begins with prefix
    function hasPrefix(string memory value, string memory prefix) internal pure returns (bool ok) {
        bytes memory v = bytes(value);
        bytes memory p = bytes(prefix);
        if (v.length < p.length) return false;
        for (uint256 i = 0; i < p.length; i++) {
            if (v[i] != p[i]) return false;
        }
        ok = true;
    }

    /// @notice True when `value` equals `expected` byte-for-byte
    /// @param value The candidate string
    /// @param expected The target string
    /// @return ok True when the two strings are byte-identical
    function equals(string memory value, string memory expected) internal pure returns (bool ok) {
        ok = keccak256(bytes(value)) == keccak256(bytes(expected));
    }

    /// @notice True when `platform` is exactly the literal "ipfs"
    /// @dev Only content-addressed bytes are admissible on the on-chain path. A mutable storage
    ///      platform (e.g. HuggingFace) would let the executor substitute the dossier
    ///      post-callback and defeat the watcher's recompute-and-compare audit.
    /// @param platform The StorageRef platform field from the investigator's artifacts[0]
    /// @return ok True when platform is "ipfs"
    function validateIpfsPlatform(string memory platform) internal pure returns (bool ok) {
        ok = equals(platform, "ipfs");
    }

    /// @notice True when `cid` looks like a syntactically valid IPFS CID
    /// @dev Cheap prefix check covering CIDv1 base32 (bafy*, bafk*, bafz*) and CIDv0 base58btc
    ///      (Qm*). Deeper validation (multihash parse, codec sanity) belongs off-chain; this is the
    ///      on-chain belt that catches the obvious leak — a path string with no recognisable CID
    ///      shape (e.g. an HF dataset path "user/repo/file.json") cannot pretend to be an IPFS CID.
    /// @param cid The path field from the investigator's artifacts[0]
    /// @return ok True when cid begins with bafy/bafk/bafz (CIDv1) or Qm (CIDv0)
    function validateIpfsCidShape(string memory cid) internal pure returns (bool ok) {
        bytes memory b = bytes(cid);
        if (b.length < 8) return false;
        // CIDv1 base32: "bafy", "bafk", "bafz" prefixes
        if (b[0] == 0x62 && b[1] == 0x61 && b[2] == 0x66) {
            if (b[3] == 0x79 || b[3] == 0x6b || b[3] == 0x7a) return true;
        }
        // CIDv0 base58btc: "Qm" prefix
        if (b[0] == 0x51 && b[1] == 0x6d) return true;
        return false;
    }
}
