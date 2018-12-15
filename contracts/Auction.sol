pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./lib/ds-proxy/src/proxy.sol";
import "./lib/IMakerCDP.sol";

contract AuctionRegistry {
     enum AuctionState {
        WaitingForBids,
        Live,
        Cancelled,
        Ended,
        Expired
    }

    struct AuctionInfo {
        uint256 listingNumber;
        bytes32 cdp;
        address seller;
        address token;
        uint256 ask;
        bytes32 auctionId;
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

    IMakerCDP mkr;
    uint256 totalListings = 0;

    constructor(address _makerAddress) {
        mkr = IMakerCDP(_makerAddress);
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
}

contract AuctionEvents is AuctionRegistry{
    event LogAuctionEntry(
        bytes32 cdp,
        address indexed seller,
        bytes32 indexed auctionId,
        address indexed token,
        uint256 ask,
        uint256 expiry
    );

    event LogEndedAuction(
        bytes32 indexed auctionId,
        bytes32 cdp,
        address indexed seller,
        AuctionState state
    );

    event LogConclusion(
        bytes32 cdp,
        address indexed seller,
        address indexed buyer,
        bytes32 indexed auctionId,
        uint256 value
    );

    event LogSubmittedBid(
        bytes32 cdp,
        address indexed buyer,
        uint256 value,
        address indexed token,
        bytes32 indexed bidId,
        uint256 expiryBlockTimestamp
    );

    event LogRevokedBid(
        bytes32 cdp,
        address indexed buyer,
        bytes32 indexed bidId,
        uint256 value
    );

    event CDPTransfer(
        bytes32 cdp, 
        address from,
        address to
    );
}

contract Auction is Pausable, DSProxy, AuctionEvents{
    using SafeMath for uint;
    using SafeMath for uint256;

    address feeTaker;
    uint256 public fee;

    constructor(address _mkrAddr, address _cacheAddr) 
        AuctionRegistry(_mkrAddr)
        DSProxy(_cacheAddr)
        public 
    {
        feeTaker = msg.sender;
        fee = 0;
    }

    function getAuctionInfo(bytes32 auctionId)
        public
        view
        returns (
            uint256 number,
            address seller,
            address token,
            uint256 ask,
            uint256 expiry,
            AuctionState state
        )
    {
        number = auctions[auctionId].listingNumber;
        seller = auctions[auctionId].seller;
        token  = auctions[auctionId].token;
        ask    = auctions[auctionId].ask;
        expiry = auctions[auctionId].expiryBlockTimestamp;
        state  = auctions[auctionId].state;
    }

    function getAuctionInfoByIndex(uint256 index)
        public
        view
        returns (
            uint256 number,
            address seller,
            address token,
            uint256 ask,
            bytes32 id,
            uint256 expiry,
            AuctionState state
        )
    {
        require(index <= totalListings, "Index is too large");

        number = allAuctions[index].listingNumber;
        seller = allAuctions[index].seller;
        token  = allAuctions[index].token;
        ask    = allAuctions[index].ask;
        id     = allAuctions[index].auctionId;
        expiry = allAuctions[index].expiryBlockTimestamp;
        state  = allAuctions[index].state;
    }

    function getBids(bytes32 auctionId)
        public 
        view
        returns (bytes32[])
    {
        return auctionToBids[auctionId];
    }

    function getBidInfo(bytes32 bidId) 
        public
        view
        returns (
            bytes32 cdp,
            address buyer,
            uint256 value,
            address token,
            uint256 expiry
        )
    {
        cdp    = bidRegistry[bidId].cdp;
        buyer  = bidRegistry[bidId].buyer;
        value  = bidRegistry[bidId].value;
        token  = bidRegistry[bidId].token;
        expiry = bidRegistry[bidId].expiryBlockTimestamp;
    }

    /* List a CDP for auction */
    function listCDP(
        bytes32 cdp,
        address token,
        uint256 ask,
        uint256 expiry,
        bytes transferData,
        uint salt
    )
        external
        whenNotPaused
        returns (bytes32)
    {
        require(msg.sender == mkr.lad(cdp), "Currently no support for CDP proxies");
        require(mkr.lad(cdp) != address(this));

        bytes32 auctionId = _genAuctionId(
            ++totalListings,
            cdp,
            msg.sender,
            expiry,
            salt
        );

        require(auctions[auctionId].auctionId == bytes32(0));
        transferCDP(cdp, msg.sender, this, transferData);

        AuctionInfo memory entry = AuctionInfo(
            totalListings,
            cdp,
            msg.sender,
            token,
            ask,
            auctionId,
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
            ask,
            expiry
        );

        return auctionId;
    }

    /* Resolve auction by seller */
    function resolveAuction(bytes32 auctionId, bytes32 bidId) 
        external 
    {
        AuctionInfo memory entry = auctions[auctionId];
        require(entry.seller == msg.sender);
        require(entry.state == AuctionState.Live);

        if(block.timestamp > entry.expiryBlockTimestamp) {
            transferCDP(
                entry.cdp, 
                this, 
                entry.seller, 
                _genCallDataForTransferCDP(entry.cdp, entry.seller)
            );
            endAuction(entry, AuctionState.Expired);
            return;
        }

        BidInfo memory bid = bidRegistry[bidId];
        require(bid.value != 0);
        require(bid.expiryBlockTimestamp <= block.timestamp);

        concludeAuction(entry, bid.buyer, bid.value);
    }

    /* Remove a CDP from auction */
    function cancelAuction(bytes32 auctionId)
        external
    {
        AuctionInfo memory entry = auctions[auctionId];
        require(entry.state == AuctionState.WaitingForBids);
        require(msg.sender == entry.seller);

        transferCDP(
            entry.cdp,
            this,
            entry.seller,
            _genCallDataForTransferCDP(entry.cdp, entry.seller)
        );

        AuctionState state = (block.timestamp > entry.expiryBlockTimestamp) 
                                ? AuctionState.Expired 
                                : AuctionState.Cancelled;

        endAuction(entry, state);
    }

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
        require(
            entry.state == AuctionState.Live ||
            entry.state == AuctionState.WaitingForBids    
        );

        if(entry.expiryBlockTimestamp > block.timestamp) {
            endAuction(entry, AuctionState.Expired);
            return bytes32(0);
        }

        if(entry.state == AuctionState.WaitingForBids) {
            entry.state = AuctionState.Live;
            auctions[auctionId] = entry;
            allAuctions[entry.listingNumber] = entry;
        }

        bytes32 bidId = _genBidId(
            auctionId,
            msg.sender,
            value,
            expiry % block.number,
            salt
        );

        require(bidRegistry[bidId].bidId == bytes32(0));

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

        if(value >= entry.ask) {
            // Allow auction to conclude if bid >= ask
            concludeAuction(entry, msg.sender, value);
        } else {
            // Auction tokens held in escrow until bid expires
            IERC20(entry.token).transferFrom(msg.sender, this, value);
        }

        emit LogSubmittedBid(
            entry.cdp,
            msg.sender,
            value,
            entry.token,
            bidId,
            expiry
        );

        return bidId;
    }

    function revokeBid(bytes32 bidId)
        external
    {
        BidInfo memory bid = bidRegistry[bidId];
        require(msg.sender == bid.buyer);
        require(!revokedBids[bidId]);
        revokedBids[bidId] = true;
        IERC20(bid.token).transfer(msg.sender, bid.value);

        emit LogRevokedBid(
            bid.cdp,
            msg.sender,
            bidId,
            bid.value
        );
    }

    function concludeAuction(AuctionInfo entry, address winner, uint256 value) 
        internal
    {
        uint256 service = value.mul(fee);
        IERC20(entry.token).transfer(feeTaker, service);
        IERC20(entry.token).transfer(entry.seller, value.sub(service));

        transferCDP(
            entry.cdp, 
            this, 
            winner, 
            _genCallDataForTransferCDP(entry.cdp, winner)
        );

        entry.state = AuctionState.Ended;
        auctions[entry.auctionId] = entry;
        allAuctions[entry.listingNumber] = entry;

        emit LogConclusion(
            entry.cdp,
            winner,
            entry.seller,
            entry.auctionId,
            value
        );
    }

    function endAuction(AuctionInfo entry, AuctionState state)
        internal
    {
        entry.state = state;
        auctions[entry.auctionId] = entry;
        allAuctions[entry.listingNumber] = entry;

        emit LogEndedAuction(
            entry.auctionId,
            entry.cdp,
            entry.seller,
            state
        );
    }

    function transferCDP(
        bytes32 cdp, 
        address from, 
        address to, 
        bytes data
    ) internal
    {
        execute(mkr, data);

        emit CDPTransfer(
            cdp,
            from,
            to
        );
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

    /* Helper function to genreate callData send to Maker for CDP transfers within the contract */
    function _genCallDataForTransferCDP(bytes32 _cdp, address _to)
        internal
        pure
        returns (bytes)
    {
        bytes memory data = abi.encodeWithSignature("Give(bytes32, address)", _cdp, _to);
        return data;
    }

    function setFeeTaker(address newFeeTaker) 
        public
        auth
    {
        feeTaker = newFeeTaker;
    }

    function setFee(uint256 newFee) 
        public
        auth
    {
        fee = newFee;
    }
}