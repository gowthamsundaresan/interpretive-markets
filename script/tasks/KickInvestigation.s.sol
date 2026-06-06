// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Market} from "../../src/core/Market.sol";

/// @dev Manual trigger for `Market.startInvestigation`. The operator service polls and calls
///      this via viem; this script exists for one-off manual kicks during Phase 3 testnet work.
///
/// Source .env then:
/// forge script script/tasks/KickInvestigation.s.sol:KickInvestigation \
///   --rpc-url $RITUAL_RPC_URL --broadcast --private-key $OPERATOR_PRIVATE_KEY \
///   --sig "run(string,uint256)" -- "ritual" <marketId>
contract KickInvestigation is Script {
    using stdJson for string;

    function run(string memory network, uint256 marketId) public {
        string memory deploymentPath = string.concat("script/outputs/", network, "/deployment.json");
        string memory deployment = vm.readFile(deploymentPath);
        address marketAddr = deployment.readAddress(".market");

        vm.startBroadcast();
        Market(marketAddr).startInvestigation(marketId);
        vm.stopBroadcast();
    }
}
