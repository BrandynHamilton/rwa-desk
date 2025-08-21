// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

interface IEncryptedERC20 {
    function confidentialTransfer(address to, uint256 encryptedAmount) external;
    function confidentialBalanceOf(
        address user
    ) external view returns (uint256 encryptedBalance);
    function decryptBalance(
        address user
    ) external view returns (uint256 plainBalance); // only owner/compliance
}

contract RWAEscrow is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum AssetType {
        ERC20,
        ERC721
    }

    struct Escrow {
        uint256 valuation; // USDC (6 decimals) or whatever unit you choose
        address seller; // receives winning funds
        address[] bidders; // iteration set
        bool isActive;
        bool isCompleted;
        address winner;
        // RWA custody
        AssetType assetType;
        address assetAddress; // ERC20 or ERC721 contract
        uint256 amountOrId; // amount (ERC20) or tokenId (ERC721)
        bool assetDeposited;
        // Bids
        mapping(address => bytes32) encryptedBidOf; // bidder => funded bid (in USDC)
    }

    mapping(bytes32 => Escrow) private escrows;
    uint256 public escrowCount;

    IEncryptedERC20 public eusdc; // eERC USDC wrapper

    // Events
    event EscrowInitialized(
        bytes32 indexed escrowId,
        address indexed seller,
        AssetType assetType,
        address asset,
        uint256 amountOrId
    );
    event ValuationPosted(bytes32 indexed escrowId, uint256 valuation);
    event BidPlaced(
        bytes32 indexed escrowId,
        address indexed bidder,
        uint256 newAmount,
        uint256 deltaIn
    );
    event EscrowClosed(
        bytes32 indexed escrowId,
        address indexed winner,
        uint256 winningBid
    );
    event EscrowCanceled(bytes32 indexed escrowId);
    event AssetReleased(bytes32 indexed escrowId, address to);

    constructor(address _eusdcToken) Ownable(msg.sender) {
        eusdc = IEncryptedERC20(_eusdcToken);
    }

    // -------- RWA Custody: initialize with ERC20 asset --------
    // Seller must approve this contract for `amount` before calling.
    function initEscrowERC20(
        address asset,
        uint256 amount
    ) external returns (bytes32 escrowId) {
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

        emit EscrowInitialized(
            escrowId,
            msg.sender,
            AssetType.ERC20,
            asset,
            amount
        );

        return escrowId;
    }

    // -------- RWA Custody: initialize with ERC721 asset --------
    // Seller must approve this contract for `tokenId` before calling.
    function initEscrowERC721(
        address asset,
        uint256 tokenId
    ) external nonReentrant returns (bytes32 escrowId) {
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

        emit EscrowInitialized(
            escrowId,
            msg.sender,
            AssetType.ERC721,
            asset,
            tokenId
        );

        return escrowId;
    }

    // Required to accept safeTransferFrom for ERC721
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // --- Desk sets valuation once (can add an updater if needed) ---
    function postValuation(
        bytes32 escrowId,
        uint256 valuation
    ) external onlyOwner {
        Escrow storage e = escrows[escrowId];
        require(e.isActive, "Inactive escrow");
        require(e.valuation == 0, "Valuation set");
        e.valuation = valuation;
        emit ValuationPosted(escrowId, valuation);
    }

    // --- Place or raise a funded bid in USDC ---
    // Caller must have approved this contract for at least the delta.
    function bidEncrypted(
        bytes32 escrowId,
        bytes32 encryptedBid,
        bytes calldata zkProof
    ) external nonReentrant {
        Escrow storage e = escrows[escrowId];

        require(e.isActive, "Inactive escrow");
        require(e.valuation != 0, "Valuation not set");

        // Verify proof off-chain or on-chain (optional)
        // e.g., zkProof ensures bid >= previous bid & >= valuation

        e.encryptedBidOf[msg.sender] = encryptedBid;

        if (!_isBidder(e, msg.sender)) {
            e.bidders.push(msg.sender);
        }

        emit BidPlaced(escrowId, msg.sender, 0, 0); // plaintext amounts hidden
    }

    // -------- Close: highest funded bid wins; release asset & funds; refund losers --------
    function closeEscrowEncrypted(
        bytes32 escrowId,
        address winner,
        bytes32 encryptedWinningAmount,
        address[] calldata losers,
        bytes32[] calldata encryptedRefunds
    ) external onlyOwner {
        Escrow storage e = escrows[escrowId];
        require(e.isActive, "Inactive");
        require(!e.isCompleted, "Completed");

        // Pay seller
        eusdc.transfer(e.seller, encryptedWinningAmount);

        // Refund losers
        for (uint256 i = 0; i < losers.length; i++) {
            eusdc.transfer(losers[i], encryptedRefunds[i]);
        }

        // Release asset to winner
        _releaseAssetTo(e, winner);

        e.isActive = false;
        e.isCompleted = true;
        e.winner = winner;

        emit EscrowClosed(escrowId, winner, 0); // winning bid hidden
    }

    // -------- Cancel: refunds all bidders; return asset to seller --------
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
                eusdc.confidentialTransfer(b, refund);
            }
        }

        // return asset to seller
        _releaseAssetTo(e, e.seller);

        e.isActive = false;
        emit EscrowCanceled(escrowId);
    }

    // -------- Views --------
    function getEscrowMeta(
        bytes32 escrowId
    )
        external
        view
        returns (
            uint256 valuation,
            address seller,
            bool isActive,
            bool isCompleted,
            address winner,
            uint256 bidderCount,
            AssetType assetType,
            address assetAddress,
            uint256 amountOrId
        )
    {
        Escrow storage e = escrows[escrowId];
        return (
            e.valuation,
            e.seller,
            e.isActive,
            e.isCompleted,
            e.winner,
            e.bidders.length,
            e.assetType,
            e.assetAddress,
            e.amountOrId
        );
    }

    function bidOf(
        bytes32 escrowId,
        address bidder
    ) external view returns (uint256) {
        return escrows[escrowId].bidOf[bidder];
    }

    function decryptBid(
        bytes32 escrowId,
        address bidder
    ) external onlyOwner returns (uint256) {
        return eusdc.decryptBalance(bidder); // returns plaintext
    }

    // -------- Internal helpers --------
    function _newEscrowId() internal returns (bytes32 id) {
        unchecked {
            escrowCount++;
        }
        id = keccak256(abi.encodePacked(escrowCount));
    }

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

    function _releaseERC721(
        address token,
        address to,
        uint256 tokenId
    ) internal {
        IERC721(token).safeTransferFrom(address(this), to, tokenId);
    }

    function _isBidder(
        Escrow storage e,
        address bidder
    ) internal view returns (bool) {
        uint256 len = e.bidders.length;
        for (uint256 i = 0; i < len; i++) {
            if (e.bidders[i] == bidder) {
                return true;
            }
        }
        return false;
    }
}
