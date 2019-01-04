const HDWalletProvider = require("truffle-hdwallet-provider");

const provider = new HDWalletProvider("", "https://kovan.infura.io/v3/APIKEY");

const Web3 = require("web3");
const web3 = new Web3(provider);

const Maker = require("@makerdao/dai");
const maker = Maker.create("kovan", {
  privateKey: ""
});

const Auction = artifacts.require("Auction");
const AuctionProxy = artifacts.require("AuctionProxy");
const SaiTub_ = require("../build/contracts/SaiTub.json");
const DSProxy = require("../build/contracts/DSProxy.json");

const BN = require("bn.js");
const random = max => Math.floor(Math.random() * (max + 1));

//Specify Number of Auctions
var numAuctions = 5;
//Add ERC20 tokens here
var tokens = [
  "0xb06d72a24df50d4e2cac133b320c5e7de3ef94cb",
  "0xd0a1e359811322d97991e03f863a0c30c2cf029c",
  "0xC4375B7De8af5a38a93548eb8453a498222C4fF2"
];

const genCallDataForAuction = (
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
  const SaiTub = new web3.eth.Contract(SaiTub_.abi, saiTubAddr);
  const MyProxy = new web3.eth.Contract(DSProxy.abi, myProxyAddr);

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

    var ask = web3.utils.toWei(new BN(random(10) + 1));
    var expiry = new BN(random(500000)) + new BN(openCdp.blockNumber);
    var salt = new BN(random(100000));

    var callData = genCallDataForAuction(
      CdpAuction.address,
      saiTubAddr,
      cup,
      tokens[random(2)],
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
