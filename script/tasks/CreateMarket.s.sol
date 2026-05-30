// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Market} from "../../src/core/Market.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";

/// @dev Source .env then:
/// forge script script/tasks/CreateMarket.s.sol:CreateMarket \
///   --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
///   --sig "run(string,string,bytes32,bytes,bytes32,bytes32,uint64,bytes32)" -- \
///   "sepolia" <question> <frameworkId> <dataSourceSpec> <modelId> <promptTemplateHash> <resolutionTime> <judgeImageDigest>
contract CreateMarket is Script {
    using stdJson for string;

    function run(
        string memory network,
        string memory question,
        bytes32 frameworkId,
        bytes memory dataSourceSpec,
        bytes32 modelId,
        bytes32 promptTemplateHash,
        uint64 resolutionTime,
        bytes32 judgeImageDigest
    ) public {
        string memory deploymentPath = string.concat("script/outputs/", network, "/deployment.json");
        string memory deployment = vm.readFile(deploymentPath);
        address marketAddr = deployment.readAddress(".market");

        IMarket.MarketInit memory params = IMarket.MarketInit({
            question: question,
            frameworkId: frameworkId,
            dataSourceSpec: dataSourceSpec,
            modelId: modelId,
            promptTemplateHash: promptTemplateHash,
            resolutionTime: resolutionTime,
            judgeImageDigest: judgeImageDigest
        });

        vm.startBroadcast();
        uint256 marketId = Market(marketAddr).createMarket(params);
        vm.stopBroadcast();

        console2.log("marketId:", marketId);
    }
}
