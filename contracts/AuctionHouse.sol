pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./IMakerCDP.sol";

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
        address proxy;
        uint256 expiryBlockTimestamp;
        AuctionState state;
    }

    struct BidInfo {
        bytes32 cdp;
        address buyer;
        uint256 value;
        bytes32 bidID;
        uint256 expiryBlockTimestamp;
    }
}

contract AuctionHouse is Pausable, Ownable, RegistryVars{
    IMakerCDP mkr = IMakerCDP(address(0));
    uint256 totalListings = 0;

    constructor(
        address _mkrAddress
    ) public {
        mkr = IMakerCDP(_mkrAddress);
    }

    // Mapping of auctionIDs to its corresponding CDP auction
    mapping (bytes32 => AuctionInfo) internal auctions;
    // Mapping for iterative lookup of all auctions
    mapping (uint256 => AuctionInfo) internal allAuctions;
   
    // Mapping of auctionIDs to max bid
    mapping (bytes32 => BidInfo) internal maxBid;
    // Mapping of AuctionIDs to bids
    mapping (bytes32 => uint256[]) public auctionToBids;
    // Registry mapping bidIDs to their corresponding entries
    mapping (bytes32 => mapping (bytes32 => BidInfo)) internal bidRegistry;

    event LogAuctionEntry(
        bytes32 cdp,
        address indexed seller,
        bytes32 indexed auctionId,
        address indexed token,
        address proxy,
        uint256 expiry
    );

    event LogCancelledAuction(
        bytes32 cdp,
        address indexed seller,
        bytes32 indexed auctionId
    );

    function getAuction(bytes32 auctionID)
        public
        view
        returns (
            uint256 number,
            address seller,
            address token,
            address proxy,
            uint256 expiry,
            AuctionState state
        )
    {
        number = auctions[auctionID].listingNumber;
        seller = auctions[auctionID].seller;
        token = auctions[auctionID].token;
        proxy = auctions[auctionID].proxy;
        expiry = auctions[auctionID].expiryBlockTimestamp;
        state = auctions[auctionID].state;
    }

    function getAuctionByIndex(uint256 index)
        public
        view
        returns (
            uint256 number,
            address seller,
            address token,
            address proxy,
            uint256 expiry,
            AuctionState state
        )
    {
        require(index <= totalListings);
        number = allAuctions[index].listingNumber;
        seller = allAuctions[index].seller;
        token = allAuctions[index].token;
        proxy = allAuctions[index].proxy;
        expiry = allAuctions[index].expiryBlockTimestamp;
        state = allAuctions[index].state;
    }

    /* List a CDP for auction */
    function listCDP(
        bytes32 _cdp,
        address _token,
        uint256 _expiry,
        uint _salt
    )
        external
        whenNotPaused
        returns (bytes32)
    {
        bytes32 auctionID = _genAuctionId(
            ++totalListings,
            _cdp,
            msg.sender,
            _token,
            _expiry,
            _salt 
        );

        require(auctions[auctionID].state == AuctionState.Undefined);

         AuctionInfo memory entry = AuctionInfo(
            totalListings,
            _cdp, 
            msg.sender,
            _token,
            mkr.lad(_cdp), 
            _expiry,
            AuctionState.WaitingForBids
        );

        auctions[auctionID] = entry;
        allAuctions[totalListings] = entry;

        emit LogAuctionEntry(
            _cdp,
            msg.sender,
            auctionID,
            _token,
            mkr.lad(_cdp),
            _expiry
        );

        return auctionID;
    }

    /* Remove a CDP from auction */
    function cancelAuction(bytes32 auctionID)
        external
    {
        AuctionInfo memory entry = auctions[auctionID];
        require(entry.state != AuctionState.Live);
        require(
            msg.sender == mkr.lad(entry.cdp) ||
            msg.sender == entry.seller
        );

        entry.state = AuctionState.Cancelled;
        auctions[auctionID] = entry;

        emit LogCancelledAuction(
            entry.cdp,
            entry.seller,
            auctionID
        );
    } 

    /**
     * Helper function for computing the hash of a given listing, 
     * which will be used as the auctionID for each new CDP 
     * auctions. 
     */
    function _genAuctionId(
        uint256 _auctionCounter,
        bytes32 _cup, 
        address _seller, 
        address _token,
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
                _token,
                _expiry,
                _salt
            )
        );
    }
}
