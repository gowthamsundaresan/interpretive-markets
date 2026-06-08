// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Market} from "../../src/core/Market.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";

/// @dev Manual trigger for `Market.startInvestigation`. The operator service polls and calls
///      this via viem; this script exists for one-off manual kicks during Phase 3 testnet work.
///
/// Source .env then:
/// forge script script/tasks/KickInvestigation.s.sol:KickInvestigation \
///   --rpc-url $RITUAL_RPC_URL --broadcast --private-key $OPERATOR_PRIVATE_KEY \
///   --sig "run(string,uint256,address,bytes)" -- "ritual" <marketId> <executor> <encryptedSecrets>
///
/// The operator must produce `encryptedSecrets` off-chain by ECIES-encrypting a JSON object
/// containing `LLM_PROVIDER` + the provider API key against the executor's `node.publicKey`
/// from `TEEServiceRegistry.getServicesByCapability(0, true)`. See `ritual-dapp-skills/skills/
/// ritual-dapp-secrets/SKILL.md` for the canonical encryption setup.
contract KickInvestigation is Script {
    using stdJson for string;

    function run(string memory network, uint256 marketId, address executor, bytes calldata encryptedSecrets) public {
        string memory deploymentPath = string.concat("script/outputs/", network, "/deployment.json");
        string memory deployment = vm.readFile(deploymentPath);
        address marketAddr = deployment.readAddress(".market");

        IMarket.SovereignSubmissionParams memory params = IMarket.SovereignSubmissionParams({
            executor: executor,
            encryptedSecrets: encryptedSecrets,
            userPublicKey: hex"",
            pollIntervalBlocks: 5,
            maxPollBlock: 6000,
            maxFeePerGas: 1_000_000_000,
            maxPriorityFeePerGas: 100_000_000
        });

        vm.startBroadcast();
        Market(marketAddr).startInvestigation(marketId, params);
        vm.stopBroadcast();
    }
}
