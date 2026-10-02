// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Subset of delegate.xyz's DelegateRegistry v2 used to honor wallet delegation.
interface IDelegateRegistry {
    function checkDelegateForAll(address to, address from, bytes32 rights) external view returns (bool);
    function checkDelegateForContract(address to, address from, address contract_, bytes32 rights) external view returns (bool);
}

/**
 * @title ShardsPresale
 * @notice Accepts native APE toward the $SHARDS presale and records each wallet's entitlement.
 *         Does not hold or transfer $SHARDS; distribution is handled off-chain from the
 *         `contributed` ledger once the sale is paused.
 *
 * One sale, priced by holder status: a wallet holding >=1 Hoodlum pays holderPricePerToken,
 * everyone else pays publicPricePerToken. A caller may also pass a `vault` address delegating
 * Hoodlums rights to them via delegate.xyz (e.g. a Glyph hot wallet acting for a cold vault) to
 * get the holder price without holding a Hoodlum directly; whole-wallet or whole-collection
 * delegations are honored, not single-token delegations. No total raise cap. The owner ends the
 * sale by calling pause(), which also unlocks withdraw().
 */
contract ShardsPresale is Ownable2Step, Pausable, ReentrancyGuard {
    /// @notice delegate.xyz DelegateRegistry v2 — identical address on every EVM chain it's deployed to.
    IDelegateRegistry public constant DELEGATE_REGISTRY = IDelegateRegistry(0x00000000000000447e69651d841bD8D104Bed493);

    /// @notice NFT collection determining which price a wallet pays.
    IERC721 public immutable hoodlums;

    /// @notice Wei of APE per 1e18 $SHARDS for a wallet holding >=1 Hoodlum (directly or via delegation).
    uint256 public immutable holderPricePerToken;

    /// @notice Wei of APE per 1e18 $SHARDS for a wallet holding no Hoodlums.
    uint256 public immutable publicPricePerToken;

    /// @notice Max $SHARDS (18 decimals) one wallet may be allocated.
    uint256 public immutable perWalletCap;

    uint256 public immutable saleStart;

    /// @notice $SHARDS (18 decimals) allocated to each wallet.
    mapping(address => uint256) public contributed;

    uint256 public totalSold;
    uint256 public totalRaised;
    uint256 public totalWithdrawn;

    event Contributed(address indexed buyer, uint256 apePaid, uint256 tokensOwed, uint256 refunded, bool isHolder);
    event Withdrawn(address indexed to, uint256 amount);

    error SaleNotOpen();
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
        uint256 holderPricePerToken_,
        uint256 publicPricePerToken_,
        uint256 perWalletCap_,
        uint256 saleStart_
    ) Ownable(initialOwner_) {
        if (hoodlums_ == address(0)) revert ZeroAddress();
        if (holderPricePerToken_ == 0 || publicPricePerToken_ == 0 || perWalletCap_ == 0) revert InvalidConfig();
        if (publicPricePerToken_ < holderPricePerToken_) revert InvalidConfig();

        hoodlums = IERC721(hoodlums_);
        holderPricePerToken = holderPricePerToken_;
        publicPricePerToken = publicPricePerToken_;
        perWalletCap = perWalletCap_;
        saleStart = saleStart_;
    }

    /// @dev `vault` is self-declared by the caller, not looked up on-chain — it is only ever
    ///      trusted after the registry itself confirms that vault delegated to `wallet`, and even
    ///      then only counts if that vault currently holds a Hoodlum. A wallet with no real
    ///      delegation gains nothing by passing an arbitrary address here.
    function _isHolder(address wallet, address vault) private view returns (bool) {
        if (hoodlums.balanceOf(wallet) > 0) return true;
        if (vault == address(0) || hoodlums.balanceOf(vault) == 0) return false;
        return DELEGATE_REGISTRY.checkDelegateForAll(wallet, vault, "")
            || DELEGATE_REGISTRY.checkDelegateForContract(wallet, vault, address(hoodlums), "");
    }

    function _priceFor(address wallet, address vault) private view returns (uint256) {
        return _isHolder(wallet, vault) ? holderPricePerToken : publicPricePerToken;
    }

    /// @notice Buy into the presale. Pass `vault` (or address(0) if none) to claim the holder price
    ///         via a delegate.xyz delegation instead of holding a Hoodlum directly. Refunds any APE
    ///         sent beyond the wallet's remaining cap.
    function contribute(address vault) external payable nonReentrant whenNotPaused {
        if (block.timestamp < saleStart) revert SaleNotOpen();
        if (msg.value == 0) revert ZeroContribution();

        uint256 remainingWallet = perWalletCap - contributed[msg.sender];
        if (remainingWallet == 0) revert WalletCapReached();

        bool isHolder = _isHolder(msg.sender, vault);
        uint256 price = isHolder ? holderPricePerToken : publicPricePerToken;
        uint256 requestedTokens = (msg.value * 1e18) / price;
        uint256 grantedTokens = requestedTokens > remainingWallet ? remainingWallet : requestedTokens;

        uint256 apeUsed = (grantedTokens * price) / 1e18;
        uint256 refund = msg.value - apeUsed;

        contributed[msg.sender] += grantedTokens;
        totalSold += grantedTokens;
        totalRaised += apeUsed;

        emit Contributed(msg.sender, apeUsed, grantedTokens, refund, isHolder);

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

    function priceFor(address wallet, address vault) external view returns (uint256) {
        return _priceFor(wallet, vault);
    }

    function remainingWalletCap(address wallet) external view returns (uint256) {
        uint256 c = contributed[wallet];
        return c >= perWalletCap ? 0 : perWalletCap - c;
    }

    /// @notice $SHARDS `apeAmount` would grant `wallet` right now, after the wallet cap.
    function previewTokensOut(address wallet, address vault, uint256 apeAmount) external view returns (uint256) {
        if (paused() || block.timestamp < saleStart) return 0;
        uint256 c = contributed[wallet];
        uint256 remainingWallet = c >= perWalletCap ? 0 : perWalletCap - c;
        uint256 tokens = (apeAmount * 1e18) / _priceFor(wallet, vault);
        if (tokens > remainingWallet) tokens = remainingWallet;
        return tokens;
    }
}
