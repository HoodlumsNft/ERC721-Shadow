// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title ShardsPresale
 * @notice Raises native APE for the $SHARDS presale. Deliberately "raise first, airdrop later":
 *         this contract never touches the $SHARDS token at all — it only accepts APE and records
 *         how many tokens each wallet is owed. Distribution happens afterward, off-chain, driven
 *         by the `contributed` ledger this contract keeps (see scripts/airdrop-presale.ts in the
 *         backend repo). Keeping token transfer/minting logic out of this contract entirely
 *         removes a whole class of ERC20 interaction risk from something meant to ship without a
 *         paid third-party audit — the only asset this contract ever custodies is native APE, and
 *         the only thing it can do with it is refund overpayment or let the owner withdraw after
 *         the sale ends.
 *
 * Two rounds, back to back, at one fixed price and one flat per-wallet cap — deliberately NOT
 * tiered by NFT holdings, so there's no on-chain snapshot/tier logic to get wrong and every
 * wallet is treated identically once it's eligible:
 *   - Round 1 [saleStart, round1End): caller must hold >=1 Hoodlums NFT at the moment they call.
 *   - Round 2 [round1End, saleEnd): open to everyone, same price, same cap.
 *
 * All three timestamps, the price, and both caps are immutable — set once in the constructor, the
 * owner can never move the goalposts once deployed. The owner can pause() new contributions in an
 * emergency (refunds still aren't needed since none are owed yet — contribute() is simply
 * unavailable while paused) and can withdraw collected APE only after saleEnd, once every
 * contribution is final.
 */
contract ShardsPresale is Ownable2Step, Pausable, ReentrancyGuard {
    /// @notice Hoodlums NFT collection gating Round 1. Holding is checked live, not snapshotted —
    ///         a deliberate simplification: this gates the right to PAY real APE for a fixed-price
    ///         allocation, not a free mint, so there's no meaningful incentive to game it.
    IERC721 public immutable hoodlums;

    /// @notice Wei of APE required per 1e18 (one whole token) of $SHARDS. Fixed for the life of
    ///         the sale — see the constructor for how this and every other parameter is set once.
    uint256 public immutable pricePerToken;

    /// @notice Total $SHARDS (18-decimal units) this presale will ever record as sold, across both rounds combined.
    uint256 public immutable totalCap;

    /// @notice Flat per-wallet cap, in $SHARDS units — identical for every wallet, both rounds, no holdings-based tiering.
    uint256 public immutable perWalletCap;

    uint256 public immutable saleStart;
    uint256 public immutable round1End; // Round 1 = [saleStart, round1End); Round 2 = [round1End, saleEnd)
    uint256 public immutable saleEnd;

    /// @notice $SHARDS (18-decimal units) each wallet has purchased — the source of truth the later airdrop reads from.
    mapping(address => uint256) public contributed;

    /// @notice Cumulative $SHARDS (18-decimal units) sold so far, capped at totalCap.
    uint256 public totalSold;

    /// @notice Cumulative APE actually collected (net of refunds) — what withdraw() can ever pay out.
    uint256 public totalRaised;

    /// @notice APE already withdrawn by the owner — tracked separately from totalRaised so withdraw() can never pay out twice.
    uint256 public totalWithdrawn;

    event Contributed(address indexed buyer, uint256 apePaid, uint256 tokensOwed, uint256 refunded, uint8 round);
    event Withdrawn(address indexed to, uint256 amount);

    error SaleNotOpen();
    error NotAHoodlumsHolder();
    error ZeroContribution();
    error CapReached();
    error WalletCapReached();
    error TooEarlyToWithdraw();
    error InsufficientBalance();
    error TransferFailed();
    error ZeroAddress();
    error InvalidConfig();

    /// @dev `Ownable(initialOwner_)` already reverts on a zero owner before this body runs.
    constructor(
        address hoodlums_,
        address initialOwner_,
        uint256 pricePerToken_,
        uint256 totalCap_,
        uint256 perWalletCap_,
        uint256 saleStart_,
        uint256 round1End_,
        uint256 saleEnd_
    ) Ownable(initialOwner_) {
        if (hoodlums_ == address(0)) revert ZeroAddress();
        if (pricePerToken_ == 0 || totalCap_ == 0 || perWalletCap_ == 0) revert InvalidConfig();
        if (!(saleStart_ < round1End_ && round1End_ < saleEnd_)) revert InvalidConfig();

        hoodlums = IERC721(hoodlums_);
        pricePerToken = pricePerToken_;
        totalCap = totalCap_;
        perWalletCap = perWalletCap_;
        saleStart = saleStart_;
        round1End = round1End_;
        saleEnd = saleEnd_;
    }

    /**
     * @notice Buy into the presale. Accepts up to whatever's left of totalCap and the caller's own
     *         perWalletCap, refunding any APE sent beyond that in the same transaction — so
     *         sending more than you can actually be allocated is never a costly mistake.
     */
    function contribute() external payable nonReentrant whenNotPaused {
        if (block.timestamp < saleStart || block.timestamp >= saleEnd) revert SaleNotOpen();
        bool inRound1 = block.timestamp < round1End;
        if (inRound1 && hoodlums.balanceOf(msg.sender) == 0) revert NotAHoodlumsHolder();
        if (msg.value == 0) revert ZeroContribution();

        uint256 remainingTotal = totalCap - totalSold;
        if (remainingTotal == 0) revert CapReached();
        uint256 remainingWallet = perWalletCap - contributed[msg.sender];
        if (remainingWallet == 0) revert WalletCapReached();

        uint256 requestedTokens = (msg.value * 1e18) / pricePerToken;
        uint256 grantedTokens = requestedTokens;
        if (grantedTokens > remainingTotal) grantedTokens = remainingTotal;
        if (grantedTokens > remainingWallet) grantedTokens = remainingWallet;

        // Converting back to APE (rather than reusing msg.value directly) intentionally re-floors
        // through the same integer division — grantedTokens is the authoritative ledger value, so
        // apeUsed can only ever be <= msg.value, never more. Any wei-level rounding this produces
        // just becomes a slightly larger refund below, always in the buyer's favor.
        uint256 apeUsed = (grantedTokens * pricePerToken) / 1e18;
        uint256 refund = msg.value - apeUsed;

        // Effects before interaction (the refund call below) — standard checks-effects-interactions;
        // nonReentrant above is defense-in-depth on top of that, not a substitute for it.
        contributed[msg.sender] += grantedTokens;
        totalSold += grantedTokens;
        totalRaised += apeUsed;

        emit Contributed(msg.sender, apeUsed, grantedTokens, refund, inRound1 ? 1 : 2);

        if (refund > 0) {
            (bool ok,) = msg.sender.call{value: refund}("");
            if (!ok) revert TransferFailed();
        }
    }

    /// @notice Owner-only, only after the sale ends — withdraw collected APE for LP seeding / operations.
    function withdraw(address payable to, uint256 amount) external onlyOwner {
        if (block.timestamp < saleEnd) revert TooEarlyToWithdraw();
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

    /// @notice 0 = closed (before start or after end), 1 = Round 1 (holders only), 2 = Round 2 (public).
    function currentRound() external view returns (uint8) {
        if (block.timestamp < saleStart || block.timestamp >= saleEnd) return 0;
        return block.timestamp < round1End ? 1 : 2;
    }

    function remainingCap() external view returns (uint256) {
        return totalCap - totalSold;
    }

    function remainingWalletCap(address wallet) external view returns (uint256) {
        uint256 c = contributed[wallet];
        return c >= perWalletCap ? 0 : perWalletCap - c;
    }

    /// @notice Convenience for the frontend — how many $SHARDS `apeAmount` would actually grant
    ///         `wallet` right now, after both caps clamp it (0 if the sale isn't open to them at all).
    function previewTokensOut(address wallet, uint256 apeAmount) external view returns (uint256) {
        if (block.timestamp < saleStart || block.timestamp >= saleEnd) return 0;
        if (block.timestamp < round1End && hoodlums.balanceOf(wallet) == 0) return 0;

        uint256 remainingTotal = totalCap - totalSold;
        uint256 c = contributed[wallet];
        uint256 remainingWallet = c >= perWalletCap ? 0 : perWalletCap - c;

        uint256 tokens = (apeAmount * 1e18) / pricePerToken;
        if (tokens > remainingTotal) tokens = remainingTotal;
        if (tokens > remainingWallet) tokens = remainingWallet;
        return tokens;
    }
}
