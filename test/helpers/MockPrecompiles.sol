// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";

import {IRitualSystem} from "../../src/interfaces/IRitualSystem.sol";

/// @notice Test-only helpers for mocking Ritual L1 system primitives via vm.mockCall
/// @dev Centralizes the mock setup so Market.t.sol stays focused on flow assertions.
library MockPrecompiles {
    // --- Types & state ---

    address internal constant SOVEREIGN_AGENT = address(0x080C);
    address internal constant LLM_INFERENCE = address(0x0802);
    address internal constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;

    // --- Core functions ---

    /// @notice Mock the Sovereign Agent precompile for a Phase-1 submission
    /// @dev `RitualSystem.investigate` treats the Phase-1 return as opaque; we mock a short opaque
    ///      return so the call succeeds. jobId arrives in the Phase-2 callback.
    /// @param vm Forge cheatcode handle
    function mockSovereignAgentSubmit(Vm vm) internal {
        vm.mockCall(SOVEREIGN_AGENT, bytes(""), abi.encode(uint256(0)));
    }

    /// @notice Mock the LLM Inference precompile to return SPC completionData
    /// @param vm Forge cheatcode handle
    /// @param completionData The completion bytes the precompile will return
    function mockJudgeSuccess(Vm vm, bytes memory completionData) internal {
        IRitualSystem.StorageRef memory emptyRef = IRitualSystem.StorageRef({platform: "", path: "", keyRef: ""});
        bytes memory ret = abi.encode(false, completionData, bytes(""), string(""), emptyRef);
        vm.mockCall(LLM_INFERENCE, bytes(""), ret);
    }

    /// @notice Mock the LLM Inference precompile to return an explicit error
    /// @param vm Forge cheatcode handle
    /// @param errorMessage Error message the precompile will report
    function mockJudgeError(Vm vm, string memory errorMessage) internal {
        IRitualSystem.StorageRef memory emptyRef = IRitualSystem.StorageRef({platform: "", path: "", keyRef: ""});
        bytes memory ret = abi.encode(true, bytes(""), bytes(""), errorMessage, emptyRef);
        vm.mockCall(LLM_INFERENCE, bytes(""), ret);
    }

    /// @notice Build the Phase-2 callback result bytes for `onSovereignAgentResult` in the
    ///         canonical 6-field shape `(bool, string, string, StorageRef, StorageRef, StorageRef[])`.
    ///         The investigator pre-assembles the judge messagesJson into `text` and pins the
    ///         dossier in `artifacts[0]`. The default assembled JSON is a representative stub;
    ///         tests that exercise the judge prompt specifically pass an explicit messagesJson.
    function buildInvestigatorResult(
        string memory dossierCid,
        address /* executor */
    ) internal pure returns (bytes memory) {
        return buildInvestigatorResult(dossierCid, _defaultMessagesJson(dossierCid));
    }

    /// @notice Overload that lets tests pin a specific assembled judge messagesJson.
    function buildInvestigatorResult(
        string memory dossierCid,
        string memory messagesJson
    ) internal pure returns (bytes memory) {
        IRitualSystem.StorageRef memory emptyRef = IRitualSystem.StorageRef({platform: "", path: "", keyRef: ""});
        IRitualSystem.StorageRef[] memory artifacts = new IRitualSystem.StorageRef[](1);
        artifacts[0] = IRitualSystem.StorageRef({platform: "ipfs", path: dossierCid, keyRef: ""});
        return abi.encode(true, "", messagesJson, emptyRef, emptyRef, artifacts);
    }

    /// @notice Adversarial overload — pins the dossier StorageRef's platform AND path explicitly.
    /// @dev Asserts Market.sol rejects non-IPFS platforms and non-CID-shaped paths at the point
    ///      of detection (not via empty-string side effect).
    function buildInvestigatorResultWithStorageRef(
        string memory dossierPlatform,
        string memory dossierPath,
        string memory messagesJson
    ) internal pure returns (bytes memory) {
        IRitualSystem.StorageRef memory emptyRef = IRitualSystem.StorageRef({platform: "", path: "", keyRef: ""});
        IRitualSystem.StorageRef[] memory artifacts = new IRitualSystem.StorageRef[](1);
        artifacts[0] = IRitualSystem.StorageRef({platform: dossierPlatform, path: dossierPath, keyRef: ""});
        return abi.encode(true, "", messagesJson, emptyRef, emptyRef, artifacts);
    }

    /// @notice Encode a verdict JSON payload for inclusion in completionData
    function buildVerdictJson(
        uint8 outcome,
        uint16 confidenceBps,
        uint8 drivingTier,
        string memory subjectRef,
        string memory rationaleHashHex,
        string[] memory citations
    ) internal pure returns (string memory json) {
        string memory citationsArr = _toJsonStringArray(citations);
        json = string.concat(
            "{",
            '"outcome":',
            _toString(uint256(outcome)),
            ',"confidence_bps":',
            _toString(uint256(confidenceBps)),
            ',"driving_tier":',
            _toString(uint256(drivingTier)),
            ',"subject_ref":"',
            subjectRef,
            '","rationale_hash":"',
            rationaleHashHex,
            '","citations":',
            citationsArr,
            "}"
        );
    }

    // --- Helper functions ---

    function _toJsonStringArray(string[] memory items) private pure returns (string memory out) {
        out = "[";
        for (uint256 i = 0; i < items.length; i++) {
            if (i > 0) out = string.concat(out, ",");
            out = string.concat(out, '"', items[i], '"');
        }
        out = string.concat(out, "]");
    }

    function _defaultMessagesJson(string memory dossierCid) private pure returns (string memory) {
        return
            string.concat(
                '[{"role":"system","content":"stub judge prompt"},',
                '{"role":"user","content":"Question: stub; Dossier: ipfs://',
                dossierCid,
                '"}]'
            );
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 v = value;
        uint256 digits;
        while (v != 0) {
            digits++;
            v /= 10;
        }
        bytes memory buf = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buf[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buf);
    }
}
