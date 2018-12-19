pragma solidity ^0.4.24;

import "./Auction.sol";
import "./sai/SaiProxy.sol";

contract AuctionProxy is SaiProxy{
    Auction public auction;

    constructor(address _auction, address _tub) 
        public
    {
        auction = Auction(_auction);
    }

    function createAuction(
        address tub,
        bytes32 cdp,
        address token,
        uint256 ask,
        uint256 expiry,
        uint salt
    ) external returns (bytes32) {
        bytes32 auctionId = auction.listCDP(
            cdp,
            token,
            ask,
            expiry,
            salt
        );
        TubInterface(tub).give(cdp, address(auction));
        return auctionId;
    }
}