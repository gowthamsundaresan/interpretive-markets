// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {FrameworkRegistry} from "../src/core/FrameworkRegistry.sol";
import {IFrameworkRegistry} from "../src/interfaces/IFrameworkRegistry.sol";

contract FrameworkRegistryTest is Test {
    // --- Types ---

    FrameworkRegistry internal registry;
    address internal alice = address(0xA11CE);

    bytes32 internal constant ID = keccak256("pedri-framework-v1");
    string internal constant URI = "ipfs://bafyfakecid";
    bytes internal constant METADATA = hex"1234";

    // --- Core functions ---

    function setUp() public {
        registry = new FrameworkRegistry();
    }

    function test_register_storesRecord() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IFrameworkRegistry.FrameworkRegistered(ID, URI, alice, METADATA);
        registry.register(ID, URI, METADATA);

        IFrameworkRegistry.Framework memory f = registry.get(ID);
        assertEq(f.uri, URI);
        assertEq(f.metadata, METADATA);
        assertEq(f.author, alice);
        assertEq(f.registeredAt, uint64(block.timestamp));
        assertTrue(registry.isRegistered(ID));
    }

    function test_register_revertsOnDuplicate() public {
        registry.register(ID, URI, METADATA);
        vm.expectRevert(abi.encodeWithSelector(IFrameworkRegistry.FrameworkAlreadyRegistered.selector, ID));
        registry.register(ID, URI, METADATA);
    }

    function test_register_revertsOnZeroId() public {
        vm.expectRevert(IFrameworkRegistry.ZeroId.selector);
        registry.register(bytes32(0), URI, METADATA);
    }

    function test_register_revertsOnEmptyURI() public {
        vm.expectRevert(IFrameworkRegistry.EmptyURI.selector);
        registry.register(ID, "", METADATA);
    }

    function test_isRegistered_falseForUnknown() public view {
        assertFalse(registry.isRegistered(keccak256("nope")));
    }
}
