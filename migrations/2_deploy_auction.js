const Dummy = "0x0000000000000000000000000000000000000000";
const KovanSaiTub = "0xa71937147b55deb8a530c7229c442fd3f31b7db2";

module.exports = function(deployer, network) {
  const SaiTub = artifacts.require("SaiTub");
  const DSProxyFactory = artifacts.require("DSProxyFactory");
  const AuctionProxy = artifacts.require("AuctionProxy");
  const Auction = artifacts.require("Auction");

  if (network == "kovan") {
    return deployer.deploy(Auction, KovanSaiTub).then(async () => {
      await deployer.deploy(AuctionProxy, Auction.address);
    });
  } else {
    deployer.deploy(DSProxyFactory);
    return deployer
      .deploy(
        SaiTub,
        Dummy,
        Dummy,
        Dummy,
        Dummy,
        Dummy,
        Dummy,
        Dummy,
        Dummy,
        Dummy
      )
      .then(async () => {
        await deployer.deploy(Auction, SaiTub.address);
      });
  }
};
