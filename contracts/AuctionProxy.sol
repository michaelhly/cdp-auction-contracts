pragma solidity ^0.4.24;

import "./Auction.sol";
import "./lib/ITub.sol";

contract AuctionProxy {
    Auction public auction;
    ITub public tub;

    constructor(address _auction) 
        public
    {
        auction = Auction(_auction);
        tub = ITub(address(auction.tub()));
    }

    function createAuction(
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
        ITub(address(auction.tub())).give(cdp, address(auction));
        return auctionId;
    }
}