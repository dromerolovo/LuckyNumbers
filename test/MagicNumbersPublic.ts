import { } from "@nomiclabs/hardhat-waffle";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { MagicNumbersPublic } from "../typechain-types";
import { VRFCoordinatorV2Mock } from "../typechain-types/@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock";
import "./utils";
import { expect } from "chai";

describe("MagicNumberTesting test", function() {

    let vrfMock : VRFCoordinatorV2Mock;
    let subscriptionId : number;
    let VRFaddress : string;

    let magicNumbersPublic : MagicNumbersPublic;
    let magicNumbersPublicAddress : string;
    let ticketPrice : BigNumber; 

    this.beforeAll(async function() {

        const baseFee = ethers.utils.parseEther("0.1");
        const gasPriceLink = ethers.utils.parseEther("0.000000001");
        const fundSubscriptionAmount = ethers.utils.parseEther("10");

        const VRFMock = await ethers.getContractFactory("VRFCoordinatorV2Mock");
        vrfMock = await VRFMock.deploy(baseFee, gasPriceLink);
        await vrfMock.deployed();

        VRFaddress = vrfMock.address

        const transactionResult = await (await vrfMock.createSubscription()).wait();
        subscriptionId = await transactionResult.events![0].args!['subId'];
        await vrfMock.fundSubscription(subscriptionId, fundSubscriptionAmount);

        const MagicNumbersPublic = await ethers.getContractFactory("MagicNumbersPublic");
        ticketPrice = ethers.utils.parseEther("0.01");
        const numberCeiling = 79;
        const hexString = ethers.utils.hexlify(ethers.utils.randomBytes(32));
        magicNumbersPublic = await MagicNumbersPublic.deploy(subscriptionId, VRFaddress, hexString, ticketPrice, numberCeiling);
        await magicNumbersPublic.deployed();
        magicNumbersPublicAddress = magicNumbersPublic.address;

        vrfMock.addConsumer(subscriptionId, magicNumbersPublicAddress);
    });

    describe("Test internal functions", function() {
        it("Displaying prizes", async function() {
            var userSelectedNumbers = [1, 2, 3, 4, 78]
            const transaction = await (await magicNumbersPublic.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await magicNumbersPublic.setLottery(Array.from({length: 20}, (_, index) => index + 1), true);
            var ticketId = transaction.events![0].args![0][0].toNumber();
            var result = await magicNumbersPublic.calculatePrize(ticketId); 
            var prize = result[1].toString();
            var prizeWeight = result[0];
            expect(prize).to.be.equal("200000000000000000");  
            expect(prizeWeight).to.be.equal(10);
        });

        it("Get correct prize transaction", async function() {
            
        }); 
    });
}); 
