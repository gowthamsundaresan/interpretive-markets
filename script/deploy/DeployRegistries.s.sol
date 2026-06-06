// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {AttestedExecutorRegistry} from "../../src/core/AttestedExecutorRegistry.sol";
import {FrameworkRegistry} from "../../src/core/FrameworkRegistry.sol";
import {Market} from "../../src/core/Market.sol";
import {RitualSystem} from "../../src/core/RitualSystem.sol";

/// @dev Source .env then:
/// forge script script/deploy/DeployRegistries.s.sol:DeployRegistries \
///   --rpc-url $RITUAL_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
///   --sig "run(string)" -- "ritual"
contract DeployRegistries is Script {
    using stdJson for string;

    function run(string memory network) public {
        string memory configPath = string.concat("script/configs/", network, ".json");
        string memory config = vm.readFile(configPath);
        address owner = config.readAddress(".owner");

        vm.startBroadcast();

        FrameworkRegistry frameworks = new FrameworkRegistry();
        AttestedExecutorRegistry executors = new AttestedExecutorRegistry(owner == address(0) ? msg.sender : owner);
        RitualSystem ritualSystem = new RitualSystem();
        Market market = new Market(frameworks, ritualSystem);

        vm.stopBroadcast();

        string memory obj = "deployment";
        vm.serializeString(obj, "network", network);
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "frameworkRegistry", address(frameworks));
        vm.serializeAddress(obj, "attestedExecutorRegistry", address(executors));
        vm.serializeAddress(obj, "ritualSystem", address(ritualSystem));
        string memory out = vm.serializeAddress(obj, "market", address(market));

        string memory outPath = string.concat("script/outputs/", network, "/deployment.json");
        vm.writeJson(out, outPath);
    }
}
