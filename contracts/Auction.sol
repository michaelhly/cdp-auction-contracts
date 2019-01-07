pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./lib/ITub.sol";
import "./lib/dappsys-monolithic/proxy.sol";

contract AuctionRegistry {
    enum AuctionState {
        Waiting,
        Live,
        Cancelled,
        Ended,
        Expired
    }

    struct AuctionInfo {
        uint256 listingNumber;
        bytes32 cdp;
        address seller;
        address proxy;
        address token;
        uint256 ask;
        bytes32 auctionId;
        uint256 expiryBlock;
        AuctionState state;
    }

    struct BidInfo {
        bytes32 cdp;
        address buyer;
        address proxy;
        uint256 value;
        address token;
        bytes32 bidId;
        bool    revoked;
        uint256 expiryBlock;
    }

    uint256 public totalListings = 0;

    // Mapping of auctionIds to its corresponding CDP auction
    mapping (bytes32 => AuctionInfo) internal auctions;
    // Mapping for iterative lookup of all auctions
    mapping (uint256 => AuctionInfo) internal allAuctions;
    // Mapping of users to AuctionIds
    mapping (address => bytes32[]) internal userToAuctions;

    // Registry mapping bidIds to their corresponding entries
    mapping (bytes32 => BidInfo) internal bidRegistry;
    // Mapping of auctionIds to bidIds
    mapping (bytes32 => bytes32[]) internal auctionToBids;
    // Mapping of users to bidIds
    mapping (address => bytes32[]) internal userToBids;
    // Mapping of revoked bids
    mapping (bytes32 => bool) public revokedBids;

    function getAuctionsByUser(address auctioneer)
        public
        view
        returns (bytes32[])
    {
        return userToAuctions[auctioneer];
    }

    function getAuctionInfo(bytes32 auctionId)
        public
        view
        returns (
            uint256 number,
            bytes32 cdp,
            address seller,
            address proxy,
            address token,
            uint256 ask,
            uint256 expiry,
            AuctionState state
        )
    {
        number = auctions[auctionId].listingNumber;
        cdp    = auctions[auctionId].cdp;
        seller = auctions[auctionId].seller;
        proxy  = auctions[auctionId].proxy;
        token  = auctions[auctionId].token;
        ask    = auctions[auctionId].ask;
        expiry = auctions[auctionId].expiryBlock;
        state  = auctions[auctionId].state;
    }

    function getAuctionInfoByIndex(uint256 index)
        public
        view
        returns (
            bytes32 id,
            bytes32 cdp,
            address seller,
            address proxy,
            address token,
            uint256 ask,
            uint256 expiry,
            AuctionState state
        )
    {
        id     = allAuctions[index].auctionId;
        cdp    = allAuctions[index].cdp;
        seller = allAuctions[index].seller;
        proxy  = allAuctions[index].proxy;
        token  = allAuctions[index].token;
        ask    = allAuctions[index].ask;
        expiry = allAuctions[index].expiryBlock;
        state  = allAuctions[index].state;
    }

    function getBids(bytes32 auctionId)
        public 
        view
        returns (bytes32[])
    {
        return auctionToBids[auctionId];
    }

    function getBidsByUser(address bidder)
        public
        view
        returns (bytes32[])
    {
        return userToBids[bidder];
    }

    function getBidInfo(bytes32 bidId)
        public
        view
        returns (
            bytes32 cdp,
            address buyer,
            address proxy,
            uint256 value,
            address token,
            bool    revoked,
            uint256 expiry
        )
    {
        cdp     = bidRegistry[bidId].cdp;
        buyer   = bidRegistry[bidId].buyer;
        proxy   = bidRegistry[bidId].proxy;
        value   = bidRegistry[bidId].value;
        token   = bidRegistry[bidId].token;
        revoked = bidRegistry[bidId].revoked; 
        expiry  = bidRegistry[bidId].expiryBlock;
    }
}

contract AuctionEvents is AuctionRegistry{
    event LogAuctionEntry(
        bytes32 cdp,
        address indexed seller,
        address indexed proxy,
        bytes32 indexed auctionId,
        address token,
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
        address indexed proxy,
        uint256 value,
        address token,
        bytes32 indexed bidId,
        uint256 expiryBlock
    );

    event LogRevokedBid(
        bytes32 cdp,
        address indexed buyer,
        bytes32 indexed bidId,
        uint256 value
    );

    event LogCDPTransfer(
        bytes32 cdp, 
        address from,
        address to
    );

    event LogAddedCollateral(
        bytes32 cdp,
        bytes32 auctionId,
        uint256 value,
        uint256 newAsk
    );
}

contract Auction is Pausable, AuctionEvents{
    using SafeMath for uint256;

    address private feeTaker;
    uint256 public fee;
    ITub public tub;
    
    constructor(address _tub)
        public 
    {
        tub = ITub(_tub);
        feeTaker = msg.sender;
        fee = 0;
    }

    /**
     * List a CDP for auction
     */
    function listCDP(
        bytes32 cdp,
        address seller,
        address token,
        uint256 ask,
        uint256 expiry,
        uint256 salt
    )
        external
        whenNotPaused
        returns (bytes32)
    {
        require(tub.lad(cdp) != address(this));
        require(DSProxy(msg.sender).owner() == seller);

        bytes32 auctionId = _genAuctionId(
            ++totalListings,
            cdp,
            msg.sender,
            expiry,
            salt
        );

        require(auctions[auctionId].auctionId == bytes32(0));

        AuctionInfo memory entry = AuctionInfo(
            totalListings,
            cdp,
            seller,
            msg.sender,
            token,
            ask,
            auctionId,
            expiry,
            AuctionState.Waiting
        );

        updateAuction(entry, AuctionState.Waiting);
        userToAuctions[seller].push(auctionId);

        emit LogAuctionEntry(
            cdp,
            seller,
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
        require(tub.lad(entry.cdp) == address(this));
        require(entry.seller == msg.sender);
        require(!revokedBids[bidId]);
        require(entry.state == AuctionState.Live);

        if(block.number > entry.expiryBlock) {
            endAuction(entry, AuctionState.Expired);
            return;
        }

        BidInfo memory bid = bidRegistry[bidId];
        require(bid.value != 0);
        require(bid.expiryBlock <= block.number);

        concludeAuction(entry, bid.buyer, bid.proxy, bid.token, bid.value);
    }

    /* Remove a CDP from auction */
    function cancelAuction(bytes32 auctionId)
        external
    {
        AuctionInfo memory entry = auctions[auctionId];
        require(tub.lad(entry.cdp) == address(this));
        require(entry.state == AuctionState.Waiting ||
                entry.state == AuctionState.Expired);
        require(msg.sender == entry.seller);

        AuctionState state = (block.number > entry.expiryBlock)
                                ? AuctionState.Expired
                                : AuctionState.Cancelled;
        endAuction(entry, state);
    }

    function submitBid(
        bytes32 auctionId,
        address proxy,
        address token,
        uint256 value,
        uint256 expiry,
        uint256 salt
    )
        external
        whenNotPaused
        returns (bytes32)
    {
        AuctionInfo memory entry = auctions[auctionId];
        require(tub.lad(entry.cdp) == address(this));
        require(DSProxy(proxy).owner() == msg.sender);
        require(
            entry.state == AuctionState.Live ||
            entry.state == AuctionState.Waiting
        );
        
        if(entry.expiryBlock > block.number) {
            endAuction(entry, AuctionState.Expired);
            return bytes32(0);
        }

        if(entry.state == AuctionState.Waiting) {
            updateAuction(entry, AuctionState.Live);
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
            proxy,
            value,
            token,
            bidId,
            false,
            expiry
        );

        bidRegistry[bidId] = bid;
        userToBids[msg.sender].push(bidId);
        auctionToBids[auctionId].push(bidId);

        if(value >= entry.ask && token == entry.token) {
            // Allow auction to conclude if bid >= ask
            concludeAuction(entry, msg.sender, proxy, entry.token, value);
        } else {
            // Auction tokens held in escrow until bid expires
            IERC20(token).transferFrom(msg.sender, this, value);
        }

        emit LogSubmittedBid(
            entry.cdp,
            msg.sender,
            proxy,
            value,
            token,
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
        delete bidRegistry[bidId];
        IERC20(bid.token).transfer(msg.sender, bid.value);

        emit LogRevokedBid(
            bid.cdp,
            msg.sender,
            bidId,
            bid.value
        );
    }

    /* Fund additional collateral to CDP being auctioned */
    function fundCDP(bytes32 auctionId, uint value, uint256 newAsk) 
        external 
    {
        AuctionInfo memory entry = auctions[auctionId];
        require(tub.lad(entry.cdp) == address(this));
        require(entry.seller == msg.sender);

        tub.lock(entry.cdp, value);
        entry.ask = newAsk ==0 ? entry.ask : newAsk;
        updateAuction(entry, entry.state);

        emit LogAddedCollateral(
            entry.cdp,
            entry.auctionId,
            value,
            newAsk
        );
    }

    function concludeAuction(
        AuctionInfo entry,
        address winner, 
        address proxy, 
        address token,
        uint256 value
    ) 
        internal
    {
        uint256 service = value.mul(fee);
        IERC20(token).transfer(feeTaker, service);
        IERC20(token).transfer(entry.seller, value.sub(service));

        transferCDP(
            entry.cdp, 
            proxy
        );

        updateAuction(entry, AuctionState.Ended);

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
        updateAuction(entry, state);
        transferCDP(
            entry.cdp,
            entry.proxy
        );

        emit LogEndedAuction(
            entry.auctionId,
            entry.cdp,
            entry.seller,
            state
        );
    }

    function updateAuction(AuctionInfo entry, AuctionState state)
        internal
    {
        entry.state = state;
        auctions[entry.auctionId] = entry;
        allAuctions[entry.listingNumber] = entry;
    }

    function transferCDP(
        bytes32 cdp, address to
    ) internal
    {
        require(DSProxy(to).owner() == msg.sender);
        tub.give(cdp, to);

        emit LogCDPTransfer(
            cdp,
            address(this),
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
        uint256 _salt
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
        uint256 _salt
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
        onlyPauser
    {
        feeTaker = newFeeTaker;
    }

    function setFee(uint256 newFee) 
        public
        onlyPauser
    {
        fee = newFee;
    }
}