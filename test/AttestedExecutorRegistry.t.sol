// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AttestedExecutorRegistry} from "../src/core/AttestedExecutorRegistry.sol";
import {IAttestedExecutorRegistry} from "../src/interfaces/IAttestedExecutorRegistry.sol";

contract AttestedExecutorRegistryTest is Test {
    // --- Types & state ---

    AttestedExecutorRegistry internal registry;
    address internal owner;
    address internal stranger;
    address internal executor;

    // --- Core functions ---

    function setUp() public {
        owner = makeAddr("owner");
        stranger = makeAddr("stranger");
        executor = makeAddr("executor");
        registry = new AttestedExecutorRegistry(owner);
    }

    function test_register_storesRecord() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IAttestedExecutorRegistry.ExecutorRegistered(executor);
        registry.register(executor);

        IAttestedExecutorRegistry.Executor memory e = registry.get(executor);
        assertTrue(e.enabled);
        assertEq(e.registeredAt, uint64(block.timestamp));
        assertTrue(registry.isAttested(executor));
    }

    function test_register_revertsOnNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        registry.register(executor);
    }

    function test_register_revertsOnDuplicate() public {
        vm.startPrank(owner);
        registry.register(executor);
        vm.expectRevert(abi.encodeWithSelector(IAttestedExecutorRegistry.ExecutorAlreadyRegistered.selector, executor));
        registry.register(executor);
        vm.stopPrank();
    }

    function test_register_revertsOnZeroExecutor() public {
        vm.prank(owner);
        vm.expectRevert(IAttestedExecutorRegistry.ZeroExecutor.selector);
        registry.register(address(0));
    }

    function test_setEnabled_togglesAttestation() public {
        vm.startPrank(owner);
        registry.register(executor);
        registry.setEnabled(executor, false);
        vm.stopPrank();

        assertFalse(registry.get(executor).enabled);
        assertFalse(registry.isAttested(executor));
    }

    function test_setEnabled_revertsOnUnregistered() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IAttestedExecutorRegistry.ExecutorNotRegistered.selector, executor));
        registry.setEnabled(executor, false);
    }

    function test_isAttested_falseForUnregistered() public view {
        assertFalse(registry.isAttested(stranger));
    }
}
