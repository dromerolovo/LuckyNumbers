import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { assert } from "console";
import helpers from "hardhat";
import { ethers } from "hardhat";
import { MagicNumbers, MagicNumbers__factory, VRFCoordinatorV2Mock__factory } from "../typechain-types";
import { VRFCoordinatorV2Mock } from "../typechain-types/contracts/VRFMock.sol";
import { exec } from "child_process";
import { BigNumber } from "ethers";
import "./utils";
import { areAllElementsUnique, delay } from "./utils";
import {mine, takeSnapshot, time } from "@nomicfoundation/hardhat-network-helpers";
import { getNetwork } from "@ethersproject/providers";
import {} from "@nomiclabs/hardhat-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

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
            const transaction = await (await magicNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            const ticketsIds = transaction.events![0].args![0];
            let count : number = 1;
            for(let i in ticketsIds) {
                expect((ticketsIds[i] as BigNumber).toNumber()).to.equal(count);
                expect(JSON.stringify(await magicNumbers.getSelectedNumbersTicket(ticketsIds[i]))).to.equal(JSON.stringify(userSelectedNumbers));
                count++;
            }
        })
        it("Trigger the lottery", async function() {
            await (await magicNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
            await magicNumbers.performUpkeep(ethers.utils.hexlify('0x'), {gasLimit: 6000000});
            var ticketsTop = magicNumbers.getSelectedNumbers();
            expect((await ticketsTop).length).to.be.equal(10);
            for(var i = 0; i < 10; i++) {
                await (await magicNumbers.buyTicket(1 ,userSelectedNumbers, {value: ticketPrice})).wait();
                await magicNumbers.performUpkeep(ethers.utils.hexlify('0x'), {gasLimit: 6000000});
                var tickets = magicNumbers.getSelectedNumbers();
                expect(areAllElementsUnique(await tickets)).to.be.true;
                
            }
        });
    });
});

