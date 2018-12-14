pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./lib/IMakerCDP.sol";

contract RegistryVars {
    using SafeMath for uint;
    using SafeMath for uint256;

    enum AuctionState {
        Undefined,
        WaitingForBids,
        Live,
        Cancelled,
        Expired
    }

    struct AuctionInfo {
        uint256 listingNumber;
        bytes32 cdp;
        address seller;
        address token;
        uint256 expiryBlockTimestamp;
        AuctionState state;
    }

    struct BidInfo {
        bytes32 cdp;
        address buyer;
        uint256 value;
        address token;
        bytes32 bidId;
        uint256 expiryBlockTimestamp;
    }
}

contract AuctionHouse is Pausable, Ownable, RegistryVars{
    uint256 totalListings = 0;
    IMakerCDP mkr;
    address feeTaker;
    uint256 public fee;

    constructor(
        address _mkrAddress
    ) public {
        mkr = IMakerCDP(_mkrAddress);
        feeTaker = msg.sender;
        fee = 0;
    }

    // Mapping of auctionIds to its corresponding CDP auction
    mapping (bytes32 => AuctionInfo) internal auctions;
    // Mapping for iterative lookup of all auctions
    mapping (uint256 => AuctionInfo) internal allAuctions;
   
    // Registry mapping bidIds to their corresponding entries
    mapping (bytes32 => BidInfo) internal bidRegistry;
    // Mapping of auctionIds to bidIds
    mapping (bytes32 => bytes32[]) internal auctionToBids;
    // Mapping of revoked bids
    mapping (bytes32 => bool) public revokedBids;

    event LogAuctionEntry(
        bytes32 cdp,
        address indexed seller,
        bytes32 indexed auctionId,
        address indexed token,
        uint256 expiry
    );

    event LogCancelledAuction(
        bytes32 cdp,
        address indexed seller,
        bytes32 indexed auctionId
    );

    function getAuction(bytes32 auctionId)
        public
        view
        returns (
            uint256 number,
            address seller,
            address token,
            uint256 expiry,
            AuctionState state
        )
    {
        number = auctions[auctionId].listingNumber;
        seller = auctions[auctionId].seller;
        token = auctions[auctionId].token;
        expiry = auctions[auctionId].expiryBlockTimestamp;
        state = auctions[auctionId].state;
    }

    function getAuctionByIndex(uint256 index)
        public
        view
        returns (
            uint256 number,
            address seller,
            address token,
            uint256 expiry,
            AuctionState state
        )
    {
        require(index <= totalListings);
        number = allAuctions[index].listingNumber;
        seller = allAuctions[index].seller;
        token = allAuctions[index].token;
        expiry = allAuctions[index].expiryBlockTimestamp;
        state = allAuctions[index].state;
    }

    /* List a CDP for auction */
    function listCDP(
        bytes32 cdp,
        address token,
        uint256 expiry,
        uint salt
    )
        external
        whenNotPaused
        returns (bytes32)
    {
        require(msg.sender == mkr.lad(cdp), "currently no support for CDP proxies");

        bytes32 auctionId = _genAuctionId(
            ++totalListings,
            cdp,
            msg.sender,
            expiry,
            salt
        );

        require(auctions[auctionId].state == AuctionState.Undefined);

        AuctionInfo memory entry = AuctionInfo(
            totalListings,
            cdp,
            msg.sender,
            token,
            expiry,
            AuctionState.WaitingForBids
        );

        auctions[auctionId] = entry;
        allAuctions[totalListings] = entry;

        emit LogAuctionEntry(
            cdp,
            msg.sender,
            auctionId,
            token,
            expiry
        );

        return auctionId;
    }

    /* Remove a CDP from auction */
    function cancelAuction(bytes32 auctionId)
        external
    {
        AuctionInfo memory entry = auctions[auctionId];
        require(entry.state == AuctionState.WaitingForBids);
        require(msg.sender == entry.seller);

        entry.state = AuctionState.Cancelled;
        auctions[auctionId] = entry;

        emit LogCancelledAuction(
            entry.cdp,
            entry.seller,
            auctionId
        );
    }

    /* Submit a bid to auction */
    function submitBid(
        bytes32 auctionId,
        uint256 value,
        uint256 expiry,
        uint salt
    )
        external
        whenNotPaused
        returns (bytes32)
    {
        AuctionInfo memory entry = auctions[auctionId];

        require(entry.seller != msg.sender);
        require(entry.state != AuctionState.Expired);

        if(entry.expiryBlockTimestamp > block.timestamp) {
            entry.state = AuctionState.Expired;
            auctions[auctionId] = entry;
            allAuctions[entry.listingNumber] = entry;
            return bytes32(0);
        }

        require(
            entry.state == AuctionState.WaitingForBids ||
            entry.state == AuctionState.Live
        );
        require(IERC20(entry.token).transferFrom(msg.sender, this, value));

        if(entry.state == AuctionState.WaitingForBids) {
            entry.state = AuctionState.Live;
            auctions[auctionId] = entry;
            allAuctions[entry.listingNumber] = entry;
        }

        bytes32 bidId = _genBidId(
            auctionId,
            msg.sender,
            value,
            expiry,
            salt
        );

        BidInfo memory bid = BidInfo(
            entry.cdp,
            msg.sender,
            value,
            entry.token,
            bidId,
            expiry
        );

        bidRegistry[bidId] = bid;
        auctionToBids[auctionId].push(bidId);

        return bidId;
    }

    /* RevokeBid from auction */
    function revokeBid(bytes32 bidId)
        external
    {
        BidInfo memory bid = bidRegistry[bidId];
        require(msg.sender == bid.buyer);
        require(!revokedBids[bidId]);
        revokedBids[bidId] = true;
        require(IERC20(bid.token).transfer(msg.sender, bid.value));
    }

    /**
     * Helper function for computing the hash of a given auction
     * listing. Will be used as the auctionId for each new CDP
     * auctions. 
     */
    function _genAuctionId(
        uint256 _auctionCounter,
        bytes32 _cup, 
        address _seller, 
        uint256 _expiry, 
        uint _salt
    )
        internal
        pure
        returns(bytes32)
    {
        return keccak256(
            abi.encodePacked(
                _auctionCounter,
                _cup, 
                _seller, 
                _expiry,
                _salt
            )
        );
    }

    /**
     * Helper function for computing the hash of a given bid.
     * Will be used as the bidId for each bid in an auction.
     */
    function _genBidId(
        bytes32 _auctionId,
        address _buyer,
        uint256 _value,
        uint256 _expiry,
        uint _salt
    ) 
        internal
        pure
        returns(bytes32)
    {
        return keccak256(
            abi.encodePacked(
                _auctionId,
                _buyer,
                _value,
                _expiry,
                _salt
            )
        );
    }

    function setFeeTaker(address newFeeTaker) 
        public
        onlyOwner 
    {
        feeTaker = newFeeTaker;
    }

    function setFee(uint256 newFee) 
        public
        onlyOwner 
    {
        fee = newFee;
    }
}
