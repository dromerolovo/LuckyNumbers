import { } from "@nomiclabs/hardhat-waffle";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { MagicNumbersPublic } from "../typechain-types";
import { VRFCoordinatorV2Mock } from "../typechain-types/@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock";
import "./utils";
import { expect } from "chai";
import {time } from "@nomicfoundation/hardhat-network-helpers";
import { latest } from "@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { areAllElementsUnique } from "./utils";

describe("MagicNumberTesting test", async function() {

    let vrfMock : VRFCoordinatorV2Mock;
    let subscriptionId : number;
    let VRFaddress : string;

    let magicNumbersPublic : MagicNumbersPublic;
    let magicNumbersPublicAddress : string;
    let ticketPrice : BigNumber; 

    
    let ownerAddr : SignerWithAddress;
    let addr1 : SignerWithAddress;
    let addr2 : SignerWithAddress;
    let addr3 : SignerWithAddress;

    this.beforeAll(async function() {

        [ownerAddr, addr1, addr2, addr3] = await ethers.getSigners();

        const baseFee = ethers.utils.parseEther("0.1");
        const gasPriceLink = ethers.utils.parseEther("0.000000001");
        const fundSubscriptionAmount = ethers.utils.parseEther("10");

        const VRFMock = await ethers.getContractFactory("VRFCoordinatorV2Mock");
        vrfMock = await VRFMock.connect(ownerAddr).deploy(baseFee, gasPriceLink);
        await vrfMock.deployed();

        VRFaddress = vrfMock.address

        const transactionResult = await (await vrfMock.createSubscription()).wait();
        subscriptionId = await transactionResult.events![0].args!['subId'];
        await vrfMock.fundSubscription(subscriptionId, fundSubscriptionAmount);

        const MagicNumbersPublic = await ethers.getContractFactory("MagicNumbersPublic");
        ticketPrice = ethers.utils.parseEther("0.01");
        const numberCeiling = 79;
        const hexString = ethers.utils.hexlify(ethers.utils.randomBytes(32));
        magicNumbersPublic = await MagicNumbersPublic.connect(ownerAddr).deploy(subscriptionId, VRFaddress, hexString, ticketPrice, numberCeiling);
        await magicNumbersPublic.deployed();
        magicNumbersPublicAddress = magicNumbersPublic.address;

        const requiredBalance = ethers.utils.parseEther("5000");
        const transaction = await addr3.sendTransaction({
            to: magicNumbersPublic.address,
            value: requiredBalance,
            gasLimit: 300000
        });

        await transaction.wait();

        vrfMock.addConsumer(subscriptionId, magicNumbersPublicAddress);
    });

    describe("Test internal functions", function() {

        it("Trigger the lottery", async function() {
            const userSelectedNumbers = [1, 2, 3, 4, 5, 6, 7]
            await (await magicNumbersPublic.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await magicNumbersPublic.performUpkeep(ethers.utils.hexlify('0x'), {gasLimit: 6000000});
            var ticketsTop = magicNumbersPublic.getSelectedNumbers();
            expect((await ticketsTop).length).to.be.equal(20);
            for(var i = 0; i < 10; i++) {
                await (await magicNumbersPublic.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
                await time.setNextBlockTimestamp(await latest() + 1000);
                await magicNumbersPublic.performUpkeep(ethers.utils.hexlify('0x'), {gasLimit: 6000000});
                var tickets = magicNumbersPublic.getSelectedNumbers();
                expect(areAllElementsUnique(await tickets)).to.be.true;
                
            }
        });

        it("Displaying prizes", async function() {
            var userSelectedNumbers = [1, 2, 3, 4, 78]
            const transaction = await (await magicNumbersPublic.connect(ownerAddr).buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await magicNumbersPublic.connect(ownerAddr).setLottery(Array.from({length: 20}, (_, index) => index + 1), true);
            var ticketId = transaction.events![0].args![0][0].toNumber();
            var result = await magicNumbersPublic.connect(ownerAddr).calculatePrize(ticketId); 
            var prize = result[1].toString();
            var prizeWeight = result[0];
            expect(prize).to.be.equal("200000000000000000");  
            expect(prizeWeight).to.be.equal(10);
        });

        it("There are not right guesses", async function() {
            await time.setNextBlockTimestamp(await latest() + 1000);
            await magicNumbersPublic.performUpkeep(ethers.utils.hexlify('0x'));
            var userSelectedNumbers = [30, 31, 32, 33, 34];
            const transaction = await (await magicNumbersPublic.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await magicNumbersPublic.setLottery(Array.from({length: 20}, (_, index) => index + 1), true);
            var ticketId = transaction.events![0].args![0][0].toNumber();
            await expect(magicNumbersPublic.calculatePrize(ticketId)).to.be.revertedWith("There are not Right guesses. So there are no avilable claimable prizes");
        });

        it("ticketClaimabilityChecker: owner of the ticket", async function() {
            await time.setNextBlockTimestamp(await latest() + 1000);
            await magicNumbersPublic.performUpkeep(ethers.utils.hexlify('0x'));
            var userSelectedNumbers = [1, 2, 3, 4, 78];
            const transaction = await (await magicNumbersPublic.connect(ownerAddr).buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            var ticketId = transaction.events![0].args![0][0].toNumber();
            await magicNumbersPublic.setLottery(Array.from({length: 20}, (_, index) => index + 1), true);
            await expect(magicNumbersPublic.connect(addr1).claimPrize(ticketId)).to.be.revertedWith("Ticket prize should be claimed by the owner of the ticket");
        });

        it("ticketClaimabilityChecker: The lottery results have not been announced", async function() {
            await time.setNextBlockTimestamp(await latest() + 1000);
            await magicNumbersPublic.performUpkeep(ethers.utils.hexlify('0x'));
            var userSelectedNumbers = [1, 2, 3, 4, 78];
            const transaction = await (await magicNumbersPublic.connect(ownerAddr).buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            var ticketId = transaction.events![0].args![0][0].toNumber();
            await expect(magicNumbersPublic.claimPrize(ticketId)).to.be.revertedWith("The lottery results have not been announced.");
        });

        it("ticketClaimabilityChecker: Ticket has already been redeemed", async function() {
            await time.setNextBlockTimestamp(await latest() + 1000);
            await magicNumbersPublic.performUpkeep(ethers.utils.hexlify('0x'));
            var userSelectedNumbers = [1, 2, 3, 4, 78];
            const transaction = await (await magicNumbersPublic.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            var ticketId = transaction.events![0].args![0][0].toNumber();
            await magicNumbersPublic.setLottery(Array.from({length: 20}, (_, index) => index + 1), true);
            await magicNumbersPublic.claimPrize(ticketId);
            await expect(magicNumbersPublic.claimPrize(ticketId)).to.be.revertedWith("Ticket has already been redeemed");
        });

        it("Test Claim prize",async function() {
            await time.setNextBlockTimestamp(await latest() + 1000);
            await magicNumbersPublic.performUpkeep(ethers.utils.hexlify('0x'));
            var userSelectedNumbers = [1, 2, 3, 4, 78];
            const transaction = await (await magicNumbersPublic.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            var ticketId = transaction.events![0].args![0][0].toNumber();
            await magicNumbersPublic.setLottery(Array.from({length: 20}, (_, index) => index + 1), true);
            var preContractValue = await magicNumbersPublic.getContractValue();
            var preBalanceAddress = await ownerAddr.getBalance();
            var calculatePrize = (await magicNumbersPublic.calculatePrize(ticketId))[1];
            var transactionClaim = (await magicNumbersPublic.claimPrize(ticketId)).wait();
            var gasUsed = (await transactionClaim).gasUsed.mul((await transactionClaim).effectiveGasPrice);
            expect(await magicNumbersPublic.getContractValue()).to.be.equal(preContractValue.sub(calculatePrize));
            expect(await ownerAddr.getBalance()).to.be.equal(preBalanceAddress.add(calculatePrize).sub(gasUsed));
        });
    });
}); 
