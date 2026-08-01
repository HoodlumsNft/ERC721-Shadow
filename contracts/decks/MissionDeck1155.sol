// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MissionDeck1155
 * @notice Hoodlums: Blacknet — paid Mission Decks, the game's monetization
 *         layer. See blacknet/docs/game.md §9 for the 5 tiers (Street is
 *         free/off-chain and never minted here; Runner/Ghost/Wraith/Apex are
 *         tiers 1-4 on this contract).
 *
 * Two ways to acquire a paid deck, both priced in native APE:
 *  - purchase(tier): guaranteed tier, price is admin-configurable per tier so
 *    it can be retuned post-launch without a redeploy.
 *  - openPack(...): a cheaper "Blacknet Pack" that resolves to a random tier.
 *    Tier weighting is inherently random and, same trust split as
 *    BlackMarketCompiler, comes from a backend-signed EIP-712 proof rather
 *    than on-chain randomness — the contract only ever mints what a
 *    `packSigner`-signed proof says, and each packId can only be opened once.
 *
 * balanceOf(user, tier) IS the on-chain record of which decks a user owns —
 * no separate ownership mapping needed.
 */
contract MissionDeck1155 is ERC1155, Ownable, EIP712, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MIN_TIER = 1; // Runner
    uint256 public constant MAX_TIER = 4; // Apex

    bytes32 public constant OPEN_PACK_TYPEHASH =
        keccak256("OpenPack(address buyer,uint256 packId,uint256 tier,uint256 price,uint256 deadline)");

    /// @notice Backend signer that rolls + signs pack outcomes.
    address public packSigner;

    /// @notice tier => price in wei (native APE).
    mapping(uint256 => uint256) public price;
    /// @notice price of one Blacknet Pack (random tier).
    uint256 public packPrice;

    /// @notice packId => consumed (replay protection; one mint per signed roll).
    mapping(uint256 => bool) public packClaimed;

    string private _baseURI;

    event PriceUpdated(uint256 indexed tier, uint256 priceWei);
    event PackPriceUpdated(uint256 priceWei);
    event PackSignerUpdated(address indexed signer);
    event DeckPurchased(address indexed buyer, uint256 indexed tier, uint256 pricePaid);
    event PackOpened(address indexed buyer, uint256 indexed packId, uint256 indexed tier, uint256 pricePaid);
    event Withdrawn(address indexed to, uint256 amount);

    error InvalidTier(uint256 tier);
    error WrongPayment(uint256 expected, uint256 sent);
    error PackAlreadyClaimed(uint256 packId);
    error ProofExpired(uint256 deadline);
    error InvalidProof();
    error TransferFailed();

    constructor(address packSigner_, string memory baseURI_)
        ERC1155("")
        Ownable(msg.sender)
        EIP712("Hoodlums Blacknet Decks", "1")
    {
        packSigner = packSigner_;
        _baseURI = baseURI_;

        price[1] = 10 ether; // Runner Deck — 10 APE (native token, 18 decimals)
        price[2] = 25 ether; // Ghost Deck
        price[3] = 55 ether; // Wraith Deck
        price[4] = 100 ether; // Apex Deck
        packPrice = 15 ether; // Blacknet Pack
    }

    /// @notice Buy a guaranteed deck tier.
    function purchase(uint256 tier) external payable nonReentrant {
        if (tier < MIN_TIER || tier > MAX_TIER) revert InvalidTier(tier);
        uint256 cost = price[tier];
        if (msg.value != cost) revert WrongPayment(cost, msg.value);

        _mint(msg.sender, tier, 1, "");
        emit DeckPurchased(msg.sender, tier, cost);
    }

    /// @notice Buy a Blacknet Pack — resolves to a server-rolled random tier.
    function openPack(uint256 packId, uint256 tier, uint256 deadline, bytes calldata proof) external payable nonReentrant {
        if (tier < MIN_TIER || tier > MAX_TIER) revert InvalidTier(tier);
        if (msg.value != packPrice) revert WrongPayment(packPrice, msg.value);
        if (block.timestamp > deadline) revert ProofExpired(deadline);
        if (packClaimed[packId]) revert PackAlreadyClaimed(packId);

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(OPEN_PACK_TYPEHASH, msg.sender, packId, tier, packPrice, deadline))
        );
        if (ECDSA.recover(digest, proof) != packSigner) revert InvalidProof();

        packClaimed[packId] = true;

        _mint(msg.sender, tier, 1, "");
        emit PackOpened(msg.sender, packId, tier, packPrice);
    }

    // ---- admin ----

    function setPrice(uint256 tier, uint256 priceWei) external onlyOwner {
        if (tier < MIN_TIER || tier > MAX_TIER) revert InvalidTier(tier);
        price[tier] = priceWei;
        emit PriceUpdated(tier, priceWei);
    }

    function setPackPrice(uint256 priceWei) external onlyOwner {
        packPrice = priceWei;
        emit PackPriceUpdated(priceWei);
    }

    function setPackSigner(address signer_) external onlyOwner {
        packSigner = signer_;
        emit PackSignerUpdated(signer_);
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseURI = baseURI_;
    }

    function withdraw(address payable to, uint256 amount) external onlyOwner nonReentrant {
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(to, amount);
    }

    // ---- views ----

    function uri(uint256 id) public view override returns (string memory) {
        return string.concat(_baseURI, id.toString(), ".json");
    }
}
