// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {AttestedExecutorRegistry} from "../../src/core/AttestedExecutorRegistry.sol";

/// @dev Source .env then:
/// forge script script/tasks/RegisterExecutor.s.sol:RegisterExecutor \
///   --rpc-url $RITUAL_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
///   --sig "run(string,address)" -- "ritual" <executor>
contract RegisterExecutor is Script {
    using stdJson for string;

    function run(string memory network, address executor) public {
        string memory deploymentPath = string.concat("script/outputs/", network, "/deployment.json");
        string memory deployment = vm.readFile(deploymentPath);
        address registryAddr = deployment.readAddress(".attestedExecutorRegistry");

        vm.startBroadcast();
        AttestedExecutorRegistry(registryAddr).register(executor);
        vm.stopBroadcast();
    }
}
