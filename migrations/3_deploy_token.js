const Token = artifacts.require("SampleToken");

module.exports = function(deployer) {
  const token = deployer.deploy(Token, "TestToken");
};
