// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {JudgeRegistry} from "../../src/core/JudgeRegistry.sol";

/// @dev Source .env then:
/// forge script script/tasks/RegisterJudge.s.sol:RegisterJudge \
///   --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
///   --sig "run(string,bytes32,address)" -- "sepolia" <imageDigest> <signer>
contract RegisterJudge is Script {
    using stdJson for string;

    function run(string memory network, bytes32 imageDigest, address signer) public {
        string memory deploymentPath = string.concat("script/outputs/", network, "/deployment.json");
        string memory deployment = vm.readFile(deploymentPath);
        address registryAddr = deployment.readAddress(".judgeRegistry");

        vm.startBroadcast();
        JudgeRegistry(registryAddr).register(imageDigest, signer);
        vm.stopBroadcast();
    }
}
