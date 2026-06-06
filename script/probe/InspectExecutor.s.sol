// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";

/// @title InspectExecutor — read TEEServiceRegistry for valid executors (Phase 0.5 probe)
/// @notice Calls `getServicesByCapability(capability, checkValidity)` on the genesis-deployed
///         TEEServiceRegistry and prints every field that's attested. This is the empirical answer
///         to "what does the attestation actually bind."
///
/// Usage:
///   export PATH="$HOME/.foundry/bin:$PATH"
///   forge script script/probe/InspectExecutor.s.sol:InspectExecutor \
///       --rpc-url https://rpc.ritualfoundation.org \
///       --sig "run(uint8)" -- 0
///
/// `capability = 0` is HTTP_CALL (the Sovereign Agent uses this).
contract InspectExecutor is Script {
    address public constant TEE_SERVICE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;

    struct TEENode {
        address paymentAddress;
        address teeAddress;
        uint8 teeType;
        bytes publicKey;
        string endpoint;
        bytes32 certPubKeyHash;
        uint8 capability;
    }

    struct TEEService {
        TEENode node;
        bool isValid;
        bytes32 workloadId;
    }

    function run(uint8 capability) public view {
        (bool ok, bytes memory ret) = TEE_SERVICE_REGISTRY.staticcall(
            abi.encodeWithSignature("getServicesByCapability(uint8,bool)", capability, true)
        );
        require(ok, "registry staticcall failed");

        TEEService[] memory services = abi.decode(ret, (TEEService[]));

        console2.log("--- TEEServiceRegistry.getServicesByCapability ---");
        console2.log("registry:", TEE_SERVICE_REGISTRY);
        console2.log("capability:", capability);
        console2.log("count:", services.length);

        for (uint256 i = 0; i < services.length; i++) {
            TEEService memory s = services[i];
            console2.log("");
            console2.log("--- service", i, "---");
            console2.log("isValid:", s.isValid);
            console2.log("workloadId:");
            console2.logBytes32(s.workloadId);
            console2.log("paymentAddress:", s.node.paymentAddress);
            console2.log("teeAddress:", s.node.teeAddress);
            console2.log("teeType:", s.node.teeType);
            console2.log("capability (field):", s.node.capability);
            console2.log("endpoint:", s.node.endpoint);
            console2.log("certPubKeyHash:");
            console2.logBytes32(s.node.certPubKeyHash);
            console2.log("publicKey:");
            console2.logBytes(s.node.publicKey);
        }
    }
}
