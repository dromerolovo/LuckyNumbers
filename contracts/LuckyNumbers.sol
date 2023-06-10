// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

import "../node_modules/hardhat/console.sol";

contract LuckyNumbers is VRFConsumerBaseV2, AutomationCompatible{
    VRFCoordinatorV2Interface immutable COORDINATOR;
    uint64 immutable s_subscriptionId;
    bytes32 immutable s_keyHash;
    uint32 constant CALLBACK_GAS_LIMIT = 1000000;
    uint16 constant REQUEST_CONFIRMATIONS = 3;
    // uint32 constant NUM_WORDS = 1;
    uint32 constant NUM_WORDS = 20;

    uint256[] private s_randomWords;
    uint256 private s_requestId;
    address s_owner;
    address payable s_opVault;

    event ReturnedRandomness(uint256 indexed requestId);

    constructor(uint64 subscriptionId, address vrfCoordinator, bytes32 keyHash, uint256 ticketPrice, 
        uint256 numberCeiling, address payable opVault, uint256 timeInterval
    ) VRFConsumerBaseV2(vrfCoordinator) {
        require(numberCeiling < 256, "Ceiling should be less than 256");
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_keyHash = keyHash;
        s_owner = msg.sender;
        s_opVault = opVault;
        s_interval = timeInterval;
        s_subscriptionId = subscriptionId;
        s_ticketPrice = ticketPrice;
        s_numberCeiling = numberCeiling;
        s_lastTimeStamp = block.timestamp;
        s_ticketCap = 10;
        s_lotteryCounter++;
        s_currentLottery = Lottery({
            lotteryId: s_lotteryCounter,
            selectedNumbers: new uint8[](0),
            resultsAnnounced: false
        });
        emit LotteryCreated(s_currentLottery.lotteryId);
        populatePrizeTable();
    }

    //TOP-LEVEL MODIFIERS / FUNCTIONS / VARIABLES

    receive() external payable {

    }

    modifier onlyOwner() {
        require(msg.sender == s_owner);
        _;
    }

    function getContractValue()  external view onlyOwner returns(uint) {
        return address(this).balance;
    }


    //VRF LOGIC

    function requestRandomWords() internal onlyOwner returns (uint256 requestId){
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
        // triggerLottery(s_randomWords[0]);
        triggerLotteryX(s_randomWords);
        delete currentLotteryTicketsId;
        s_lotteryCounter++;
        s_currentLottery = Lottery({
            lotteryId: s_lotteryCounter,
            selectedNumbers: new uint8[](0),
            resultsAnnounced: false
        });
        emit LotteryCreated(s_currentLottery.lotteryId);
        emit ReturnedRandomness(requestId);
    }

    // TICKETING AND GAME LOGIC

    uint256 public s_ticketPrice; 
    Lottery public s_currentLottery;
    uint256[] private currentLotteryTicketsId;
    mapping(uint256 => Lottery) public s_lotteries;
    mapping (address => Ticket[]) public s_tickets;
    mapping(uint256 => Ticket) public ticketsIndex;
    uint256 s_numberCeiling;
    uint256 private s_ticketCounter = 0;
    uint256 private s_lotteryCounter = 0;
    uint256 public s_ticketCap;
    uint8 public constant SELECTED_NUMBERS_UPPER_LIMIT_LOTTERY = 20;
    uint8 public constant SELECTED_NUMBERS_UPPER_LIMIT_USER = 10;
    //[hits or right guesses][selected numbers count] 
    uint32[11][11] private s_prizeTable;

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

    event TicketsBought(uint256[] ticketsId);
    event TicketCapModified(uint256 ticketCap);
    event TicketPriceModified(uint256 ticketPrice);
    event LotteryCreated(uint256 indexed lotteryId);
    event PrizeClaimed(uint256 indexed ticketId, uint256 prize);
    event LotteryTriggered(uint256 indexed lotteryId, uint8[] selectedNumbers);

    modifier ticketClaimabilityChecker(uint256 ticketId) {
        if(ticketsIndex[ticketId].owner != msg.sender) {
            revert("Ticket prize should be claimed by the owner of the ticket");
        }
        uint256 lotteryId = ticketsIndex[ticketId].lotteryId;
        if(s_lotteries[lotteryId].resultsAnnounced == false) {
            revert("The lottery results have not been announced.");
        }

        if(ticketsIndex[ticketId].isItRedeemed == true) {
            revert("Ticket has already been redeemed");
        }
        _;
    }

    modifier checkLotteryResultsAnnounced(uint256 ticketId) {
        require(ticketId <= s_ticketCounter, "The ticket has not been created.");
        uint256 lotteryId = ticketsIndex[ticketId].lotteryId;
        if(s_lotteries[lotteryId].resultsAnnounced == false) {
            revert("The lottery results have not been announced.");
        }
        _;
    }

    modifier ceilingCheck(uint8[] calldata selectedNumbers) {
        for(uint256 i = 0; i < selectedNumbers.length; i++) {
            require(selectedNumbers[i] <= s_numberCeiling, "Numbers must not exceed the ceiling");
        }
        _;
    }

    modifier uniqueArrayCheck(uint8[] calldata selectedNumbers) {
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

    function modifyTicketsCap(uint256 ticketCap)  external onlyOwner  {
        s_ticketCap = ticketCap;
        emit TicketCapModified(s_ticketCap);
    }

    function modifyTicketPrice(uint256 newPrice)  external onlyOwner {
        s_ticketPrice = newPrice;
        emit TicketPriceModified(s_ticketPrice);
    }

    function getTicketsBought() external view returns(Ticket[] memory) {
        Ticket[] memory ticketsMemory = s_tickets[msg.sender];
        return ticketsMemory;
    }

    function getTicket(uint256 ticketId) external view returns(Ticket memory) {
        Ticket memory ticketMemory = ticketsIndex[ticketId];
        return ticketMemory;
    }

    function claimPrize(uint256 ticketId) ticketClaimabilityChecker(ticketId) external virtual {
        (uint256 m, uint256 prizeInEth) = calculatePrize(ticketId);
        if(m == 0 || prizeInEth == 0) {
            revert("There are no claimable prize");
        }
        // This code block is intended as a failsafe and should ideally never be triggered ;)
        if(address(this).balance < prizeInEth) {
        prizeInEth = address(this).balance;
        }
        ticketsIndex[ticketId].isItRedeemed = true;
        payable (msg.sender).transfer(prizeInEth);
        emit PrizeClaimed(ticketId, prizeInEth);
    }

    function buyTicket(uint32 numTickets, uint8[] calldata selectedNumbers) 
        external 
        payable 
        virtual
        ceilingCheck(selectedNumbers) 
        uniqueArrayCheck(selectedNumbers)
    {
        require(msg.value >= s_ticketPrice * numTickets, "Insufficient Ether sent");
        require(numTickets < s_ticketCap, "Tickets bought must not exceed the max amount or cap");
        require(selectedNumbers.length <= SELECTED_NUMBERS_UPPER_LIMIT_USER, "Selected numbers must be equal or less than 10");
        require(s_currentLottery.resultsAnnounced == false, "The lottery should not be concluded");
        require(s_currentLottery.selectedNumbers.length == 0, "The lottery should not be concluded");

        

        uint256[] memory ticketsIds = new uint256[](numTickets);
        uint8[] memory selectedNumbersFixed = selectedNumbers;
        
        for(uint256 i = 0; i < numTickets; i++) {
            s_ticketCounter += 1;
            Ticket memory ticket = Ticket({
                ticketId: s_ticketCounter,
                isItRedeemed: false,
                lotteryId: s_currentLottery.lotteryId,
                selectedNumbers: selectedNumbersFixed,
                owner: msg.sender
            });
            s_tickets[msg.sender].push(ticket);
            currentLotteryTicketsId.push(ticket.ticketId);
            ticketsIds[i] = s_ticketCounter;
            ticketsIndex[s_ticketCounter] = ticket;
        } 
        uint operationsCoverage = msg.value * 2 / 100;
        s_opVault.transfer(operationsCoverage);       
        emit TicketsBought(ticketsIds);
    }

    function calculatePrize(uint256 ticketId) 
        public 
        view 
        virtual 
        checkLotteryResultsAnnounced(ticketId) 
        returns(uint32, uint256) 
    {
        uint selectedNumbersCount = ticketsIndex[ticketId].selectedNumbers.length;
        uint8 count = calculateRightGuesses(ticketId);
        uint32 multiplier = s_prizeTable[count][selectedNumbersCount];
        uint256 prizeInEth = s_ticketPrice  * uint256(multiplier);
        return (multiplier, prizeInEth);
    }

    function getSelectedNumbers() public view returns(uint8[] memory) {
        require(s_lotteryCounter > 1, "There are no previous results yet");
        return s_lotteries[s_lotteryCounter - 1].selectedNumbers;

    }

    function getSelectedNumbersId(uint256 lotteryId) public view returns(uint8[] memory) {
        if(lotteryId == 0) {
            revert("Empty Lottery");
        }
        
        if(s_lotteries[lotteryId].lotteryId == 0) {
            revert("This lottery has not been created yet");
        }

        return s_lotteries[lotteryId].selectedNumbers;
    }

    function calculateRightGuesses(uint256 ticketId) 
        public 
        view 
        virtual 
        checkLotteryResultsAnnounced(ticketId) 
        returns(uint8) 
    {
        uint8[] memory selectedNumbersUser = ticketsIndex[ticketId].selectedNumbers;
        uint8[] memory selectedNumbersLottery = s_lotteries[ticketsIndex[ticketId].lotteryId].selectedNumbers;
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

    function triggerLotteryX(uint256[] memory randomWords) internal virtual {
        uint8[] memory transitSelectedNumbers = new uint8[](20);
        bool repeated;
        //Lucky number 7 is arbitrary
        uint256 helperUint = 7777;
        uint256 helperCount = 0;
        for(uint256 i = 0; i < SELECTED_NUMBERS_UPPER_LIMIT_LOTTERY; i++) {
            helperCount++;
            uint256 number;
            number = (uint256(keccak256(abi.encodePacked(randomWords[i], i, block.timestamp, block.prevrandao ))) % s_numberCeiling) + 1;
            if(repeated) {
                helperUint + i;
                uint256 helper = uint256(keccak256(abi.encodePacked(block.timestamp, helperUint, block.prevrandao, helperCount)));
                number = (uint256(keccak256(abi.encodePacked(randomWords[i], i, block.timestamp, block.prevrandao, helper ))) % s_numberCeiling) + 1;
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
        setLottery(transitSelectedNumbers); 
        emit LotteryTriggered(s_currentLottery.lotteryId, transitSelectedNumbers);
    }
    // function triggerLottery(uint256 randomWord) internal virtual {
    //     uint8[] memory transitSelectedNumbers = new uint8[](20);
    //     bool repeated;
    //     //Lucky number 7 is arbitrary.
    //     uint256 helperUint = 7777;
    //     uint256 helperCount = 0;
    //     for(uint256 i = 0; i < SELECTED_NUMBERS_UPPER_LIMIT_LOTTERY; i++) {
    //         helperCount++;
    //         uint256 number;
    //         number = (uint256(keccak256(abi.encodePacked(randomWord, i, block.timestamp, block.prevrandao ))) % s_numberCeiling) + 1;
    //         if(repeated) {
    //             helperUint + i;
    //             uint256 helper = uint256(keccak256(abi.encodePacked(block.timestamp, helperUint, block.prevrandao, helperCount)));
    //             number = (uint256(keccak256(abi.encodePacked(randomWord, i, block.timestamp, block.prevrandao, helper ))) % s_numberCeiling) + 1;
    //         } 
    //         uint8 numberCast = uint8(number);
    //         if(!isNumberSelected(numberCast, transitSelectedNumbers)) {
    //             transitSelectedNumbers[i] = uint8(number);
    //             repeated = false;
    //         } else {
    //             repeated = true;
    //             i--;
    //         }
    //     }
    //     setLottery(transitSelectedNumbers, true);
    //     s_lotteries[s_currentLottery.lotteryId] = s_currentLottery;
    //     emit LotteryTriggered(s_currentLottery.lotteryId, transitSelectedNumbers);
    // }

    function setLottery(uint8[] memory selectedNumbers) internal virtual {
        s_currentLottery.selectedNumbers = selectedNumbers;
        s_currentLottery.resultsAnnounced = true;
        s_lotteries[s_currentLottery.lotteryId] = s_currentLottery;
    }

    function isNumberSelected(uint8 number, uint8[] memory transitSelectedNumbers) internal pure returns(bool) {
        for(uint i = 0; i < transitSelectedNumbers.length; i++) {
            if(transitSelectedNumbers[i] == number) {
                return true;
            }
        }

        return false;
    }

    function populatePrizeTable() private {
        s_prizeTable[1][1] = 3;
        s_prizeTable[1][2] = 1;

        s_prizeTable[2][2] = 6;
        s_prizeTable[2][3] = 3;
        s_prizeTable[2][4] = 1;
        s_prizeTable[2][5] = 1;

        s_prizeTable[3][3] = 25;
        s_prizeTable[3][4] = 5;
        s_prizeTable[3][5] = 2;
        s_prizeTable[3][6] = 1;
        s_prizeTable[3][7] = 1;

        s_prizeTable[4][4] = 120;
        s_prizeTable[4][5] = 10;
        s_prizeTable[4][6] = 8;
        s_prizeTable[4][7] = 4;
        s_prizeTable[4][8] = 2;
        s_prizeTable[4][9] = 1;
        s_prizeTable[4][10] = 1;

        s_prizeTable[5][5] = 380;
        s_prizeTable[5][6] = 55;
        s_prizeTable[5][7] = 20;
        s_prizeTable[5][8] = 10;
        s_prizeTable[5][9] = 5;
        s_prizeTable[5][10] = 2;

        s_prizeTable[6][6] = 2000;
        s_prizeTable[6][7] = 150;
        s_prizeTable[6][8] = 50;
        s_prizeTable[6][9] = 30;
        s_prizeTable[6][10] = 20;

        s_prizeTable[7][7] = 5000;
        s_prizeTable[7][8] = 1000;
        s_prizeTable[7][9] = 200;
        s_prizeTable[7][10] = 50;

        s_prizeTable[8][8] = 20000;
        s_prizeTable[8][9] = 4000;
        s_prizeTable[8][10] = 500;

        s_prizeTable[9][9] = 50000;
        s_prizeTable[9][10] = 10000;

        s_prizeTable[10][10] = 100000;
    }

    //AUTOMATION LOGIC
    uint256 public s_interval;
    uint256 public s_lastTimeStamp;

    event ChangeInterval(uint256 interval);

    function changeInterval(uint256 interval) external onlyOwner {
        s_interval = interval;
    }

    function checkUpkeep(bytes calldata)
        external 
        view 
        override 
        returns(bool upkeepNeeded, bytes memory)
    {
        bool lotteryTicketsCheck = currentLotteryTicketsId.length > 0;
        bool timestampCheck = (block.timestamp - s_lastTimeStamp) > s_interval;
        upkeepNeeded = lotteryTicketsCheck && timestampCheck;
    }

    function performUpkeep(bytes calldata) 
        external 
        override 
    {
        bool lotteryTicketsCheck = currentLotteryTicketsId.length > 0;
        bool timestampCheck = (block.timestamp - s_lastTimeStamp) > s_interval;
        bool check = lotteryTicketsCheck && timestampCheck;

        if(check) {
            s_lastTimeStamp = block.timestamp;
            requestRandomWords();
        } else {
            revert("Not ready to trigger a lottery");
        }
    }

    ///DEBUGGING: USE ONLY FOR TESTING ON LOCAL ENVIROMENT,
    function DEBUG_ONLY_setLottery(uint8[] memory selectedNumbers) public virtual {
        s_currentLottery.selectedNumbers = selectedNumbers;
        s_currentLottery.resultsAnnounced = true;
        s_lotteries[s_currentLottery.lotteryId] = s_currentLottery;
        delete currentLotteryTicketsId;
        s_lotteryCounter++;
        s_currentLottery = Lottery({
            lotteryId: s_lotteryCounter,
            selectedNumbers: new uint8[](0),
            resultsAnnounced: false
        });
        emit LotteryCreated(s_currentLottery.lotteryId);
    }

    function DEBUG_ONLY_performUpkeep(bytes calldata, uint8[] memory seletedNumbers) external {
        bool lotteryTicketsCheck = currentLotteryTicketsId.length > 0;
        bool timestampCheck = (block.timestamp - s_lastTimeStamp) > s_interval;
        bool check = lotteryTicketsCheck && timestampCheck;

        if(check) {
            s_lastTimeStamp = block.timestamp;
            DEBUG_ONLY_setLottery(seletedNumbers);
        } else {
            revert("Not ready to trigger a lottery");
        }
    }
}