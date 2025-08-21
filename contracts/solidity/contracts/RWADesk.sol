// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

/// @title RWAEscrow: Real-World Asset Escrow Contract
/// @author 
/// @notice Allows sellers to escrow ERC20 or ERC721 assets, accept USDC bids, and close escrows to release
/// the asset to the winning bidder while managing refunds for losing bidders.
/// @dev Uses OpenZeppelin Ownable for access control and ReentrancyGuard for safe fund transfers.

contract RWAEscrow is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Type of asset being escrowed
    enum AssetType { ERC20, ERC721 }


    /// @notice Represents an individual escrow
    /// @param valuation The minimum accepted bid in USDC (6 decimals)
    /// @param seller Address of the seller receiving funds
    /// @param bidders List of addresses that have placed bids
    /// @param isActive True if the escrow is currently open
    /// @param isCompleted True if escrow has been closed
    /// @param winner Address of the winning bidder after escrow is closed
    /// @param assetType Type of asset held in escrow (ERC20 or ERC721)
    /// @param assetAddress Contract address of the asset
    /// @param amountOrId Amount for ERC20 or tokenId for ERC721
    /// @param assetDeposited True if the asset is currently held in escrow
    /// @param bidOf Mapping from bidder address to current bid amount
    struct Escrow {
        uint256 valuation;           // USDC (6 decimals) or whatever unit you choose
        address seller;              // receives winning funds
        address[] bidders;           // iteration set
        bool isActive;
        bool isCompleted;
        address winner;

        // RWA custody
        AssetType assetType;
        address assetAddress;        // ERC20 or ERC721 contract
        uint256 amountOrId;          // amount (ERC20) or tokenId (ERC721)
        bool assetDeposited;

        // Bids
        mapping(address => uint256) bidOf; // bidder => funded bid (in USDC)
    }

    mapping(bytes32 => Escrow) private escrows;
    uint256 public escrowCount;

    IERC20 public usdc;

    // Events
    /// @notice Emitted when a new escrow is initialized
    /// @param escrowId Unique identifier for the escrow
    /// @param seller Address of the seller
    /// @param assetType Type of asset (ERC20/ERC721)
    /// @param asset Asset contract address
    /// @param amountOrId Amount or tokenId deposited
    event EscrowInitialized(bytes32 indexed escrowId, address indexed seller, AssetType assetType, address asset, uint256 amountOrId);

    /// @notice Emitted when valuation is posted for an escrow
    /// @param escrowId Escrow identifier
    /// @param valuation Posted valuation in USDC
    event ValuationPosted(bytes32 indexed escrowId, uint256 valuation);

    /// @notice Emitted when a bidder places or increases a bid
    /// @param escrowId Escrow identifier
    /// @param bidder Address of the bidder
    /// @param newAmount Current bid amount
    /// @param deltaIn Amount newly transferred to contract
    event BidPlaced(bytes32 indexed escrowId, address indexed bidder, uint256 newAmount, uint256 deltaIn);

    /// @notice Emitted when escrow is successfully closed
    /// @param escrowId Escrow identifier
    /// @param winner Address of winning bidder
    /// @param winningBid Winning bid amount in USDC
    event EscrowClosed(bytes32 indexed escrowId, address indexed winner, uint256 winningBid);

    /// @notice Emitted when escrow is canceled
    /// @param escrowId Escrow identifier
    event EscrowCanceled(bytes32 indexed escrowId);

    /// @notice Emitted when an escrowed asset is released
    /// @param escrowId Escrow identifier
    /// @param to Recipient of the asset
    event AssetReleased(bytes32 indexed escrowId, address to);

    /// @notice Deploys the escrow contract with a USDC token address
    /// @param _usdcToken ERC20 USDC token contract
    constructor(address _usdcToken) Ownable(msg.sender) {
        usdc = IERC20(_usdcToken);
    }

    /// @notice Initializes a new escrow with an ERC20 asset
    /// @dev Seller must approve this contract for `amount` before calling
    /// @param asset ERC20 token address
    /// @param amount Number of tokens to deposit
    /// @return escrowId Unique identifier for the escrow
    function initEscrowERC20(address asset, uint256 amount) external returns (bytes32 escrowId) {
        require(asset != address(0), "asset=0");
        require(amount > 0, "amount=0");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        escrowId = _newEscrowId();
        Escrow storage e = escrows[escrowId];

        e.seller = msg.sender;
        e.isActive = true;
        e.assetType = AssetType.ERC20;
        e.assetAddress = asset;
        e.amountOrId = amount;
        e.assetDeposited = true;

        emit EscrowInitialized(escrowId, msg.sender, AssetType.ERC20, asset, amount);

        return escrowId;
    }

    /// @notice Initializes a new escrow with an ERC721 asset
    /// @dev Seller must approve this contract for `tokenId` before calling
    /// @param asset ERC721 token address
    /// @param tokenId Token ID to deposit
    /// @return escrowId Unique identifier for the escrow
    function initEscrowERC721(address asset, uint256 tokenId) external nonReentrant returns (bytes32 escrowId) {
        require(asset != address(0), "asset=0");
        IERC721(asset).safeTransferFrom(msg.sender, address(this), tokenId); // will call onERC721Received

        escrowId = _newEscrowId();
        Escrow storage e = escrows[escrowId];

        e.seller = msg.sender;
        e.isActive = true;
        e.assetType = AssetType.ERC721;
        e.assetAddress = asset;
        e.amountOrId = tokenId;
        e.assetDeposited = true;

        emit EscrowInitialized(escrowId, msg.sender, AssetType.ERC721, asset, tokenId);

        return escrowId;
    }

    /// @notice Required callback to receive ERC721 tokens via safeTransferFrom
    /// @return selector IERC721Receiver.onERC721Received.selector
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice Sets the minimum valuation for an escrow
    /// @dev Only callable by the contract owner (desk)
    /// @param escrowId Escrow identifier
    /// @param valuation Minimum bid amount in USDC
    function postValuation(bytes32 escrowId, uint256 valuation) external onlyOwner {
        Escrow storage e = escrows[escrowId];
        require(e.isActive, "Inactive escrow");
        require(e.valuation == 0, "Valuation set");
        e.valuation = valuation;
        emit ValuationPosted(escrowId, valuation);
    }

    /// @notice Place or increase a bid for an escrow
    /// @dev Caller must have approved USDC transfer for the delta amount
    /// @param escrowId Escrow identifier
    /// @param newAmount New total bid amount (must be greater than previous)
    function bid(bytes32 escrowId, uint256 newAmount) external nonReentrant {
        Escrow storage e = escrows[escrowId];
        require(e.isActive, "Inactive escrow");
        require(e.valuation != 0, "Valuation not set");
        require(newAmount > 0, "Zero bid");
        require(newAmount >= e.valuation, "Under posted valuation");

        uint256 prev = e.bidOf[msg.sender];
        require(newAmount > prev, "Must increase bid");
        uint256 delta = newAmount - prev;

        // Pull only the delta
        usdc.safeTransferFrom(msg.sender, address(this), delta);

        // First-time bidder? track them
        if (prev == 0) {
            e.bidders.push(msg.sender);
        }

        e.bidOf[msg.sender] = newAmount;

        emit BidPlaced(escrowId, msg.sender, newAmount, delta);
    }

    /// @notice Closes the escrow, pays the seller, refunds losing bidders, and releases asset to winner
    /// @param escrowId Escrow identifier
    function closeEscrow(bytes32 escrowId) external {
        Escrow storage e = escrows[escrowId];
        require(e.isActive, "Inactive");
        require(!e.isCompleted, "Completed");
        require(e.assetDeposited, "No asset");
        require(e.bidders.length > 0, "No bids placed"); // prevent closing empty escrow

        // find highest
        uint256 highest = 0;
        address winner_;
        uint256 len = e.bidders.length;
        for (uint256 i = 0; i < len; i++) {
            address b = e.bidders[i];
            uint256 amt = e.bidOf[b];
            if (amt > highest) { highest = amt; winner_ = b; }
        }
        require(highest > 0, "No bids");

        // pay seller from winner funds
        usdc.safeTransfer(e.seller, highest);

        // refund losers
        for (uint256 i = 0; i < len; i++) {
            address b = e.bidders[i];
            if (b == winner_) continue;
            uint256 refund = e.bidOf[b];
            if (refund > 0) {
                e.bidOf[b] = 0; // effects before interactions
                usdc.safeTransfer(b, refund);
            }
        }

        // release asset to winner
        _releaseAssetTo(e, winner_);

        e.isActive = false;
        e.isCompleted = true;
        e.winner = winner_;

        emit EscrowClosed(escrowId, winner_, highest);
    }

    /// @notice Cancels an escrow and refunds all bidders
    /// @dev Only the owner or the seller (if no bids) can cancel
    /// @param escrowId Escrow identifier
    function cancelEscrow(bytes32 escrowId) external {
        Escrow storage e = escrows[escrowId];
        require(e.isActive, "Inactive");
        require(!e.isCompleted, "Completed");

        // Only owner or seller (if no bids) can cancel
        bool isOwner = owner() == msg.sender;
        bool isSeller = e.seller == msg.sender && e.bidders.length == 0;
        require(isOwner || isSeller, "Not authorized or bids exist");

        // refund all
        uint256 len = e.bidders.length;
        for (uint256 i = 0; i < len; i++) {
            address b = e.bidders[i];
            uint256 refund = e.bidOf[b];
            if (refund > 0) {
                e.bidOf[b] = 0;
                usdc.safeTransfer(b, refund);
            }
        }

        // return asset to seller
        _releaseAssetTo(e, e.seller);

        e.isActive = false;
        emit EscrowCanceled(escrowId);
    }

    /// @notice Returns metadata of an escrow
    /// @param escrowId Escrow identifier
    /// @return valuation Minimum bid
    /// @return seller Seller address
    /// @return isActive True if escrow is open
    /// @return isCompleted True if escrow is closed
    /// @return winner Address of winning bidder
    /// @return bidderCount Number of bidders
    /// @return assetType ERC20/ERC721
    /// @return assetAddress Address of the asset
    /// @return amountOrId Amount (ERC20) or tokenId (ERC721)
    function getEscrowMeta(bytes32 escrowId)
        external
        view
        returns (uint256 valuation, address seller, bool isActive, bool isCompleted, address winner, uint256 bidderCount,
                 AssetType assetType, address assetAddress, uint256 amountOrId)
    {
        Escrow storage e = escrows[escrowId];
        return (
            e.valuation, e.seller, e.isActive, e.isCompleted, e.winner, e.bidders.length,
            e.assetType, e.assetAddress, e.amountOrId
        );
    }

    /// @notice Returns the current bid of a given bidder
    /// @param escrowId Escrow identifier
    /// @param bidder Bidder address
    /// @return Current bid amount
    function bidOf(bytes32 escrowId, address bidder) external view returns (uint256) {
        return escrows[escrowId].bidOf[bidder];
    }

    /// @notice Generates a new unique escrow identifier
    /// @dev Internal function
    function _newEscrowId() internal returns (bytes32 id) {
        unchecked { escrowCount++; }
        id = keccak256(abi.encodePacked(escrowCount));
    }

    /// @notice Transfers escrowed asset to a given address
    /// @dev Internal functions handling ERC20 and ERC721
    function _releaseAssetTo(Escrow storage e, address to) internal {
        if (!e.assetDeposited) return;
        e.assetDeposited = false;
        if (e.assetType == AssetType.ERC20) {
            _releaseERC20(e.assetAddress, to, e.amountOrId);
        } else if (e.assetType == AssetType.ERC721) {
            _releaseERC721(e.assetAddress, to, e.amountOrId);
        }
    }

    function _releaseERC20(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function _releaseERC721(address token, address to, uint256 tokenId) internal {
        IERC721(token).safeTransferFrom(address(this), to, tokenId);
    }

}