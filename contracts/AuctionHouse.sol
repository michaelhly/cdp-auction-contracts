pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./IMakerCDP.sol";

contract GlobalVars {
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
        address proxy;
        bytes32 auctionID;
        uint256 expiryBlockTimestamp;
        AuctionState state;
    }

    struct BidEntry {
        bytes32 cdp;
        address buyer;
        uint256 value;
        address token;
        bytes32 bidID;
        uint256 expiryBlockTimestamp;
    }
}

contract AuctionHouse is Pausable, Ownable, GlobalVars{
    IMakerCDP mkr = IMakerCDP(address(0));
    uint256 auctionCounter = 0;

    constructor(
        address _mkrAddress
    ) public {
        mkr = IMakerCDP(_mkrAddress);
    }

    // Registry mapping CDPs to their corresponding auctions and listings
    mapping (bytes32 => mapping(bytes32 => ListingEntry)) public listingRegistry;
    // Array of all auctions
    bytes32[] auctionRegistry;
   
    // Mapping of AuctionIDs to BidEntryIDs
    mapping (bytes32 => uint256[]) internal auctionToBidEntries; 
    // Registry mapping BidEntryIDs to their corresponding entries
    mapping (bytes32 => mapping (bytes32 => BidEntry)) internal bidRegistry; 

    event LogEntryListing(
        bytes32 cdp,
        address indexed seller,
        bytes32 indexed auctionId,
        address proxy,
        uint256 expiry
    );

    event LogEntryRemoval(
        bytes32 cdp,
        address indexed seller,
        bytes32 indexed auctionId
    );

    function getListingInfo(bytes32 cdp, bytes32 auctionID)
        public 
        view
        returns (
            uint256 number,
            address seller,
            address proxy,
            uint256 expiry,
            AuctionState state
        )
    {
        number = listingRegistry[cdp][auctionID].listingNumber;
        seller = listingRegistry[cdp][auctionID].seller;
        proxy = listingRegistry[cdp][auctionID].proxy;
        expiry = listingRegistry[cdp][auctionID].expiryBlockTimestamp;
        state = listingRegistry[cdp][auctionID].state;
    }

    /* List a CDP to auction */
    function listCDP(bytes32 _cdp, uint256 _expiry, uint _salt)
        public
        whenNotPaused
    {
        bytes32 auctionID = _genAuctionId(
            ++auctionCounter,
            _cdp,
            msg.sender,
            _expiry,
            _salt 
        );

        require(listingRegistry[_cdp][auctionID].auctionID == bytes32(0));

        ListingEntry memory entry = ListingEntry(
            auctionCounter,
            _cdp, 
            msg.sender,
            mkr.lad(_cdp), 
            auctionID,
            _expiry,
            AuctionState.Live
        );

        listingRegistry[_cdp][auctionID] = entry;
        auctionRegistry.push(auctionID);

        emit LogEntryListing(
            _cdp,
            msg.sender,
            auctionID,
            mkr.lad(_cdp),
            _expiry
        );
    }

    /* Remove a CDP from auction */
    function removeCDP(bytes32 cdp, bytes32 auctionID) public {
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
     * Get AuctionID without CDP bytes
     */
    function getAuctionID(uint256 index) 
        public
        view
        returns (bytes32 auctionID)
    {
        require(index <= auctionCounter);
        return auctionID[index];
    }
}
