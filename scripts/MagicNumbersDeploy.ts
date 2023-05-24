import { BigNumber } from "ethers";
import { ethers } from "hardhat";

async function main() {

  const baseFee = ethers.utils.parseEther("0.1");
  const gasPriceLink = ethers.utils.parseEther("0.000000001");
  const fundSubscriptionAmount = ethers.utils.parseEther("1");

  const VRFMock = await ethers.getContractFactory("VRFCoordinatorV2Mock");
  const MagicNumbers = ethers.getContractFactory("MagicNumbers");

  const vrfMock = await VRFMock.deploy(baseFee, gasPriceLink);
  await vrfMock.deployed();

  const transactionResult = await vrfMock.createSubscription();
  const transactionResultAwaited = await transactionResult.wait();
  const subscriptionId = transactionResultAwaited.events![0].args!['subId'] as BigNumber;

  (await vrfMock.fundSubscription(subscriptionId, fundSubscriptionAmount)).wait();

  vrfMock.getSubscription(1)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});