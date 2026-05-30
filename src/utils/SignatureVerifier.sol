// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {ResolutionTypes} from "../libraries/ResolutionTypes.sol";

/// @title SignatureVerifier
/// @notice Helpers for hashing and recovering signers of market verdicts
library SignatureVerifier {
    using MessageHashUtils for bytes32;

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Compute the canonical digest signed by the judge for a verdict
    /// @param marketId The market id
    /// @param verdict The verdict struct
    /// @param bundleRef Pointer to the re-execution bundle
    /// @return digest The EIP-191 prefixed digest
    function verdictDigest(
        uint256 marketId,
        ResolutionTypes.Verdict memory verdict,
        string memory bundleRef
    ) internal pure returns (bytes32 digest) {
        bytes32 raw = keccak256(abi.encode(marketId, verdict, bundleRef));
        digest = raw.toEthSignedMessageHash();
    }

    /// @notice Recover the signer of a verdict signature
    /// @param marketId The market id
    /// @param verdict The verdict struct
    /// @param bundleRef Pointer to the re-execution bundle
    /// @param signature ECDSA signature
    /// @return signer The recovered signer address
    function recoverVerdictSigner(
        uint256 marketId,
        ResolutionTypes.Verdict memory verdict,
        string memory bundleRef,
        bytes memory signature
    ) internal pure returns (address signer) {
        signer = ECDSA.recover(verdictDigest(marketId, verdict, bundleRef), signature);
    }
}
