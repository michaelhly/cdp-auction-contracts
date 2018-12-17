const DSProxyCache = artifacts.require("DSProxyCache");
const DSProxy = artifacts.require("DSProxy");
const Auction = artifacts.require("Auction");
const MKR = "0xa71937147b55deb8a530c7229c442fd3f31b7db2";

module.exports = function(deployer) {
  deployer.deploy(DSProxyCache).then(function() {
    return deployer.deploy(Auction, MKR, DSProxyCache.address);
  });
};
