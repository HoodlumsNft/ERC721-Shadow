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
 *         backend repo), once the team manually calls pause() to end the sale. Keeping token
 *         transfer/minting logic out of this contract entirely removes a whole class of ERC20
 *         interaction risk from something meant to ship without a paid third-party audit — the
 *         only asset this contract ever custodies is native APE, and the only thing it can do with
 *         it is refund overpayment or let the owner withdraw once the sale is paused.
 *
 * Deliberately open-ended, by design (target is "raise 100k+ APE," not "raise exactly 100k and
 * stop"):
 *   - No total raise cap. There's no ceiling the sale auto-stops at — if demand is strong, it just
 *     keeps raising. The only hard limit left is perWalletCap, per wallet, per round.
 *   - No fixed end date. Round 1 [saleStart, round1End) is time-boxed (Hoodlums holders only);
 *     Round 2 [round1End, forever) is open to everyone and runs until the team ends it by calling
 *     pause() — there is no saleEnd timestamp to race against. pause() is the only "stop" switch,
 *     and once paused, every contribution is final and withdraw() unlocks for the real airdrop.
 *   - Two prices, not one. Round 1 (holders) gets round1PricePerToken; Round 2 (public) gets
 *     round2PricePerToken, normally set higher — holders who show up first get the better price,
 *     everyone else pays a bit more. Both are immutable, set once at deploy.
 *
 * perWalletCap is still flat token units, identical for every wallet within a round, deliberately
 * NOT tiered by NFT holdings — no on-chain snapshot/tier logic to get wrong. Because Round 2's
 * price is higher, the same token cap naturally lets a Round 2 buyer spend more APE before hitting
 * it than a Round 1 buyer would at the lower price — a side effect of the pricing, not a separate
 * per-round cap to configure.
 */
contract ShardsPresale is Ownable2Step, Pausable, ReentrancyGuard {
    /// @notice Hoodlums NFT collection gating Round 1. Holding is checked live, not snapshotted —
    ///         a deliberate simplification: this gates the right to PAY real APE for a fixed-price
    ///         allocation, not a free mint, so there's no meaningful incentive to game it.
    IERC721 public immutable hoodlums;

    /// @notice Wei of APE required per 1e18 (one whole token) of $SHARDS, during Round 1 (Hoodlums holders only).
    uint256 public immutable round1PricePerToken;

    /// @notice Wei of APE required per 1e18 of $SHARDS, during Round 2 (public) — normally >= round1PricePerToken.
    uint256 public immutable round2PricePerToken;

    /// @notice Flat per-wallet cap, in $SHARDS units — identical for every wallet, both rounds, no holdings-based tiering.
    uint256 public immutable perWalletCap;

    uint256 public immutable saleStart;
    uint256 public immutable round1End; // Round 1 = [saleStart, round1End); Round 2 = [round1End, ...), no fixed end.

    /// @notice $SHARDS (18-decimal units) each wallet has purchased — the source of truth the later airdrop reads from.
    mapping(address => uint256) public contributed;

    /// @notice Cumulative $SHARDS (18-decimal units) sold so far — informational only, nothing is ever clamped against it.
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
    error WalletCapReached();
    error SaleStillActive();
    error InsufficientBalance();
    error TransferFailed();
    error ZeroAddress();
    error InvalidConfig();

    /// @dev `Ownable(initialOwner_)` already reverts on a zero owner before this body runs.
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

    /// @dev Round 1 = [saleStart, round1End); Round 2 = [round1End, ...) forever, no auto-end.
    function _currentPrice() private view returns (uint256) {
        return block.timestamp < round1End ? round1PricePerToken : round2PricePerToken;
    }

    /**
     * @notice Buy into the presale. Accepts up to the caller's own perWalletCap, refunding any APE
     *         sent beyond that in the same transaction — so sending more than you can actually be
     *         allocated is never a costly mistake. No total-raise cap: whatever real demand shows
     *         up, this keeps accepting it until the team ends the sale with pause().
     */
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

        // Converting back to APE (rather than reusing msg.value directly) intentionally re-floors
        // through the same integer division — grantedTokens is the authoritative ledger value, so
        // apeUsed can only ever be <= msg.value, never more. Any wei-level rounding this produces
        // just becomes a slightly larger refund below, always in the buyer's favor.
        uint256 apeUsed = (grantedTokens * price) / 1e18;
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

    /**
     * @notice Owner-only, only once the sale is paused — withdraw collected APE for LP seeding /
     *         operations (call it as many times as needed, e.g. once per destination for the
     *         LP/ops split). Gated on `paused()` rather than a timestamp: there's no saleEnd to
     *         compare against anymore, and nothing here is unsafe to buyers either way — what each
     *         wallet is owed lives entirely in the `contributed` ledger, independent of when the
     *         APE itself leaves the contract.
     */
    function withdraw(address payable to, uint256 amount) external onlyOwner {
        if (!paused()) revert SaleStillActive();
        if (to == address(0)) revert ZeroAddress();
        if (amount > totalRaised - totalWithdrawn) revert InsufficientBalance();
        totalWithdrawn += amount;
        emit Withdrawn(to, amount);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Stops new contributions. This is the sale's only "end" mechanism — there is no
    ///         saleEnd timestamp. Once paused, withdraw() unlocks and the off-chain airdrop script
    ///         treats the `contributed` ledger as final.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resumes contributions after a pause. Only meant for a genuine "we paused briefly
    ///         and the sale isn't actually over" case — once the team has started withdrawing /
    ///         airdropping against a paused snapshot, unpausing and accepting more contributions
    ///         would make the ledger inconsistent with what's already been paid out, so treat
    ///         pause() as final in practice once withdraw()/the airdrop script have run.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ---- views ----

    /// @notice 0 = not started yet, 1 = Round 1 (holders only), 2 = Round 2 (public) — stays 2
    ///         forever once reached, whether or not the sale is currently paused (see paused()).
    function currentRound() external view returns (uint8) {
        if (block.timestamp < saleStart) return 0;
        return block.timestamp < round1End ? 1 : 2;
    }

    /// @notice The price (wei of APE per 1e18 $SHARDS) a contribute() call would use right now.
    function currentPrice() external view returns (uint256) {
        return _currentPrice();
    }

    function remainingWalletCap(address wallet) external view returns (uint256) {
        uint256 c = contributed[wallet];
        return c >= perWalletCap ? 0 : perWalletCap - c;
    }

    /// @notice Convenience for the frontend — how many $SHARDS `apeAmount` would actually grant
    ///         `wallet` right now, after the wallet cap clamps it (0 if the sale isn't open to them
    ///         at all, including while paused).
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
