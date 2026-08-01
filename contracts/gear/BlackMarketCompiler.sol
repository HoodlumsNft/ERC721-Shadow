// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./GearModule1155.sol";

/**
 * @title BlackMarketCompiler
 * @notice Hoodlums: Blacknet — burns Data Shards per a fixed Recipe, mints a
 *         server-rolled set of Gear Modules, atomically in one transaction.
 *         See blacknet/docs/game.md §7 for the 8 recipes.
 *
 * Trust split, same principle as DataShard1155's claim flow:
 *  - Recipe COSTS live on-chain (owner-configured), so anyone can verify what
 *    a recipe burns without trusting the backend for that part.
 *  - Recipe OUTPUT (count/rarity/category) is inherently random and must come
 *    from a trusted off-chain roll — the backend signs an EIP-712 proof
 *    binding the caller, recipe, a single-use craftId, and the exact output,
 *    with a deadline. The contract only ever mints what that proof says.
 *  - Burn and mint happen in the same call: a player can't get a signed
 *    output proof without also paying its exact recipe cost in the same tx,
 *    and craftId replay is blocked the same way DataShard1155 blocks
 *    runId replay.
 *
 * Data Shards have no burn() (DataShard1155 is a plain ERC-1155C token), so
 * "burning" is a transfer to a fixed, unrecoverable sink address — the
 * standard pattern for consuming a token that was never designed to be
 * burnable. Requires the player to have called
 * DataShard1155.setApprovalForAll(compiler, true) once.
 */
contract BlackMarketCompiler is Ownable, EIP712 {
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    bytes32 public constant COMPILE_TYPEHASH = keccak256(
        "Compile(address operator,uint256 recipeId,uint256 craftId,uint256[] outputIds,uint256[] outputAmounts,uint256 deadline)"
    );

    struct Recipe {
        uint256[] costTiers;
        uint256[] costAmounts;
        bool active;
    }

    IERC1155 public immutable dataShard;
    GearModule1155 public immutable gear;

    /// @notice Backend signer that rolls + signs recipe outputs
    address public craftSigner;

    mapping(uint256 => Recipe) private _recipes;
    /// @notice craftId => consumed (replay protection; one mint per signed roll)
    mapping(uint256 => bool) public craftClaimed;

    event RecipeSet(uint256 indexed recipeId, uint256[] costTiers, uint256[] costAmounts, bool active);
    event CraftSignerUpdated(address indexed signer);
    event Compiled(address indexed operator, uint256 indexed recipeId, uint256 indexed craftId, uint256[] outputIds, uint256[] outputAmounts);

    error UnknownRecipe(uint256 recipeId);
    error CraftAlreadyClaimed(uint256 craftId);
    error ProofExpired(uint256 deadline);
    error InvalidProof();
    error LengthMismatch();

    constructor(address dataShard_, address gear_, address craftSigner_)
        Ownable(msg.sender)
        EIP712("Hoodlums Blacknet Compiler", "1")
    {
        dataShard = IERC1155(dataShard_);
        gear = GearModule1155(gear_);
        craftSigner = craftSigner_;
    }

    /**
     * @notice Burn a recipe's Data Shard cost and mint the server-rolled
     *         Gear Module output, in one transaction.
     */
    function compile(
        uint256 recipeId,
        uint256 craftId,
        uint256[] calldata outputIds,
        uint256[] calldata outputAmounts,
        uint256 deadline,
        bytes calldata proof
    ) external {
        Recipe memory recipe = _recipes[recipeId];
        if (!recipe.active) revert UnknownRecipe(recipeId);
        if (outputIds.length == 0 || outputIds.length != outputAmounts.length) revert LengthMismatch();
        if (block.timestamp > deadline) revert ProofExpired(deadline);
        if (craftClaimed[craftId]) revert CraftAlreadyClaimed(craftId);

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    COMPILE_TYPEHASH,
                    msg.sender,
                    recipeId,
                    craftId,
                    keccak256(abi.encodePacked(outputIds)),
                    keccak256(abi.encodePacked(outputAmounts)),
                    deadline
                )
            )
        );
        if (ECDSA.recover(digest, proof) != craftSigner) revert InvalidProof();

        craftClaimed[craftId] = true;

        dataShard.safeBatchTransferFrom(msg.sender, BURN_ADDRESS, recipe.costTiers, recipe.costAmounts, "");
        gear.mintBatch(msg.sender, outputIds, outputAmounts);

        emit Compiled(msg.sender, recipeId, craftId, outputIds, outputAmounts);
    }

    // ---- views ----

    function getRecipe(uint256 recipeId) external view returns (uint256[] memory costTiers, uint256[] memory costAmounts, bool active) {
        Recipe memory r = _recipes[recipeId];
        return (r.costTiers, r.costAmounts, r.active);
    }

    // ---- admin ----

    function setRecipe(uint256 recipeId, uint256[] calldata costTiers, uint256[] calldata costAmounts, bool active) external onlyOwner {
        if (costTiers.length == 0 || costTiers.length != costAmounts.length) revert LengthMismatch();
        _recipes[recipeId] = Recipe(costTiers, costAmounts, active);
        emit RecipeSet(recipeId, costTiers, costAmounts, active);
    }

    function setCraftSigner(address signer_) external onlyOwner {
        craftSigner = signer_;
        emit CraftSignerUpdated(signer_);
    }
}
