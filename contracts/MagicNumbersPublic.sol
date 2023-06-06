// SPDX-License-Identifier: MIT

//Replace internal with public everythere except for the case of the function fulfillRandomWords.
// Move the triggerLottery function to performUpkeep, also all the side effects. 
// Use setLottery directly to set the selectedNumbers.
// Remove chainlinkAddress modifier

//COPY THE CONTRACT BELOW THIS LINE:
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

pragma solidity ^0.8.9;

import './MagicNumbers.sol';
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "hardhat/console.sol";

contract MagicNumbersPublic is VRFConsumerBaseV2, AutomationCompatibleInterface{
    VRFCoordinatorV2Interface immutable COORDINATOR;
    VRFCoordinatorV2Mock immutable COORDINATOR_INSTANCE;

    uint64 immutable s_subscriptionId;
    bytes32 immutable s_keyHash;
    uint32 constant CALLBACK_GAS_LIMIT = 1000000;
    uint16 constant REQUEST_CONFIRMATIONS = 3;
    uint32 constant NUM_WORDS = 1;

    uint256[] public s_randomWords;
    uint256 public s_requestId;
    address s_owner;

    event ReturnedRandomness(uint256[] randomWords);

    constructor(uint64 subscriptionId, address vrfCoordinator, bytes32 keyHash, uint256 _ticketPrice, 
        uint256 numberCeiling_
    ) VRFConsumerBaseV2(vrfCoordinator) {
        require(numberCeiling < 256, "Ceiling should be less than 256");
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        COORDINATOR_INSTANCE = VRFCoordinatorV2Mock(vrfCoordinator);
        s_keyHash = keyHash;
        s_owner = msg.sender;
        interval = 900; //15 minutes in Unix timestamp
        s_subscriptionId = subscriptionId;
        ticketPrice = _ticketPrice;
        numberCeiling = numberCeiling_;
        lastTimeStamp = block.timestamp;
        ticketCap = 10;
        currentLottery = Lottery({
            lotteryId: 0,
            selectedNumbers: new uint8[](0),
            resultsAnnounced: false
        });
        populatePrizeTable();
    }

    //TOP-LEVEL MODIFIERS / FUNCTIONS / VARIABLES

    receive() external payable {

    }

    modifier onlyOwner() {
        require(msg.sender == s_owner);
        _;
    }

    function getContractValue() onlyOwner external view returns(uint) {
        return address(this).balance;
    }

    //VRF LOGIC

    function requestRandomWords() public onlyOwner returns (uint256 requestId){
        s_requestId = COORDINATOR.requestRandomWords(
            s_keyHash,
            s_subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );

        return s_requestId;
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;
        emit ReturnedRandomness(randomWords);


    }

    // TICKETING AND GAME LOGIC

    uint256 public ticketPrice; 
    Lottery public currentLottery;
    uint256[] private currentLotteryTicketsId;
    mapping(uint256 => Lottery) public lotteries;
    mapping (address => Ticket[]) public tickets;
    mapping(uint256 => Ticket) public ticketsIndex;
    uint256 numberCeiling;
    uint256 private ticketCounter = 0;
    uint256 private lotteryCounter = 0;
    uint256 public ticketCap;
    uint8 public constant selectedNumbersUpperLimitLottery = 20;
    uint8 public constant selectedNumbersUpperLimitUser = 10;
    uint8 public constant totalNumbers = 79;

    //[hits or right guesses][selected numbers count] 
    uint32[11][11] private prizeTable;

    event TicketBought(uint256[] ticket);
    event TicketCapModified(uint256 ticketCap);
    event TicketPriceModified(uint256 ticketPrice);
    event LotteryCreated(Lottery lottery);
    event LogMessage(string message);

    struct Lottery {
        uint256 lotteryId;
        uint8[] selectedNumbers;
        bool resultsAnnounced;
    }

    struct Ticket {
        uint256 ticketId;
        bool isItRedeemed;
        uint256 lotteryId;
        uint8[] selectedNumbers;
        address owner;
    }

    function populatePrizeTable() private {
        prizeTable[1][1] = 3;
        prizeTable[1][2] = 1;

        prizeTable[2][2] = 6;
        prizeTable[2][3] = 3;
        prizeTable[2][4] = 1;
        prizeTable[2][5] = 1;

        prizeTable[3][3] = 25;
        prizeTable[3][4] = 5;
        prizeTable[3][5] = 2;
        prizeTable[3][6] = 1;
        prizeTable[3][7] = 1;

        prizeTable[4][4] = 120;
        prizeTable[4][5] = 10;
        prizeTable[4][6] = 8;
        prizeTable[4][7] = 4;
        prizeTable[4][8] = 2;
        prizeTable[4][9] = 1;
        prizeTable[4][10] = 1;

        prizeTable[5][5] = 380;
        prizeTable[5][6] = 55;
        prizeTable[5][7] = 20;
        prizeTable[5][8] = 10;
        prizeTable[5][9] = 5;
        prizeTable[5][10] = 2;

        prizeTable[6][6] = 2000;
        prizeTable[6][7] = 150;
        prizeTable[6][8] = 50;
        prizeTable[6][9] = 30;
        prizeTable[6][10] = 20;

        prizeTable[7][7] = 5000;
        prizeTable[7][8] = 1000;
        prizeTable[7][9] = 200;
        prizeTable[7][10] = 50;

        prizeTable[8][8] = 20000;
        prizeTable[8][9] = 4000;
        prizeTable[8][10] = 500;

        prizeTable[9][9] = 50000;
        prizeTable[9][10] = 10000;

        prizeTable[10][10] = 100000;
    }

    function modifyTicketsCap(uint256 _ticketCap) onlyOwner external virtual {
        ticketCap = _ticketCap;
        emit TicketCapModified(ticketCap);
    }

    function modifyTicketPrice(uint256 newPrice) onlyOwner external virtual {
        ticketPrice = newPrice;
        emit TicketPriceModified(ticketPrice);
    }

    function calculateRightGuesses(uint256 ticketId) public view returns(uint8) {
        uint8[] memory selectedNumbersUser = ticketsIndex[ticketId].selectedNumbers;
        uint8[] memory selectedNumbersLottery = lotteries[ticketsIndex[ticketId].lotteryId].selectedNumbers;
        bool[80] memory set;

        for(uint8 i = 0; i < selectedNumbersUser.length; i++) {
            set[selectedNumbersUser[i]] = true;
        }

        uint8 rightGuesses = 0;
        for(uint8 i = 0; i < selectedNumbersLottery.length; i++) {
            if(set[selectedNumbersLottery[i]]) {
                rightGuesses++;
            }
        }

        return rightGuesses;
    }

    function calculatePrize(uint256 ticketId) public view returns(uint32, uint256) {
        uint selectedNumbersCount = ticketsIndex[ticketId].selectedNumbers.length;
        uint8 count = calculateRightGuesses(ticketId);
        if(count == 0) {
            revert("There are not Right guesses. So there are no avilable claimable prizes");
        }
        uint32 multiplier = prizeTable[count][selectedNumbersCount];
        uint256 prizeInEth = 20000000000000000  * uint256(multiplier);
        return (multiplier, prizeInEth);
    }

    function claimPrize(uint256 ticketId) ticketClaimabilityChecker(ticketId) external {
         (uint256 m, uint256 prizeInEth) = calculatePrize(ticketId);
         // This code block is intended as a failsafe and should ideally never be triggered ;)
         if(address(this).balance < prizeInEth) {
            prizeInEth = address(this).balance;
         }
         ticketsIndex[ticketId].isItRedeemed = true;
         payable (msg.sender).transfer(prizeInEth);
    }

    modifier ticketClaimabilityChecker(uint256 ticketId) virtual {
        if(ticketsIndex[ticketId].owner != msg.sender) {
            revert("Ticket prize should be claimed by the owner of the ticket");
        }
        uint256 lotteryId = ticketsIndex[ticketId].lotteryId;
        if(lotteries[lotteryId].resultsAnnounced == false) {
            revert("The lottery results have not been announced.");
        }

        if(ticketsIndex[ticketId].isItRedeemed == true) {
            revert("Ticket has already been redeemed");
        }
        _;
    }

    function buyTicket(uint32 numTickets, uint8[] calldata selectedNumbers_) 
        ceilingCheck(selectedNumbers_) 
        uniqueArrayCheck(selectedNumbers_)
        external payable virtual{
        require(msg.value >= ticketPrice * numTickets, "Insufficient Ether sent");
        require(numTickets < ticketCap, "Tickets bought must not exceed the max amount or cap");
        require(selectedNumbers_.length <= selectedNumbersUpperLimitUser, "Selected numbers must be equal or less than 10");
        require(currentLottery.resultsAnnounced == false, "The lottery should not be concluded");
        require(currentLottery.selectedNumbers.length == 0, "The lottery should not be concluded");

        uint256[] memory ticketsIds = new uint256[](numTickets);
        uint8[] memory selectedNumbersFixed = selectedNumbers_;
        
        for(uint256 i = 0; i < numTickets; i++) {
            ticketCounter += 1;
            Ticket memory ticket = Ticket({
                ticketId: ticketCounter,
                isItRedeemed: false,
                lotteryId: currentLottery.lotteryId,
                selectedNumbers: selectedNumbersFixed,
                owner: msg.sender
            });
            tickets[msg.sender].push(ticket);
            currentLotteryTicketsId.push(ticket.ticketId);
            ticketsIds[i] = ticketCounter;
            ticketsIndex[ticketCounter] = ticket;
        }        
        emit TicketBought(ticketsIds);
    }

    function getTicketsBought() external view returns(Ticket[] memory) {
        Ticket[] memory ticketsMemory = tickets[msg.sender];
        return ticketsMemory;
    }

    function getTicket(uint256 ticketId) external view returns(Ticket memory) {
        Ticket memory ticketMemory = ticketsIndex[ticketId];
        return ticketMemory;
    }

    modifier ceilingCheck(uint8[] calldata selectedNumbers) virtual {
        for(uint256 i = 0; i < selectedNumbers.length; i++) {
            require(selectedNumbers[i] <= numberCeiling, "Numbers must not exceed the ceiling");
        }
        _;
    }

    modifier uniqueArrayCheck(uint8[] calldata selectedNumbers) virtual {
        uint length = selectedNumbers.length;
        bool[] memory encountered = new bool[](length);
        for(uint i = 0; i < length; i++) {
            for(uint j = i + 1; j < length; j++) {
                if(selectedNumbers[i] == selectedNumbers[j]) {
                    revert("Values should be unique");
                }
            }
        }
        _;
    }

    function triggerLottery(uint256 randomWord) public virtual {
        uint8[] memory transitSelectedNumbers = new uint8[](20);
        bool repeated;
        //Lucky number 7 is arbitrary.
        uint256 helperUint = 7777;
        uint256 helperCount = 0;
        for(uint256 i = 0; i < selectedNumbersUpperLimitLottery; i++) {
            helperCount++;
            uint256 number;
            number = (uint256(keccak256(abi.encodePacked(randomWord, i, block.timestamp, block.prevrandao ))) % totalNumbers) + 1;
            if(repeated) {
                helperUint + i;
                uint256 helper = uint256(keccak256(abi.encodePacked(block.timestamp, helperUint, block.prevrandao, helperCount)));
                number = (uint256(keccak256(abi.encodePacked(randomWord, i, block.timestamp, block.prevrandao, helper ))) % totalNumbers) + 1;
            } 
            uint8 numberCast = uint8(number);
            if(!isNumberSelected(numberCast, transitSelectedNumbers)) {
                transitSelectedNumbers[i] = uint8(number);
                repeated = false;
            } else {
                repeated = true;
                i--;
            }
        }
        setLottery(transitSelectedNumbers, true);
    }

    function setLottery(uint8[] memory selectedNumbers_, bool result) public virtual {
        currentLottery.selectedNumbers = selectedNumbers_;
        currentLottery.resultsAnnounced = result;
        lotteries[currentLottery.lotteryId] = currentLottery;
    }

    function isNumberSelected(uint8 number, uint8[] memory transitSelectedNumbers) pure public returns(bool) {
        for(uint i = 0; i < transitSelectedNumbers.length; i++) {
            if(transitSelectedNumbers[i] == number) {
                return true;
            }
        }

        return false;
    }

    function getSelectedNumbers() public view returns(uint8[] memory) {
        require(lotteryCounter > 0, "There are not previous results yet");
        if(lotteryCounter == 1) {
            return lotteries[0].selectedNumbers;
        } else {
            return lotteries[lotteryCounter - 2].selectedNumbers;
        }
    }

    //AUTOMATION LOGIC

    address public automationAddress;
    uint256 public interval;
    uint256 public lastTimeStamp;

    modifier chainlinkAddress() {
        require(msg.sender == automationAddress);
        _;
    }

    function changeAddress(address automationAddress_) onlyOwner external {
        automationAddress = automationAddress_;
    }

    function changeInterval(uint256 interval_) onlyOwner external {
        interval = interval_;
    }

    function checkUpkeep(bytes calldata)
        /*chainlinkAddress*/
        external 
        view 
        override 
        returns(bool upkeepNeeded, bytes memory)
    {
        bool lotteryTicketsCheck = currentLotteryTicketsId.length > 0;
        bool timestampCheck = (block.timestamp - lastTimeStamp) > interval;
        upkeepNeeded = lotteryTicketsCheck && timestampCheck;
        return (upkeepNeeded,abi.encode("0x"));
    }

    function performUpkeep(bytes calldata) /*chainlinkAddress*/ external override {

        bool lotteryTicketsCheck = currentLotteryTicketsId.length > 0;
        bool timestampCheck = (block.timestamp - lastTimeStamp) > interval;
        bool upkeepNeeded = lotteryTicketsCheck && timestampCheck;

        if(upkeepNeeded) {
            lastTimeStamp = block.timestamp;
            uint256 requestId = requestRandomWords();
            //This shouldn't be called on testnet, only locally
            COORDINATOR_INSTANCE.fulfillRandomWords(requestId, address(this));
            triggerLottery(s_randomWords[0]);
            delete currentLotteryTicketsId;
            lotteryCounter++;
            currentLottery = Lottery({
                lotteryId: lotteryCounter,
                selectedNumbers: new uint8[](0),
                resultsAnnounced: false
            });
            

        } else {
            revert("Not ready to trigger a lottery");
        }
    }

}