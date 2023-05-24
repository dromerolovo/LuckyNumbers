// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

contract MagicNumbers is VRFConsumerBaseV2, AutomationCompatibleInterface{
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
        s_subscriptionId = subscriptionId;
        ticketPrice = _ticketPrice;
        numberCeiling = numberCeiling_;
        lastTimeStamp = block.timestamp;
        ticketCap = 10;
        currentRaffle = Raffle({
            rafleId: 1,
            selectedNumbers: new uint8[](0),
            resultsAnnounced: false
        });
        raffles.push(currentRaffle);
    }

    //TOP-LEVEL MODIFIERS / FUNCTIONS / VARIABLES

    modifier onlyOwner() {
        require(msg.sender == s_owner);
        _;
    }

    function getContractValue() onlyOwner external view returns(uint) {
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
        emit ReturnedRandomness(randomWords);


    }

    // TICKETING AND GAME LOGIC

    uint256 public ticketPrice; 
    Raffle public currentRaffle;
    Raffle[] public raffles;
    uint256[] private currentRaffleTicketsId;
    mapping (address => Ticket[]) public tickets;
    mapping(uint256 => uint8[]) public selectedNumbers;
    uint256 numberCeiling;
    uint256 private ticketCounter = 0;
    uint256 private raffleCounter = 0;
    uint256 public ticketCap;
    uint8 public constant selectednUmbersUpperLimit = 10;
    uint8 public constant totalNumbers = 79;

    event TicketBought(uint256[] ticket);
    event TicketCapModified(uint256 ticketCap);
    event TicketPriceModified(uint256 ticketPrice);
    event RaffleCreated(Raffle raffle);
    event LogMessage(string message);

    struct Raffle {
        uint256 rafleId;
        uint8[] selectedNumbers;
        bool resultsAnnounced;
    }

    struct Ticket {
        uint256 ticketId;
        bool isItRedeemed;
        uint256 raffleId;
        uint8[] selectedNumbers;
    }

    function modifyTicketsCap(uint256 _ticketCap) onlyOwner external virtual {
        ticketCap = _ticketCap;
        emit TicketCapModified(ticketCap);
    }

    function modifyTicketPrice(uint256 newPrice) onlyOwner external virtual {
        ticketPrice = newPrice;
        emit TicketPriceModified(ticketPrice);
    }

    function buyTicket(uint32 numTickets, uint8[] calldata selectedNumbers_) 
        ceilingCheck(selectedNumbers_) 
        uniqueArrayCheck(selectedNumbers_)
        external payable virtual{
        require(msg.value >= ticketPrice * numTickets, "Insufficient Ether sent");
        require(numTickets < ticketCap, "Tickets bought must not exceed the max amount or cap");
        require(selectedNumbers_.length <= selectednUmbersUpperLimit, "Selected numbers must be equal or less than 10");
        require(currentRaffle.resultsAnnounced == false, "The raffle should not be concluded");
        require(currentRaffle.selectedNumbers.length == 0, "The raffle should not be concluded");

        uint256[] memory ticketsIds = new uint256[](numTickets);
        
        for(uint256 i = 0; i < numTickets; i++) {
            ticketCounter += 1;
            Ticket memory ticket = Ticket({
                ticketId: ticketCounter,
                isItRedeemed: false,
                raffleId: currentRaffle.rafleId,
                selectedNumbers: selectedNumbers_
            });
            tickets[msg.sender].push(ticket);
            currentRaffleTicketsId.push(ticket.ticketId);
            ticketsIds[i] = ticketCounter;
            selectedNumbers[ticketCounter] = selectedNumbers_;
        }        
        emit TicketBought(ticketsIds);
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

    function getSelectedNumbersTicket(uint256 id) external view returns(uint8[] memory) {
        // uint8[] selectedNumbers_ = new uint8[](selectedNumbers[id].length);
        // for(uint i = 0; i < selectedNumbers[id].length; i++ ) {
        //     selectedNumbers_[i] = selectedNumbers[id];
        // }
        return selectedNumbers[id];
    }

    function raffleTrigger() internal virtual {

    }

    function randomize(uint256 randomWord) internal virtual {
        uint8[] memory transitSelectedNumbers = new uint8[](10);
        for(uint256 i = 0; i < selectednUmbersUpperLimit; i++) {
            uint256 number = (uint256(keccak256(abi.encode(randomWord, i))) % totalNumbers) + 1;
            uint8 numberCast = uint8(number);
            emit LogMessage(numberCast);
            if(!isNumberSelected(numberCast, transitSelectedNumbers)) {
                transitSelectedNumbers[i] = uint8(number);
            } else {
                i--;
            }
            
        }
        currentRaffle.selectedNumbers = transitSelectedNumbers;
        currentRaffle.resultsAnnounced = true;
    }

    function isNumberSelected(uint8 number, uint8[] memory transitSelectedNumbers) pure internal returns(bool) {
        for(uint i = 0; i < transitSelectedNumbers.length; i++) {
            if(transitSelectedNumbers[i] == number) {
                return true;
            }
        }

        return false;
    }

    function getSelectedNumbers() public view returns(uint8[] memory) {
        return currentRaffle.selectedNumbers;
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
        bool raffleTicketsCheck = currentRaffleTicketsId.length > 0;
        // bool timestampCheck = (block.timestamp - lastTimeStamp) > interval;
        upkeepNeeded = raffleTicketsCheck /*&& timestampCheck*/;
        return (upkeepNeeded,abi.encode("0x"));
    }

    function performUpkeep(bytes calldata) /*chainlinkAddress*/ external override {

        bool raffleTicketsCheck = currentRaffleTicketsId.length > 0;
        // bool timestampCheck = (block.timestamp - lastTimeStamp) > interval;
        bool upkeepNeeded = raffleTicketsCheck /*&& timestampCheck*/;

        if(upkeepNeeded) {
            lastTimeStamp = block.timestamp;
            uint256 requestId = requestRandomWords();
            //This shouldn't be called on testnet, only locally
            COORDINATOR_INSTANCE.fulfillRandomWords(requestId, address(this));
            randomize(s_randomWords[0]);
            delete currentRaffleTicketsId;

        } else {
            revert("Not ready to trigger a raffle");
        }
    }

}