// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {JudgeRegistry} from "../src/core/JudgeRegistry.sol";
import {IJudgeRegistry} from "../src/interfaces/IJudgeRegistry.sol";

contract JudgeRegistryTest is Test {
    // --- Types ---

    JudgeRegistry internal registry;
    address internal owner;
    address internal stranger;
    address internal signer;

    bytes32 internal constant DIGEST = keccak256("judge-image-v0");

    // --- Core functions ---

    function setUp() public {
        owner = makeAddr("owner");
        stranger = makeAddr("stranger");
        signer = makeAddr("signer");
        registry = new JudgeRegistry(owner);
    }

    function test_register_storesRecord() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit IJudgeRegistry.JudgeRegistered(DIGEST, signer);
        registry.register(DIGEST, signer);

        IJudgeRegistry.Judge memory j = registry.get(DIGEST);
        assertEq(j.signer, signer);
        assertTrue(j.enabled);
        assertEq(j.registeredAt, uint64(block.timestamp));
        assertTrue(registry.isAuthorized(DIGEST, signer));
    }

    function test_register_revertsOnNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        registry.register(DIGEST, signer);
    }

    function test_register_revertsOnDuplicate() public {
        vm.startPrank(owner);
        registry.register(DIGEST, signer);
        vm.expectRevert(abi.encodeWithSelector(IJudgeRegistry.JudgeAlreadyRegistered.selector, DIGEST));
        registry.register(DIGEST, signer);
        vm.stopPrank();
    }

    function test_register_revertsOnZeroDigest() public {
        vm.prank(owner);
        vm.expectRevert(IJudgeRegistry.ZeroImageDigest.selector);
        registry.register(bytes32(0), signer);
    }

    function test_register_revertsOnZeroSigner() public {
        vm.prank(owner);
        vm.expectRevert(IJudgeRegistry.ZeroSigner.selector);
        registry.register(DIGEST, address(0));
    }

    function test_setEnabled_togglesAuthorization() public {
        vm.startPrank(owner);
        registry.register(DIGEST, signer);
        registry.setEnabled(DIGEST, false);
        vm.stopPrank();

        assertFalse(registry.get(DIGEST).enabled);
        assertFalse(registry.isAuthorized(DIGEST, signer));
    }

    function test_setEnabled_revertsOnUnregistered() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IJudgeRegistry.JudgeNotRegistered.selector, DIGEST));
        registry.setEnabled(DIGEST, false);
    }

    function test_isAuthorized_falseForMismatchedSigner() public {
        vm.prank(owner);
        registry.register(DIGEST, signer);
        assertFalse(registry.isAuthorized(DIGEST, stranger));
    }
}
