import { expect } from "chai";
import { ethers } from "hardhat";

import {Contract, BigNumber, Wallet} from "ethers";
import { formatEther } from "ethers/lib/utils";
import {MockProvider, deployContract} from 'ethereum-waffle';
import {createFixtureLoader} from 'ethereum-waffle';
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

describe("ClaimIDOPool", function () {
  const provider = new MockProvider();
  const [wallet] = provider.getWallets();

  const loadFixture = createFixtureLoader([wallet], provider);
  const etherUnit = BigNumber.from(10).pow(18);

  async function fixture([wallet]: Wallet[], _mockProvider: MockProvider) {
    const [owner, user1, user2, user3] = await ethers.getSigners();

    const ClaimIDOPool = await ethers.getContractFactory("ClaimIDOPool");
    const idoPool = await ClaimIDOPool.deploy();
    await idoPool.deployed();

    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    const tokenAAA = await ERC20Mock.deploy("AAA", "AAA" , owner.address, BigNumber.from(100000).mul(etherUnit));
    await tokenAAA.deployed();

    const tokenBBB = await ERC20Mock.deploy("BBB", "BBB" , owner.address, BigNumber.from(100000).mul(etherUnit));
    await tokenBBB.deployed();

    // console.log("wallet.address: ", wallet.address);
    console.log("tokenAAA.address: ", tokenAAA.address);
    console.log("idoPool.address: ", idoPool.address);
    console.log("owner.address: ", owner.address);
    console.log("user1.address: ", user1.address);
    console.log("user2.address: ", user2.address);
    console.log("user3.address: ", user3.address);

    // configure setting for ClaimIDOPool
    idoPool.connect(owner).setConfig(tokenAAA.address, 2);

    // have pool an inital amount 10000 AAA tokens
    await tokenAAA.connect(owner).transfer(idoPool.address, BigNumber.from(10000).mul(etherUnit));

    // tokenAAA approve user
    await tokenAAA.connect(user1).approve(idoPool.address, BigNumber.from(100000).mul(etherUnit))
    await tokenAAA.connect(user2).approve(idoPool.address, BigNumber.from(100000).mul(etherUnit))

    // have users own 2000 BUSD tokens
    // await tokenAAA.transfer(user1.address, BigNumber.from(2000).mul(etherUnit));
    // await tokenAAA.transfer(user2.address, BigNumber.from(2000).mul(etherUnit));
    const userTokenBalance1 = await tokenAAA.balanceOf(user1.address);
    const userTokenBalance2 = await tokenAAA.balanceOf(user2.address);
    const poolTokenBalance = await tokenAAA.balanceOf(idoPool.address);
    console.log("The amount of AAA that the user1 owns: ", formatEther(userTokenBalance1));
    console.log("The amount of AAA that the user2 owns: ", formatEther(userTokenBalance2));
    console.log("The amount of AAA that the Pool has: ", formatEther(poolTokenBalance));


    return {owner, user1, user2, user3, tokenAAA, tokenBBB, idoPool};
  }

  let owner: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress
  let user3: SignerWithAddress
  let tokenAAA: Contract
  let tokenBBB: Contract
  let idoPool: Contract

  beforeEach(async function() {
    const _fixture = await loadFixture(fixture);
    owner = _fixture.owner;
    user1 = _fixture.user1;
    user2 = _fixture.user2;
    user3 = _fixture.user3;
    tokenAAA = _fixture.tokenAAA;
    tokenBBB = _fixture.tokenBBB;
    idoPool = _fixture.idoPool;
  });

  describe("Testsuite 1 - verify basic operations of owner & users", function () {

    it("TC1 - owner cannot re-initalized IDO Pool", async function () {
      await expect(idoPool.connect(owner).setConfig(tokenAAA.address, 2))
        .to.be.revertedWith("Pool is already initialized");
    });

    it("TC2 - owner can set new token while normal users cannot", async function () {
      await expect(idoPool.connect(owner).setNewToken(tokenBBB.address)).to.emit(idoPool, 'NewTokenSet'); // check event EMIT
      expect (await idoPool.connect(owner).tokenAddress()).to.equal(tokenBBB.address);
      await idoPool.connect(owner).setNewToken(tokenAAA.address); // reset the token

      await expect(idoPool.connect(user1).setNewToken(tokenAAA.address))
        .to.be.revertedWith("Ownable: caller is not the owner"); 
    });

    it("TC3 - owner can set times for users to start claiming while normal users cannot", async function () {
      const currentBlock = await ethers.provider.getBlockNumber();
      const currentTime = (await ethers.provider.getBlock(currentBlock)).timestamp;
      const claimTime1 = currentTime + 86400;
      const claimTime2 = claimTime1 + 86400;

      // console.log(currentTime);
      // console.log(claimTime1);
      // console.log(claimTime2);
      
      await expect(idoPool.connect(user1).setClaimTime(claimTime1, 1))
        .to.be.revertedWith("Ownable: caller is not the owner");

      await expect(idoPool.connect(owner).setClaimTime(claimTime1, 1))
        .to.emit(idoPool, 'ClaimTimeSet');
      await expect(idoPool.connect(owner).setClaimTime(claimTime2, 2))
        .to.emit(idoPool, 'ClaimTimeSet');   
    });


    it("TC4 - owner can add/remove whitelist while normal users cannot", async function () {
      await idoPool.connect(owner).addWhitelistAddressesForAllRounds([user1.address, user2.address]);
      await idoPool.connect(owner).removeWhitelistAddressesForAllRounds([user1.address, user2.address]);

      await expect(idoPool.connect(user1).addWhitelistAddressesForAllRounds([user1.address, user2.address]))
        .to.be.revertedWith("Ownable: caller is not the owner");
      await expect(idoPool.connect(user2).removeWhitelistAddressesForAllRounds([user1.address, user2.address]))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("TC5 - owner can set quota for claiming while normal users cannot", async function () {
      const userList = [user1.address, user2.address];
      const quotaRound1 = [BigNumber.from(500).mul(etherUnit), BigNumber.from(1000).mul(etherUnit)];
      const quotaRound2 = [BigNumber.from(1000).mul(etherUnit), BigNumber.from(2000).mul(etherUnit)]

      await idoPool.connect(owner).setClaimQuota(userList, quotaRound1, 1);
      await idoPool.connect(owner).setClaimQuota(userList, quotaRound2, 2);   
      
      await expect(idoPool.connect(user1).setClaimQuota(userList, quotaRound1, 1))
        .to.be.revertedWith("Ownable: caller is not the owner");
      await expect(idoPool.connect(user2).setClaimQuota(userList, quotaRound2, 2))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("TC6 - user cannot claim if he hasn't been whitelisted", async function () {
      await expect(idoPool.connect(user3).claim(1)) // claim at round 1
        .to.be.revertedWith("You are not whitelisted or have already claimed token at this round");
    });

    it("TC7 - user cannot claim when the time hasn't come yet", async function () {
      // setup
      await idoPool.connect(owner).addWhitelistAddressesForRound([user1.address], 1);

      // test
      await expect(idoPool.connect(user1).claim(1)) // claim at round 1
        .to.be.revertedWith("Claiming of this round not enabled yet");

      // clear setup  
      await idoPool.connect(owner).removeWhitelistAddressesForRound([user1.address], 1);
    });
  
  });

  describe("Testsuite 2 - verify when users claim, transfering work properly ", function () {
    it ("TC1 - users claim at round 1", async function () {
      // setup
      await idoPool.connect(owner).addWhitelistAddressesForAllRounds([user1.address, user2.address]);
      await ethers.provider.send("hardhat_mine", ["0x15180"]);// fast-winding 1 day

      await expect(idoPool.connect(user1).claim(1))
        .to.emit(idoPool, 'Claim');

      await expect(idoPool.connect(user2).claim(1))
        .to.emit(idoPool, 'Claim');

      let balanceUser1 = await tokenAAA.balanceOf(user1.address);
      console.log("AAA balance of User1 after claim: ", formatEther(balanceUser1));
      let balanceUser2 = await tokenAAA.balanceOf(user2.address);
      console.log("AAA balance of User2 after claim: ", formatEther(balanceUser2));

      let balancePool = await tokenAAA.balanceOf(idoPool.address);
      console.log("AAA balance of Pool: ", formatEther(balancePool));

    });

    it ("TC2 - users claim at round 2", async function () {
      // setup
      await ethers.provider.send("hardhat_mine", ["0x15180"]);// fast-winding 1 day

      await expect(idoPool.connect(user1).claim(2))
        .to.emit(idoPool, 'Claim');

      await expect(idoPool.connect(user2).claim(2))
        .to.emit(idoPool, 'Claim');

      let balanceUser1 = await tokenAAA.balanceOf(user1.address);
      console.log("AAA balance of User1 after claim: ", formatEther(balanceUser1));
      let balanceUser2 = await tokenAAA.balanceOf(user2.address);
      console.log("AAA balance of User2 after claim: ", formatEther(balanceUser2));

      let balancePool = await tokenAAA.balanceOf(idoPool.address);
      console.log("AAA balance of Pool: ", formatEther(balancePool));

    });

    it("TC3 - user cannot claim twice in a round", async function () {
      await expect(idoPool.connect(user1).claim(1)) // claim at round 1
        .to.be.revertedWith("You are not whitelisted or have already claimed token at this round");
      await expect(idoPool.connect(user2).claim(2)) // claim at round 2
        .to.be.revertedWith("You are not whitelisted or have already claimed token at this round");
    });
  });


    

});
