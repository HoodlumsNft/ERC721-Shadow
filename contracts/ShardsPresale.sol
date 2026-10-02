// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title ShardsPresale
 * @notice Accepts native APE toward the $SHARDS presale and records each wallet's entitlement.
 *         Does not hold or transfer $SHARDS; distribution is handled off-chain from the
 *         `contributed` ledger once the sale is paused.
 *
 * Round 1 [saleStart, round1End): Hoodlums holders only, at round1PricePerToken.
 * Round 2 [round1End, ...): open to everyone, at round2PricePerToken, no end date.
 * No total raise cap. The owner ends the sale by calling pause(), which also unlocks withdraw().
 */
contract ShardsPresale is Ownable2Step, Pausable, ReentrancyGuard {
    /// @notice NFT collection gating Round 1.
    IERC721 public immutable hoodlums;

    /// @notice Wei of APE per 1e18 $SHARDS during Round 1.
    uint256 public immutable round1PricePerToken;

    /// @notice Wei of APE per 1e18 $SHARDS during Round 2.
    uint256 public immutable round2PricePerToken;

    /// @notice Max $SHARDS (18 decimals) one wallet may be allocated, both rounds combined.
    uint256 public immutable perWalletCap;

    uint256 public immutable saleStart;
    uint256 public immutable round1End;

    /// @notice $SHARDS (18 decimals) allocated to each wallet.
    mapping(address => uint256) public contributed;

    uint256 public totalSold;
    uint256 public totalRaised;
    uint256 public totalWithdrawn;

    event Contributed(address indexed buyer, uint256 apePaid, uint256 tokensOwed, uint256 refunded, uint8 round);
    event Withdrawn(address indexed to, uint256 amount);

    error SaleNotOpen();
    error NotAHoodlumsHolder();
    error ZeroContribution();
    error WalletCapReached();
    error SaleStillActive();
    error InsufficientBalance();
    error TransferFailed();
    error ZeroAddress();
    error InvalidConfig();

    constructor(
        address hoodlums_,
        address initialOwner_,
        uint256 round1PricePerToken_,
        uint256 round2PricePerToken_,
        uint256 perWalletCap_,
        uint256 saleStart_,
        uint256 round1End_
    ) Ownable(initialOwner_) {
        if (hoodlums_ == address(0)) revert ZeroAddress();
        if (round1PricePerToken_ == 0 || round2PricePerToken_ == 0 || perWalletCap_ == 0) revert InvalidConfig();
        if (round2PricePerToken_ < round1PricePerToken_) revert InvalidConfig();
        if (saleStart_ >= round1End_) revert InvalidConfig();

        hoodlums = IERC721(hoodlums_);
        round1PricePerToken = round1PricePerToken_;
        round2PricePerToken = round2PricePerToken_;
        perWalletCap = perWalletCap_;
        saleStart = saleStart_;
        round1End = round1End_;
    }

    function _currentPrice() private view returns (uint256) {
        return block.timestamp < round1End ? round1PricePerToken : round2PricePerToken;
    }

    /// @notice Buy into the presale. Refunds any APE beyond the wallet's remaining cap.
    function contribute() external payable nonReentrant whenNotPaused {
        if (block.timestamp < saleStart) revert SaleNotOpen();
        bool inRound1 = block.timestamp < round1End;
        if (inRound1 && hoodlums.balanceOf(msg.sender) == 0) revert NotAHoodlumsHolder();
        if (msg.value == 0) revert ZeroContribution();

        uint256 remainingWallet = perWalletCap - contributed[msg.sender];
        if (remainingWallet == 0) revert WalletCapReached();

        uint256 price = _currentPrice();
        uint256 requestedTokens = (msg.value * 1e18) / price;
        uint256 grantedTokens = requestedTokens > remainingWallet ? remainingWallet : requestedTokens;

        uint256 apeUsed = (grantedTokens * price) / 1e18;
        uint256 refund = msg.value - apeUsed;

        contributed[msg.sender] += grantedTokens;
        totalSold += grantedTokens;
        totalRaised += apeUsed;

        emit Contributed(msg.sender, apeUsed, grantedTokens, refund, inRound1 ? 1 : 2);

        if (refund > 0) {
            (bool ok,) = msg.sender.call{value: refund}("");
            if (!ok) revert TransferFailed();
        }
    }

    /// @notice Owner-only. Available once the sale is paused.
    function withdraw(address payable to, uint256 amount) external onlyOwner {
        if (!paused()) revert SaleStillActive();
        if (to == address(0)) revert ZeroAddress();
        if (amount > totalRaised - totalWithdrawn) revert InsufficientBalance();
        totalWithdrawn += amount;
        emit Withdrawn(to, amount);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---- views ----

    /// @notice 0 = not started, 1 = Round 1, 2 = Round 2.
    function currentRound() external view returns (uint8) {
        if (block.timestamp < saleStart) return 0;
        return block.timestamp < round1End ? 1 : 2;
    }

    function currentPrice() external view returns (uint256) {
        return _currentPrice();
    }

    function remainingWalletCap(address wallet) external view returns (uint256) {
        uint256 c = contributed[wallet];
        return c >= perWalletCap ? 0 : perWalletCap - c;
    }

    /// @notice $SHARDS `apeAmount` would grant `wallet` right now, after the wallet cap.
    function previewTokensOut(address wallet, uint256 apeAmount) external view returns (uint256) {
        if (paused() || block.timestamp < saleStart) return 0;
        if (block.timestamp < round1End && hoodlums.balanceOf(wallet) == 0) return 0;

        uint256 c = contributed[wallet];
        uint256 remainingWallet = c >= perWalletCap ? 0 : perWalletCap - c;

        uint256 tokens = (apeAmount * 1e18) / _currentPrice();
        if (tokens > remainingWallet) tokens = remainingWallet;
        return tokens;
    }
}
