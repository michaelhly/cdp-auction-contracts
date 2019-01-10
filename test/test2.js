const Web3 = require("web3");
const web3 = new Web3(new Web3.providers.HttpProvider("http://127.0.0.1:7545"));

const chai = require("chai");
const assert = chai.assert;

const DSProxyFactory = artifacts.require("DSProxyFactory");
const DSProxy = artifacts.require("DSProxy");
const SaiTub = artifacts.require("SaiTub");
const SaiProxy = artifacts.require("SaiProxy");
const AuctionProxy = artifacts.require("AuctionProxy");
const Auction = artifacts.require("Auction");
const TestToken = artifacts.require("SampleToken");

const BN = require("bn.js");
const { promisify } = require("es6-promisify");

const random = max => Math.floor((Math.random() + 1) * max);

contract("test2", accounts => {
  let proxyFactory = null;
  let saiTub = null;
  let auction = null;
  let auctionProxy = null;
  let myProxy = null;
  let saiProxy = null;
  let cup = null;
  let token = null;
  let auctionId = null;
  let ask = web3.utils.toWei(new BN(random(10)));

  before(async () => {
    proxyFactory = await DSProxyFactory.deployed();
    saiProxy = await SaiProxy.deployed();
    saiTub = await SaiTub.deployed();
    auction = await Auction.deployed();
    auctionProxy = await AuctionProxy.deployed();
    token = await TestToken.deployed();
    const build_tx = await proxyFactory.build();
    myProxy = await DSProxy.at(build_tx.logs[0].args.proxy);
    assert.equal(await myProxy.owner(), accounts[0]);
  });

  it("Test: createAuction", async () => {
    const calldata_open = web3.eth.abi.encodeFunctionCall(
      {
        name: "open",
        type: "function",
        inputs: [
          {
            type: "address",
            name: "tub"
          }
        ]
      },
      [saiTub.address]
    );

    const openCdp = await myProxy.execute(saiProxy.address, calldata_open);
    cup = openCdp.receipt.logs[2].data;

    assert(await saiTub.lad(cup), myProxy.address);

    const expiry = new BN(random(500)).add(new BN(openCdp.receipt.blockNumber));
    const salt = new BN(random(100000));

    const calldata_createAuction = web3.eth.abi.encodeFunctionCall(
      {
        name: "createAuction",
        type: "function",
        inputs: [
          {
            type: "address",
            name: "auction"
          },
          {
            type: "address",
            name: "tub"
          },
          {
            type: "bytes32",
            name: "cdp"
          },
          {
            type: "address",
            name: "token"
          },
          {
            type: "uint256",
            name: "ask"
          },
          {
            type: "uint256",
            name: "expiry"
          },
          {
            type: "uint256",
            name: "salt"
          }
        ]
      },
      [
        auction.address,
        saiTub.address,
        cup,
        token.address,
        ask.toString(),
        expiry.toString(),
        salt.toString()
      ]
    );

    const createAuction = await myProxy.execute(
      auctionProxy.address,
      calldata_createAuction
    );

    auctionId = createAuction.receipt.logs[1].topics[3];

    const auctionEntry = await promisify(cb =>
      auction
        .LogAuctionEntry(
          {},
          { fromBlock: createAuction.blockNumber, toBlock: "latest" }
        )
        .get(cb)
    )();

    assert.equal(await saiTub.lad(cup), auction.address);
    assert.equal(auctionEntry[0].args.cdp, cup);
    assert.equal(auctionEntry[0].args.seller, await myProxy.owner());
    assert.equal(auctionEntry[0].args.proxy, myProxy.address);
    assert.equal(auctionEntry[0].args.token, token.address);
    assert.equal(auctionEntry[0].args.ask.toString(), ask.toString());
    assert.equal(auctionEntry[0].args.expiry.toString(), expiry.toString());
  });

  it("Test: submitBid, take CDP", async () => {
    const acc0InitialBalance = await token.balanceOf(accounts[0]);
    const build_tx = await proxyFactory.build({ from: accounts[1] });
    const acc1ProxyAddr = build_tx.logs[0].args.proxy;
    const acc1Proxy = await DSProxy.at(acc1ProxyAddr);
    assert.equal(await acc1Proxy.owner(), accounts[1]);
    await token.transfer(accounts[1], ask.toString());
    await token.approve(auction.address, ask.toString(), { from: accounts[1] });

    const expiry = new BN(random(500000));
    const salt = new BN(random(100000));

    const submitBid = await auction.submitBid(
      auctionId,
      acc1Proxy.address,
      token.address,
      ask.toString(),
      expiry.toString(),
      salt.toString(),
      { from: accounts[1] }
    );

    const submitLog = submitBid.logs;

    assert.equal(await saiTub.lad(cup), acc1ProxyAddr);

    const acc0FinalBalance = await token.balanceOf(accounts[0]);
    assert.equal(
      acc0FinalBalance.toString() - acc0InitialBalance.toString(),
      0
    );

    const auctionInfo = await auction.getAuctionInfo(auctionId);
    assert.equal(auctionInfo[7], 3);
    const bidInfo = await auction.getBidInfo(submitLog[2].args.bidId);
    assert.equal(bidInfo[8], true);
  });
});
