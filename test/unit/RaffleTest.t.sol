//SPDX-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {console} from "forge-std/console.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperconfig;
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    event RaffleEntered(address indexed player);
    event WinnerPicker(address indexed winner);

    function setUp() public {
        DeployRaffle deployraffle = new DeployRaffle();
        (raffle, helperconfig) = deployraffle.deployContract();
        HelperConfig.NetworkConfig memory config = helperconfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;
        vm.deal(PLAYER, STARTING_BALANCE);
    }

    /* ///////////////////////////////////////////////////
                          enterRaffle()
    ///////////////////////////////////////////////////*/
    function testRaffleInitializesdInOpenState() public {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        //assertEq(uint256(raffle.getRaffleState()), 0);
    }

    function testRaffleRevertIfUDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER);
        //Act//Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle{value: 0.001 ether}();
        //raffle.enterRaffle(); //without sending money
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        //arrange
        vm.prank(PLAYER);
        //Acct
        raffle.enterRaffle{value: 0.02 ether}();
        //assert
        assertEq(PLAYER, raffle.getPlayer(0));
    }

    function testRaffleEnteredEmitsEvent() public {
        //arrange
        vm.prank(PLAYER);
        //Act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        //assert
        raffle.enterRaffle{value: entranceFee}();
    }

    //test: if (s_raffleState != RaffleState.OPEN) {
    //     revert Raffle__RaffleNotOpen();
    // }
    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        //arrange
        vm.prank(PLAYER); //have to call performUpkeep, becuase change the state to calculating
        raffle.enterRaffle{value: entranceFee}(); //make sure have balance and players
        vm.warp(block.timestamp + interval + 1); //make sure time passed
        vm.roll(block.number + 1);
        raffle.performUpkeep();
        //Act//Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /* ///////////////////////////////////////////////////
                           checkUpkeep
    ///////////////////////////////////////////////////*/

    function testCheckUpKeepReturnsFalseIfRaffleHasNoBalance() public {
        //arrange
        vm.warp(block.timestamp + interval + 1); //make sure time passed, but nobody enter the raffle
        vm.roll(block.number + 1);
        //Acc
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        //Asset
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleIsNotOpen() public {
        vm.prank(PLAYER); //have to call performUpkeep, becuase change the state to calculating
        raffle.enterRaffle{value: entranceFee}(); //make sure have balance and players
        vm.warp(block.timestamp + interval + 1); //make sure time passed
        vm.roll(block.number + 1);
        raffle.performUpkeep(); //should close the raffle_is_open
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfTimeIsNotPassed() public {
        vm.prank(PLAYER); //have to call performUpkeep, becuase change the state to calculating
        raffle.enterRaffle{value: entranceFee}(); //make sure have balance and players
        vm.warp(block.timestamp + (interval - 1));
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    /* ///////////////////////////////////////////////////
                        performUpkeep
    ///////////////////////////////////////////////////*/
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public raffleEntered {
        //Act/assert
        raffle.performUpkeep();
    }

    function testPerformUpKeepRevertsIfCHeckUpkeepIsFalse() public {
        //arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rstate = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance += entranceFee;
        numPlayers += 1;

        //act/assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle_UpkeepNotNeeded.selector, currentBalance, numPlayers, rstate)
        );
        raffle.performUpkeep();
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {
        //arrange

        //act
        vm.recordLogs(); //start tract logs
        raffle.performUpkeep();
        //all the emit events, all recorded stick in to entries array
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; //0 is from vrfcoordinator,ours are 1 after vrfcoordinator,0 is always for sth else
        //assert
        Raffle.RaffleState rafflestate = raffle.getRaffleState();
        assert(uint256(requestId) > 0); //type casting from uint256 to bytes32, and check if it is not 0
        assert(uint256(rafflestate) == 1);
    }

    /* ///////////////////////////////////////////////////
                    FullFillRandomWords
    ///////////////////////////////////////////////////*/
    modifier skipForkTest() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulFillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 requestId)
        public
        raffleEntered
        skipForkTest
    {
        //arrange//act//assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(requestId, address(raffle)); //make a random numer to test to revert
    }

    function testFulfilRandomWordsPicksAWinnerResetsAndSendTheMoney() public raffleEntered skipForkTest {
        //arrange
        uint256 addtionalEntrances = 3; //4 people total
        uint256 StartingIndex = 1;
        address expectedWinner = address(1);
        //player already entered
        for (uint256 i = StartingIndex; i < StartingIndex + addtionalEntrances; i++) {
            address newPlayer = address(uint160(i)); //address(1),address(2),address(3),address(4)
            hoax(newPlayer, 1 ether); //
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp(); //before performUpkeep();
        uint256 winnerStartingBalance = expectedWinner.balance;

        //act
        vm.recordLogs();
        raffle.performUpkeep();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        //pretend chainlink node
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        //assert
        address recentwinner = raffle.getRecentWinner();
        Raffle.RaffleState rafflestate = raffle.getRaffleState();
        uint256 winnerBalance = recentwinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (addtionalEntrances + 1);

        assert(expectedWinner == recentwinner);
        assert(uint256(rafflestate) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
