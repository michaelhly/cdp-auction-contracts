const chai = require("chai");
const assert = chai.assert;

const Web3 = require("web3");
const web3 = new Web3(
  new Web3.providers.WebsocketProvider("ws://127.0.0.1:8546")
);

const Maker = require("@makerdao/dai");
const maker = Maker.create("kovan", {
  privateKey: "fd4c9f5afcf167e68c7894605fe84e6ee814cd7e04b974dc4b6f150131eb638d"
});

const Auction = artifacts.require("Auction");
const AuctionProxy = artifacts.require("AuctionProxy");
const SaiTubAbi = require("../abi/SaiTub.json");
const ProxyAbi = require("../abi/DSProxy.json");

const BN = require("bn.js");
const { promisify } = require("es6-promisify");

const random = max => Math.floor(Math.random() * (max + 1));

//Specify Number of Auctions
var numAuctions = 5;
//Add ERC20 tokens here
var tokens = ["0xb06d72a24df50d4e2cac133b320c5e7de3ef94cb"];

genCallDataForAuction = (
  auctionAddr,
  tubAddr,
  cupId,
  tokenAddr,
  ask,
  expiry,
  salt
) => {
  return web3.eth.abi.encodeFunctionCall(
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
    [auctionAddr, tubAddr, cupId, tokenAddr, ask, expiry, salt]
  );
};

const main = async () => {
  await maker.authenticate();

  const proxyService = maker.service("proxy");
  if (!proxyService.currentProxy()) {
    return await proxyService.build();
  }

  const saiTubAddr = maker.service("smartContract").getContractByName("SAI_TUB")
    .wrappedContract.address;
  const myAddr = maker.currentAccount().address;
  const myProxyAddr = proxyService.currentProxy();
  const saiProxyAddr = maker
    .service("smartContract")
    .getContractByName("SAI_PROXY").wrappedContract.address;

  const CdpAuction = await Auction.deployed();
  const SaiTub = new web3.eth.Contract(SaiTubAbi, saiTubAddr);
  const MyProxy = new web3.eth.Contract(ProxyAbi, myProxyAddr);

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
    [saiTubAddr]
  );

  i = 0;
  while (i < numAuctions) {
    var openCdp = await MyProxy.methods["0x1cff79cd"](
      saiProxyAddr,
      calldata_open
    ).send({ from: myAddr });

    var event_NewCup = await SaiTub.getPastEvents("LogNewCup", {
      filter: myAddr,
      fromBlock: openCdp.blockNumber,
      toBlock: "latest"
    });

    var cup = event_NewCup[0].returnValues.cup;
    var ask = web3.utils.toWei(new BN(random(10)));
    var expiry = new BN(random(500000)) + new BN(openCdp.blockNumber);
    var salt = new BN(random(100000));
    var callData = genCallDataForAuction(
      CdpAuction.address,
      saiTubAddr,
      cup,
      tokens[0],
      ask.toString(),
      expiry.toString(),
      salt.toString()
    );

    var createAuction = await MyProxy.methods["0x1cff79cd"](
      AuctionProxy.address,
      callData
    ).send({ from: myAddr });

    i++;
  }
};

module.exports = cb => {
  main()
    .then(res => cb(null, res))
    .catch(err => cb(err));
};
