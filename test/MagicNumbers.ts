import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { assert } from "console";
import helpers from "hardhat";
import { ethers, waffle } from "hardhat";
import { MagicNumbers, MagicNumbers__factory, VRFCoordinatorV2Mock__factory } from "../typechain-types";
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



describe("MagicNumbers Test", async function() {

    let vrfMock : VRFCoordinatorV2Mock;
    let subscriptionId : number;
    let VRFaddress : string;

    let magicNumbers : MagicNumbers;
    let magicNumbersAddress : string;
    let ticketPrice : BigNumber; 

    
    let defaultAccount : SignerWithAddress;


    this.beforeEach(async function() {

        
        let [defaultAccountPre] = await ethers.getSigners();
        defaultAccount = defaultAccountPre;

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

        const MagicNumbers = await ethers.getContractFactory("MagicNumbers");
        ticketPrice = ethers.utils.parseEther("0.01");
        const numberCeiling = 79;
        const hexString = ethers.utils.hexlify(ethers.utils.randomBytes(32));

        magicNumbers = await MagicNumbers.deploy(subscriptionId, VRFaddress, hexString, ticketPrice, numberCeiling);
        await magicNumbers.deployed();
        magicNumbersAddress = magicNumbers.address;

        vrfMock.addConsumer(subscriptionId, magicNumbersAddress);
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



    
    describe("MagicNumbers deployment", function() {
        const userSelectedNumbers = [1, 2, 3, 4, 5, 6, 7]

        it("The deployment is correct", async function() {
            expect(ethers.utils.isAddress(magicNumbersAddress)).to.be.true;
        });

        it("Ticket buy action works correctly", async function() {
            const signerAddress = await ethers.provider.getSigner().getAddress();
            const transaction = await (await magicNumbers.buyTicket(2, userSelectedNumbers, {value: ticketPrice.mul(2)})).wait();
            const ticketsIds = transaction.events![0].args![0]
            for(var i = 0; i < ticketsIds.length; i++) {
                var id = ticketsIds[i].toNumber();
                var ticket = await magicNumbers.getTicket(id);
                expect(JSON.stringify(ticket.selectedNumbers)).to.equal(JSON.stringify(userSelectedNumbers));
            }

        })
        it("Trigger the lottery", async function() {
            await (await magicNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await time.setNextBlockTimestamp(await latest() + 1000);
            await magicNumbers.performUpkeep(ethers.utils.hexlify('0x'), {gasLimit: 6000000});
            var ticketsTop = magicNumbers.getSelectedNumbers();
            expect((await ticketsTop).length).to.be.equal(20);
            for(var i = 0; i < 10; i++) {
                await (await magicNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
                await time.setNextBlockTimestamp(await latest() + 1000);
                await magicNumbers.performUpkeep(ethers.utils.hexlify('0x'), {gasLimit: 6000000});
                var tickets = magicNumbers.getSelectedNumbers();
                expect(areAllElementsUnique(await tickets)).to.be.true;
                
            }
        });

        it("Get tickets bought", async function() {
            var firstArray = [1, 2, 3, 4, 5];
            var secondArray = [1, 5, 6, 7, 9];
            var thirdArray = [2, 8, 9, 7, 10];
            var arrays = [firstArray, secondArray, thirdArray];
            for(var i = 0; i < arrays.length; i++) {
                await magicNumbers.buyTicket(1, arrays[i], {value: ticketPrice});
            }

            var ticketsBought = await magicNumbers.getTicketsBought()
            expect(ticketsBought.length).to.be.equal(3);
            expect(JSON.stringify(ticketsBought[0].selectedNumbers)).to.be.equal(JSON.stringify(firstArray));

        })
    });
});

