// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Market} from "../../src/core/Market.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";

/// @dev Reads the market-creation parameters from a JSON file so the structured fields
///      (sourceAllowlist, dossierSubjects) survive without exploding the --sig surface.
///
/// JSON shape (see script/tasks/market.example.json):
/// {
///   "question": "...",
///   "frameworkId": "0x...",
///   "sourceAllowlist": ["https://..."],
///   "dossierPathPrefix": "dossier://",
///   "dossierSubjects": ["haaland", "mbappe"],
///   "resolutionTime": 1762000000,
///   "cliType": 0,
///   "model": "zai-org/GLM-4.7-FP8",
///   "maxTurns": 20,
///   "maxTokens": 4096,
///   "callbackGasLimit": 5000000,
///   "investigationTtl": 1000
/// }
///
/// Source .env then:
/// forge script script/tasks/CreateMarket.s.sol:CreateMarket \
///   --rpc-url $RITUAL_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
///   --sig "run(string,string)" -- "ritual" "script/tasks/market.example.json"
contract CreateMarket is Script {
    using stdJson for string;

    function run(string memory network, string memory marketConfigPath) public {
        string memory deploymentPath = string.concat("script/outputs/", network, "/deployment.json");
        string memory deployment = vm.readFile(deploymentPath);
        address marketAddr = deployment.readAddress(".market");

        string memory cfg = vm.readFile(marketConfigPath);
        IMarket.MarketInit memory params = IMarket.MarketInit({
            question: cfg.readString(".question"),
            frameworkId: cfg.readBytes32(".frameworkId"),
            sourceAllowlist: cfg.readStringArray(".sourceAllowlist"),
            dossierPathPrefix: cfg.readString(".dossierPathPrefix"),
            dossierSubjects: cfg.readStringArray(".dossierSubjects"),
            resolutionTime: uint64(cfg.readUint(".resolutionTime")),
            cliType: uint16(cfg.readUint(".cliType")),
            model: cfg.readString(".model"),
            maxTurns: uint16(cfg.readUint(".maxTurns")),
            maxTokens: uint32(cfg.readUint(".maxTokens")),
            callbackGasLimit: cfg.readUint(".callbackGasLimit"),
            investigationTtl: cfg.readUint(".investigationTtl")
        });

        vm.startBroadcast();
        uint256 marketId = Market(marketAddr).createMarket(params);
        vm.stopBroadcast();

        console2.log("marketId:", marketId);
    }
}
