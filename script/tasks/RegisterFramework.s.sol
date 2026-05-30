// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {FrameworkRegistry} from "../../src/core/FrameworkRegistry.sol";

/// @dev Invoked by manager/src/manual/registerFramework.ts. Source .env then:
/// forge script script/tasks/RegisterFramework.s.sol:RegisterFramework \
///   --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
///   --sig "run(string,bytes32,string,bytes)" -- "sepolia" <id> <uri> <metadata>
contract RegisterFramework is Script {
    using stdJson for string;

    function run(string memory network, bytes32 id, string memory uri, bytes memory metadata) public {
        string memory deploymentPath = string.concat("script/outputs/", network, "/deployment.json");
        string memory deployment = vm.readFile(deploymentPath);
        address registryAddr = deployment.readAddress(".frameworkRegistry");

        vm.startBroadcast();
        FrameworkRegistry(registryAddr).register(id, uri, metadata);
        vm.stopBroadcast();
    }
}
