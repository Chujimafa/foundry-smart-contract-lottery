//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "lib/forge-std/src/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/interaction.s.sol";

contract DeployRaffle is Script {
    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperconfig = new HelperConfig();
        //local-> deploy mocks
        //sepolia ->get sepolia config
        HelperConfig.NetworkConfig memory config = helperconfig.getConfig();
        if (config.subscriptionId == 0) {
            //creat subscription
            CreateSubscription createScription = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) =
                createScription.createSubscription(config.vrfCoordinator, config.account);

            //fund it
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
        }

        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        //add consumer after deploy the contract
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(config.vrfCoordinator, config.subscriptionId, address(raffle), config.account);
        //donnot need broadcast because in addConsumer function add broadcast
        return (raffle, helperconfig);
    }

    function run() public {
        deployContract();
    }
}
