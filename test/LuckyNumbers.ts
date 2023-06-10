import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { assert } from "console";
import helpers from "hardhat";
import { ethers, waffle } from "hardhat";
import { LuckyNumbers, LuckyNumbers__factory, VRFCoordinatorV2Mock__factory } from "../typechain-types";
import { VRFCoordinatorV2Mock } from "../typechain-types/@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock";
import { exec } from "child_process";
import { BigNumber, providers } from "ethers";
import "./utils";
import { areAllElementsUnique, delay} from "./utils";
import {mine, takeSnapshot, time } from "@nomicfoundation/hardhat-network-helpers";
import { getNetwork } from "@ethersproject/providers";
import {} from "@nomiclabs/hardhat-waffle";
import { deployMockContract, MockProvider } from "ethereum-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { increase, increaseTo, latest, latestBlock } from "@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time";
import path from "path";
import fs from "fs";



describe("LuckyNumbers Test", async function() {

    let vrfMock : VRFCoordinatorV2Mock;
    let subscriptionId : number;
    let VRFaddress : string;

    let luckyNumbers : LuckyNumbers;
    let luckyNumbersAddress : string;
    let ticketPrice : BigNumber; 

    
    let defaultAccount : SignerWithAddress;
    let addr1 : SignerWithAddress;
    let addr2 : SignerWithAddress;
    let addr3 : SignerWithAddress;

    this.beforeEach(async function() {

        [defaultAccount, addr1, addr2, addr3] = await ethers.getSigners();

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

        const LuckyNumbers = await ethers.getContractFactory("LuckyNumbers");
        ticketPrice = ethers.utils.parseEther("0.01");
        const numberCeiling = 79;
        const hexString = ethers.utils.hexlify(ethers.utils.randomBytes(32));

        luckyNumbers = await LuckyNumbers.deploy(subscriptionId, VRFaddress, hexString, ticketPrice, numberCeiling, addr1.address, 900);
        await luckyNumbers.deployed();
        luckyNumbersAddress = luckyNumbers.address;

        vrfMock.addConsumer(subscriptionId, luckyNumbersAddress);
    });
    
    describe("VRFCoordinatorV2Mock deployment", function() {
        it("Subscription id should be created", async function() {
            const subscription = await vrfMock.getSubscription(subscriptionId);
            expect(subscription).to.exist;
        });
    
        it("subscription id should be 1", async function() {
            expect(subscriptionId).to.equal(1);
        });
    
        it("Subscription should be funded", async function() {
            const subscription = await vrfMock.getSubscription(subscriptionId);
            expect(subscription.balance.toString()).to.equal("10000000000000000000");
        });
    });



    
    describe("LuckyNumbers deployment", function() {
        const userSelectedNumbers = [1, 2, 3, 4, 5, 6, 7]

        it("The deployment is correct", async function() {
            expect(ethers.utils.isAddress(luckyNumbersAddress)).to.be.true;
        });

        it("Ticket buy action works correctly", async function() {
            const signerAddress = await ethers.provider.getSigner().getAddress();
            const transaction = await (await luckyNumbers.buyTicket(2, userSelectedNumbers, {value: ticketPrice.mul(2)})).wait();
            const ticketsIds = transaction.events![0].args![0]
            for(var i = 0; i < ticketsIds.length; i++) {
                var id = ticketsIds[i].toNumber();
                var ticket = await luckyNumbers.getTicket(id);
                expect(JSON.stringify(ticket.selectedNumbers)).to.equal(JSON.stringify(userSelectedNumbers));
            }

        })
        it("Get tickets bought", async function() {
            var firstArray = [1, 2, 3, 4, 5];
            var secondArray = [1, 5, 6, 7, 9];
            var thirdArray = [2, 8, 9, 7, 10];
            var arrays = [firstArray, secondArray, thirdArray];
            for(var i = 0; i < arrays.length; i++) {
                await luckyNumbers.buyTicket(1, arrays[i], {value: ticketPrice});
            }

            var ticketsBought = await luckyNumbers.getTicketsBought()
            expect(ticketsBought.length).to.be.equal(3);
            expect(JSON.stringify(ticketsBought[0].selectedNumbers)).to.be.equal(JSON.stringify(firstArray));

        })

        it("Check Upkeep", async function() {
            console.log(await luckyNumbers.s_interval());
            await time.setNextBlockTimestamp(await latest() + 1500);
            await luckyNumbers.buyTicket(1, userSelectedNumbers, {value: ticketPrice});
            await time.setNextBlockTimestamp(await latest() + 1500);
            console.log(await luckyNumbers.s_interval());
            var upkeep = (await luckyNumbers.checkUpkeep(ethers.utils.hexlify('0x')))[0];
            console.log(await luckyNumbers.s_interval());
            expect(upkeep).to.be.equal(true);

        });
    });

    describe("Lottery Testing Module", async function() {
        const userSelectedNumbers = [1, 2, 3, 4, 5, 6, 7];
        const lotterySelectedNumbers = Array.from({length: 20}, (_, index) => index + 1);
        it("Trigger the lottery", async function() {
            await (await luckyNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await luckyNumbers.DEBUG_ONLY_performUpkeep(ethers.utils.hexlify('0x'), lotterySelectedNumbers , {gasLimit: 6000000});
            var ticketsTop = luckyNumbers.getSelectedNumbers();
            expect((await ticketsTop).length).to.be.equal(20);
            for(var i = 0; i < 10; i++) {
                await (await luckyNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
                await time.setNextBlockTimestamp(await latest() + 1000);
                await luckyNumbers.performUpkeep(ethers.utils.hexlify('0x'), {gasLimit: 6000000});
                var tickets = luckyNumbers.getSelectedNumbers();
                expect(areAllElementsUnique(await tickets)).to.be.true;
            }
        });

        it("Check Results Announced", async function() {
            await (await luckyNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await luckyNumbers.DEBUG_ONLY_performUpkeep(ethers.utils.hexlify('0x'), lotterySelectedNumbers , {gasLimit: 6000000});
            var firstLottery = await luckyNumbers.s_lotteries(1);
            expect(firstLottery.resultsAnnounced).to.be.equal(true);
            var secondLotteryPre = await luckyNumbers.s_lotteries(2);
            expect(secondLotteryPre.resultsAnnounced).to.be.equal(false);
            await (await luckyNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await luckyNumbers.DEBUG_ONLY_performUpkeep(ethers.utils.hexlify('0x'), lotterySelectedNumbers , {gasLimit: 6000000});
            var secondLotteryPost = await luckyNumbers.s_lotteries(2);
            var thirdLotter = await luckyNumbers.s_lotteries(3);
            expect(secondLotteryPost.resultsAnnounced).to.be.equal(true);
            expect(thirdLotter.resultsAnnounced).to.be.equal(false);
        });

        it("Get Selected Numbers Id", async function() {
            await (await luckyNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await luckyNumbers.DEBUG_ONLY_performUpkeep(ethers.utils.hexlify('0x'), lotterySelectedNumbers , {gasLimit: 6000000});
            await expect(luckyNumbers.getSelectedNumbersId(0)).revertedWith("Empty Lottery");
            expect(JSON.stringify(await  luckyNumbers.getSelectedNumbersId(1))).to.be.equal(JSON.stringify(lotterySelectedNumbers));
            await expect(luckyNumbers.getSelectedNumbersId(4)).revertedWith("This lottery has not been created yet");
        });


    });

    describe("Ticket module", async function() {
        const userSelectedNumbers = [1, 2, 3, 4, 5, 6, 7];
        const lotterySelectedNumbers = Array.from({length: 20}, (_, index) => index + 1);

        it("Displaying prizes", async function() {
            var userSelectedNumbers = [1, 2, 3, 4, 78]
            const transaction = await (await luckyNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await luckyNumbers.DEBUG_ONLY_performUpkeep(ethers.utils.hexlify('0x'), lotterySelectedNumbers);
            var ticketId = transaction.events![0].args![0][0].toNumber();
            var result = await luckyNumbers.calculatePrize(ticketId); 
            var prize = result[1].toString();
            var prizeWeight = result[0];
            expect(prize).to.be.equal("100000000000000000");  
            expect(prizeWeight).to.be.equal(10);
        });

        it("There are not right guesses", async function() {
            var userSelectedNumbers = [30, 31, 32, 33, 34];
            const transaction = await (await luckyNumbers.buyTicket(1 , userSelectedNumbers, {value: ticketPrice})).wait();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await luckyNumbers.DEBUG_ONLY_performUpkeep(ethers.utils.hexlify('0x'), lotterySelectedNumbers);
            var ticketId = transaction.events![0].args![0][0].toNumber();
            expect((await luckyNumbers.calculatePrize(ticketId))[1].toNumber()).to.be.equal(0);
        });

        it("ticketClaimabilityChecker: owner of the ticket", async function() {
            const transaction = await (await luckyNumbers.connect(defaultAccount).buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            var ticketId = transaction.events![0].args![0][0].toNumber();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await luckyNumbers.DEBUG_ONLY_performUpkeep(ethers.utils.hexlify('0x'), lotterySelectedNumbers);
            await expect(luckyNumbers.connect(addr1).claimPrize(ticketId)).to.be.revertedWith("Ticket prize should be claimed by the owner of the ticket");
        });

        it("ticketClaimabilityChecker: The lottery results have not been announced", async function() {
            const transaction = await (await luckyNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await time.setNextBlockTimestamp(await latest() + 1000);
            var ticketId = transaction.events![0].args![0][0].toNumber();
            await expect(luckyNumbers.claimPrize(ticketId)).to.be.revertedWith("The lottery results have not been announced.");
        });

        it("ticketClaimabilityChecker: Ticket has already been redeemed", async function() {
            const transaction = await (await luckyNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            var ticketId = transaction.events![0].args![0][0].toNumber();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await luckyNumbers.DEBUG_ONLY_performUpkeep(ethers.utils.hexlify('0x'), lotterySelectedNumbers);
            await luckyNumbers.claimPrize(ticketId);
            await expect(luckyNumbers.claimPrize(ticketId)).to.be.revertedWith("Ticket has already been redeemed");
        });


        it("Test Claim prize",async function() {


            const requiredBalance = ethers.utils.parseEther("5000");
            const transactionX = await addr3.sendTransaction({
                to: luckyNumbers.address,
                value: requiredBalance,
                gasLimit: 300000
            });
            await transactionX.wait();

            var userSelectedNumbers = [1, 2, 3, 4, 78];
            const transaction = await (await luckyNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            var ticketId = transaction.events![0].args![0][0].toNumber();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await luckyNumbers.DEBUG_ONLY_performUpkeep(ethers.utils.hexlify('0x'), lotterySelectedNumbers);
            var preContractValue = await luckyNumbers.getContractValue();
            var preBalanceAddress = await defaultAccount.getBalance();
            var calculatePrize = (await luckyNumbers.calculatePrize(ticketId))[1];
            var transactionClaim = (await luckyNumbers.claimPrize(ticketId)).wait();
            var gasUsed = (await transactionClaim).gasUsed.mul((await transactionClaim).effectiveGasPrice);
            expect(await luckyNumbers.getContractValue()).to.be.equal(preContractValue.sub(calculatePrize));
            expect(await defaultAccount.getBalance()).to.be.equal(preBalanceAddress.add(calculatePrize).sub(gasUsed));
        });
    });
});

