// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {Attestation} from "../src/libraries/Attestation.sol";

contract AttestationTest is Test {
    // --- Core functions ---

    function test_recordOf_bindsExecutorBlockAndBinding() public {
        address executor = makeAddr("executor");
        bytes32 binding = keccak256("inputs");

        vm.roll(1234);
        Attestation.Record memory r = _wrapRecordOf(executor, binding);

        assertEq(r.executor, executor);
        assertEq(r.attestedAtBlock, 1234);
        assertEq(r.requestBinding, binding);
    }

    // --- Helper functions ---

    function _wrapRecordOf(address executor, bytes32 binding) internal view returns (Attestation.Record memory) {
        return Attestation.recordOf(executor, binding);
    }
}
