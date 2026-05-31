// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {FrameworkRegistry} from "../../src/core/FrameworkRegistry.sol";
import {JudgeRegistry} from "../../src/core/JudgeRegistry.sol";
import {Market} from "../../src/core/Market.sol";

/// @dev Source .env then:
/// forge script script/deploy/DeployRegistries.s.sol:DeployRegistries \
///   --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
///   --sig "run(string)" -- "sepolia"
contract DeployRegistries is Script {
    using stdJson for string;

    function run(string memory network) public {
        string memory configPath = string.concat("script/configs/", network, ".json");
        string memory config = vm.readFile(configPath);
        address owner = config.readAddress(".owner");

        vm.startBroadcast();

        FrameworkRegistry frameworks = new FrameworkRegistry();
        JudgeRegistry judges = new JudgeRegistry(owner == address(0) ? msg.sender : owner);
        Market market = new Market(frameworks, judges);

        vm.stopBroadcast();

        string memory obj = "deployment";
        vm.serializeString(obj, "network", network);
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "frameworkRegistry", address(frameworks));
        vm.serializeAddress(obj, "judgeRegistry", address(judges));
        string memory out = vm.serializeAddress(obj, "market", address(market));

        string memory outPath = string.concat("script/outputs/", network, "/deployment.json");
        vm.writeJson(out, outPath);
    }
}
