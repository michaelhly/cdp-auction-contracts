const Auction = artifacts.require("Auction");
const SaiTub = "0xa71937147b55deb8a530c7229c442fd3f31b7db2";

module.exports = function(deployer) {
  deployer.deploy(Auction, SaiTub);
};
