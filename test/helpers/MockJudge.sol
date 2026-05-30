// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";

import {ResolutionTypes} from "../../src/libraries/ResolutionTypes.sol";
import {SignatureVerifier} from "../../src/utils/SignatureVerifier.sol";

/// @notice Test-only helper for producing valid judge signatures over verdicts
library MockJudge {
    /// @notice Sign a verdict for the given market with the provided private key
    function signVerdict(
        Vm vm,
        uint256 signerKey,
        uint256 marketId,
        ResolutionTypes.Verdict memory verdict,
        string memory bundleRef
    ) internal pure returns (bytes memory signature) {
        bytes32 digest = SignatureVerifier.verdictDigest(marketId, verdict, bundleRef);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        signature = abi.encodePacked(r, s, v);
    }
}
