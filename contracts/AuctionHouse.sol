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
        Live,
        Cancelled,
        Expired
    }

    struct ListingEntry {
        uint256 listingNumber;
        bytes32 cdp;
        address seller;
        address token;
        address proxy;
        bytes32 auctionID;
        uint256 expiryBlockTimestamp;
        AuctionState state;
    }

    struct BidEntry {
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

    // Registry mapping CDPs to their corresponding auctions and listings
    mapping (bytes32 => mapping(bytes32 => ListingEntry)) internal listingRegistry;
    // Mapping of ListingEntries in order of listing history
    mapping (uint256 => ListingEntry) internal allListings;
   
    // Mapping of AuctionIDs to max BidEntry
    mapping (bytes32 => BidEntry) internal maxBidEntry;
    // Mapping of AuctionIDs to BidEntryIDs
    mapping (bytes32 => uint256[]) public auctionToBidEntries;
    // Registry mapping BidEntryIDs to their corresponding entries
    mapping (bytes32 => mapping (bytes32 => BidEntry)) internal bidRegistry;

    event LogEntryListing(
        bytes32 cdp,
        address indexed seller,
        bytes32 indexed auctionId,
        address indexed token,
        address proxy,
        uint256 expiry
    );

    event LogEntryRemoval(
        bytes32 cdp,
        address indexed seller,
        bytes32 indexed auctionId
    );

    function getListing(bytes32 cdp, bytes32 auctionID)
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
        number = listingRegistry[cdp][auctionID].listingNumber;
        seller = listingRegistry[cdp][auctionID].seller;
        token = listingRegistry[cdp][auctionID].token;
        proxy = listingRegistry[cdp][auctionID].proxy;
        expiry = listingRegistry[cdp][auctionID].expiryBlockTimestamp;
        state = listingRegistry[cdp][auctionID].state;
    }

    function getListingByIndex(uint256 index)
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
        number = allListings[index].listingNumber;
        seller = allListings[index].seller;
        token = allListings[index].token;
        proxy = allListings[index].proxy;
        expiry = allListings[index].expiryBlockTimestamp;
        state = allListings[index].state;
    }

    /* List a CDP to auction */
    function listCDP(
        bytes32 _cdp,
        address _token,
        uint256 _expiry,
        uint _salt
    )
        external
        whenNotPaused
    {
        bytes32 auctionID = _genAuctionId(
            ++totalListings,
            _cdp,
            msg.sender,
            _token,
            _expiry,
            _salt 
        );

        require(listingRegistry[_cdp][auctionID].auctionID == bytes32(0));

        ListingEntry memory entry = ListingEntry(
            totalListings,
            _cdp, 
            msg.sender,
            _token,
            mkr.lad(_cdp), 
            auctionID,
            _expiry,
            AuctionState.Live
        );

        listingRegistry[_cdp][auctionID] = entry;
        allListings[totalListings] = entry;

        emit LogEntryListing(
            _cdp,
            msg.sender,
            auctionID,
            _token,
            mkr.lad(_cdp),
            _expiry
        );
    }

    /* Remove a CDP from auction */
    function removeCDP(bytes32 cdp, bytes32 auctionID)
        external
    {
        ListingEntry memory entry = listingRegistry[cdp][auctionID];
        require(entry.state != AuctionState.Live);
        require(
            msg.sender == mkr.lad(cdp) || 
            msg.sender == listingRegistry[cdp][auctionID].seller
        );

        entry.state = AuctionState.Cancelled;
        listingRegistry[cdp][auctionID] = entry;

        emit LogEntryRemoval(
            cdp,
            entry.seller,
            entry.auctionID
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
