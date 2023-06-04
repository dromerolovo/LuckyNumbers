import { VRFCoordinatorV2Mock } from "../typechain-types/@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock";
import { ethers, waffle } from "hardhat";


export function areAllElementsUnique(arr: any[]): boolean {
    return arr.length === new Set(arr).size;
  }

export function delay(ms: number) {
    return new Promise( resolve => setTimeout(resolve, ms) );
}

export async function initializeVrfMock(vrfMock : VRFCoordinatorV2Mock, VRFaddress : string, subscriptionId : number) {

  const baseFee = ethers.utils.parseEther("0.1");
  const gasPriceLink = ethers.utils.parseEther("0.000000001");
  const fundSubscriptionAmount = ethers.utils.parseEther("10");

  const VRFMock = await ethers.getContractFactory("VRFCoordinatorV2Mock");
  vrfMock = await VRFMock.deploy(baseFee, gasPriceLink);
  await vrfMock.deployed();

  VRFaddress = vrfMock.address;

  const transactionResult = await (await vrfMock.createSubscription()).wait();
  subscriptionId = await transactionResult.events![0].args!['subId'];
  await vrfMock.fundSubscription(subscriptionId, fundSubscriptionAmount);
  return [vrfMock, VRFaddress, subscriptionId];

} 