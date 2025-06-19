// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Auction House
 * @dev A decentralized platform for creating and participating in auctions
 * @author Decentralized Auction House Team
 */
contract DecentralizedAuctionHouse {
    // Struct to represent an auction
    struct Auction {
        uint256 auctionId;
        address payable seller;
        string itemName;
        string itemDescription;
        uint256 startingPrice;
        uint256 currentBid;
        address payable currentBidder;
        uint256 auctionEndTime;
        bool active;
        bool settled;
    }

    // State variables
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => mapping(address => uint256)) public pendingReturns;
    uint256 public auctionCounter;
    uint256 public platformFeePercentage = 250; // 2.5% in basis points
    address payable public platformOwner;

    // Events
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        string itemName,
        uint256 startingPrice,
        uint256 auctionEndTime
    );
    
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount,
        uint256 timestamp
    );
    
    event AuctionSettled(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 finalPrice,
        uint256 timestamp
    );
    
    event BidWithdrawn(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );

    // Modifiers
    modifier onlyPlatformOwner() {
        require(msg.sender == platformOwner, "Only platform owner can call this");
        _;
    }

    modifier auctionExists(uint256 _auctionId) {
        require(_auctionId < auctionCounter, "Auction does not exist");
        _;
    }

    modifier auctionActive(uint256 _auctionId) {
        require(auctions[_auctionId].active, "Auction is not active");
        require(block.timestamp < auctions[_auctionId].auctionEndTime, "Auction has ended");
        _;
    }

    modifier auctionEnded(uint256 _auctionId) {
        require(block.timestamp >= auctions[_auctionId].auctionEndTime, "Auction is still active");
        _;
    }

    modifier notSeller(uint256 _auctionId) {
        require(msg.sender != auctions[_auctionId].seller, "Seller cannot bid on own auction");
        _;
    }

    /**
     * @dev Constructor to initialize the auction house
     */
    constructor() {
        platformOwner = payable(msg.sender);
        auctionCounter = 0;
    }

    /**
     * @dev Create a new auction
     * @param _itemName Name of the item being auctioned
     * @param _itemDescription Description of the item
     * @param _startingPrice Minimum starting price for the auction
     * @param _auctionDuration Duration of the auction in seconds
     */
    function createAuction(
        string memory _itemName,
        string memory _itemDescription,
        uint256 _startingPrice,
        uint256 _auctionDuration
    ) external {
        require(bytes(_itemName).length > 0, "Item name cannot be empty");
        require(_startingPrice > 0, "Starting price must be greater than 0");
        require(_auctionDuration >= 300, "Auction duration must be at least 5 minutes");
        require(_auctionDuration <= 604800, "Auction duration cannot exceed 7 days");

        uint256 auctionEndTime = block.timestamp + _auctionDuration;

        auctions[auctionCounter] = Auction({
            auctionId: auctionCounter,
            seller: payable(msg.sender),
            itemName: _itemName,
            itemDescription: _itemDescription,
            startingPrice: _startingPrice,
            currentBid: 0,
            currentBidder: payable(address(0)),
            auctionEndTime: auctionEndTime,
            active: true,
            settled: false
        });

        emit AuctionCreated(
            auctionCounter,
            msg.sender,
            _itemName,
            _startingPrice,
            auctionEndTime
        );

        auctionCounter++;
    }

    /**
     * @dev Place a bid on an active auction
     * @param _auctionId ID of the auction to bid on
     */
    function placeBid(uint256 _auctionId) 
        external 
        payable 
        auctionExists(_auctionId)
        auctionActive(_auctionId)
        notSeller(_auctionId)
    {
        Auction storage auction = auctions[_auctionId];
        
        require(msg.value > auction.startingPrice, "Bid must be higher than starting price");
        require(msg.value > auction.currentBid, "Bid must be higher than current bid");

        // Return the previous bid to the previous bidder
        if (auction.currentBidder != address(0) && auction.currentBid > 0) {
            pendingReturns[_auctionId][auction.currentBidder] += auction.currentBid;
        }

        // Update auction with new bid
        auction.currentBid = msg.value;
        auction.currentBidder = payable(msg.sender);

        emit BidPlaced(_auctionId, msg.sender, msg.value, block.timestamp);
    }

    /**
     * @dev Settle an auction after it has ended
     * @param _auctionId ID of the auction to settle
     */
    function settleAuction(uint256 _auctionId)
        external
        auctionExists(_auctionId)
        auctionEnded(_auctionId)
    {
        Auction storage auction = auctions[_auctionId];
        require(auction.active, "Auction is not active");
        require(!auction.settled, "Auction already settled");

        auction.active = false;
        auction.settled = true;

        if (auction.currentBidder != address(0) && auction.currentBid > 0) {
            // Calculate platform fee
            uint256 platformFee = (auction.currentBid * platformFeePercentage) / 10000;
            uint256 sellerAmount = auction.currentBid - platformFee;

            // Transfer funds
            auction.seller.transfer(sellerAmount);
            platformOwner.transfer(platformFee);

            emit AuctionSettled(
                _auctionId,
                auction.currentBidder,
                auction.currentBid,
                block.timestamp
            );
        } else {
            // No bids were placed
            emit AuctionSettled(_auctionId, address(0), 0, block.timestamp);
        }
    }

    /**
     * @dev Withdraw pending bid refunds
     * @param _auctionId ID of the auction
     */
    function withdrawBid(uint256 _auctionId) external {
        uint256 amount = pendingReturns[_auctionId][msg.sender];
        require(amount > 0, "No pending refunds");

        pendingReturns[_auctionId][msg.sender] = 0;
        payable(msg.sender).transfer(amount);

        emit BidWithdrawn(_auctionId, msg.sender, amount);
    }

    // View functions
    function getAuction(uint256 _auctionId) 
        external 
        view 
        auctionExists(_auctionId)
        returns (
            address seller,
            string memory itemName,
            string memory itemDescription,
            uint256 startingPrice,
            uint256 currentBid,
            address currentBidder,
            uint256 auctionEndTime,
            bool active,
            bool settled
        )
    {
        Auction storage auction = auctions[_auctionId];
        return (
            auction.seller,
            auction.itemName,
            auction.itemDescription,
            auction.startingPrice,
            auction.currentBid,
            auction.currentBidder,
            auction.auctionEndTime,
            auction.active,
            auction.settled
        );
    }

    function getActiveAuctions() external view returns (uint256[] memory) {
        uint256[] memory activeAuctionIds = new uint256[](auctionCounter);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < auctionCounter; i++) {
            if (auctions[i].active && block.timestamp < auctions[i].auctionEndTime) {
                activeAuctionIds[activeCount] = i;
                activeCount++;
            }
        }

        // Resize array to remove empty slots
        uint256[] memory result = new uint256[](activeCount);
        for (uint256 i = 0; i < activeCount; i++) {
            result[i] = activeAuctionIds[i];
        }

        return result;
    }

    function getPendingRefund(uint256 _auctionId, address _bidder) 
        external 
        view 
        returns (uint256) 
    {
        return pendingReturns[_auctionId][_bidder];
    }

    function getTimeRemaining(uint256 _auctionId) 
        external 
        view 
        auctionExists(_auctionId)
        returns (uint256) 
    {
        if (block.timestamp >= auctions[_auctionId].auctionEndTime) {
            return 0;
        }
        return auctions[_auctionId].auctionEndTime - block.timestamp;
    }

    function getTotalAuctions() external view returns (uint256) {
        return auctionCounter;
    }

    // Platform management functions
    function updatePlatformFee(uint256 _newFeePercentage) 
        external 
        onlyPlatformOwner 
    {
        require(_newFeePercentage <= 1000, "Fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }

    function transferPlatformOwnership(address payable _newOwner) 
        external 
        onlyPlatformOwner 
    {
        require(_newOwner != address(0), "New owner cannot be zero address");
        platformOwner = _newOwner;
    }
}
