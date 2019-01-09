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

//Fake ERC20 token
const tokens = ["0xb06d72a24df50d4e2cac133b320c5e7de3ef94cb"];

contract("test1", accounts => {
  let proxyFactory = null;
  let saiTub = null;
  let auction = null;
  let auctionProxy = null;
  let myProxy = null;
  let saiProxy = null;
  let token = null;
  let auctionId = null;
  let bidId = null;
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
    const cdpCup = openCdp.receipt.logs[2].data;

    assert(await saiTub.lad(cdpCup), myProxy.address);

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
        cdpCup,
        tokens[0],
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

    assert.equal(await saiTub.lad(cdpCup), auction.address);
    assert.equal(auctionEntry[0].args.cdp, cdpCup);
    assert.equal(auctionEntry[0].args.seller, await myProxy.owner());
    assert.equal(auctionEntry[0].args.proxy, myProxy.address);
    assert.equal(auctionEntry[0].args.token, tokens[0]);
    assert.equal(auctionEntry[0].args.ask.toString(), ask.toString());
    assert.equal(auctionEntry[0].args.expiry.toString(), expiry.toString());
  });

  it("Test: submitBid, submit bid entry", async () => {
    const build_tx = await proxyFactory.build({ from: accounts[1] });
    const acc1Proxy = await DSProxy.at(build_tx.logs[0].args.proxy);
    assert.equal(await acc1Proxy.owner(), accounts[1]);
    await token.transfer(accounts[1], ask.toString());
    await token.approve(auction.address, ask.toString(), { from: accounts[1] });

    const bid = new BN(ask).sub(new BN(10000));
    const expiry = new BN(random(500000));
    const salt = new BN(random(100000));

    const submitBid = await auction.submitBid(
      auctionId,
      acc1Proxy.address,
      token.address,
      bid.toString(),
      expiry.toString(),
      salt.toString(),
      { from: accounts[1] }
    );

    const auctionBalance = await token.balanceOf(auction.address);
    assert.equal(auctionBalance.toString(), bid.toString());

    const submitLog = submitBid.logs[0].args;
    assert.equal(submitLog.auctionId, auctionId);
    assert.equal(submitLog.buyer, accounts[1]);
    assert.equal(submitLog.value.toString(), bid.toString());
    assert.equal(submitLog.token, token.address);
    assert.equal(submitLog.expiryBlock.toString(), expiry.toString());

    bidId = submitLog.bidId;
  });

  it("Test: revokeBid, revoke bid entry", async () => {
    await auction.revokeBid(bidId, { from: accounts[1] });
    const balance = await token.balanceOf(accounts[1]);
    assert.equal(balance.toString(), ask.toString());

    const bidInfo = await auction.getBidInfo(bidId);
    assert.equal(bidInfo[7], true);
  });
});
