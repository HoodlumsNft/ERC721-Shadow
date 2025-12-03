// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC721Shadow
 * @notice Interface for cross-chain NFT ownership mirroring
 * @dev This interface defines a minimal, gas-efficient standard for maintaining
 * read-only NFT ownership state synchronized from a primary chain by an authorized oracle.
 * The shadow contract does not support transfers or approvals on the secondary chain.
 */
interface IERC721Shadow {
    /**
     * @notice Emitted when ownership of a token is mirrored from the primary chain
     * @param tokenId The ID of the token whose ownership was updated
     * @param previousOwner The previous owner address (zero address if newly minted)
     * @param newOwner The new owner address
     */
    event OwnershipMirrored(
        uint256 indexed tokenId,
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @notice Emitted when multiple token ownerships are mirrored in a batch
     * @param count The number of tokens updated in this batch
     * @param blockNumber The block number on the primary chain at which this state was captured
     */
    event BulkOwnershipMirrored(uint256 count, uint256 blockNumber);

    /**
     * @notice Emitted when the authorized oracle address is updated
     * @param previousOracle The previous oracle address
     * @param newOracle The new oracle address
     */
    event OracleUpdated(address indexed previousOracle, address indexed newOracle);

    /**
     * @notice Thrown when a non-oracle address attempts to call an oracle-only function
     */
    error NotOracle();

    /**
     * @notice Thrown when zero address is provided where not allowed
     */
    error ZeroAddress();

    /**
     * @notice Thrown when array parameters have mismatched lengths
     */
    error ArrayLengthMismatch();

    /**
     * @notice Thrown when querying a token that has not been mirrored
     * @param tokenId The ID of the non-existent token
     */
    error TokenNotMinted(uint256 tokenId);

    /**
     * @notice Returns the owner of a specific token
     * @dev Reverts with TokenNotMinted if the token has not been mirrored
     * @param tokenId The ID of the token to query
     * @return owner The address of the token owner
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @notice Returns the number of tokens owned by an address
     * @param owner The address to query
     * @return balance The number of tokens owned
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @notice Returns the collection name
     * @return The name of the NFT collection
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the collection symbol
     * @return The symbol of the NFT collection
     */
    function symbol() external view returns (string memory);

    /**
     * @notice Returns the metadata URI for a token
     * @dev Reverts with TokenNotMinted if the token has not been mirrored
     * @param tokenId The ID of the token to query
     * @return The metadata URI string
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /**
     * @notice Returns the total number of tokens that have been mirrored
     * @return The total supply of mirrored tokens
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Checks if a token has been mirrored
     * @param tokenId The ID of the token to check
     * @return True if the token exists, false otherwise
     */
    function exists(uint256 tokenId) external view returns (bool);

    /**
     * @notice Returns the current authorized oracle address
     * @return The oracle address
     */
    function oracle() external view returns (address);

    /**
     * @notice Returns the base URI for token metadata
     * @return The base URI string
     */
    function baseURI() external view returns (string memory);

    /**
     * @notice Mirrors ownership of a single token from the primary chain
     * @dev Can only be called by the authorized oracle
     * @param tokenId The ID of the token to update
     * @param newOwner The new owner address
     */
    function mirrorOwnership(uint256 tokenId, address newOwner) external;

    /**
     * @notice Mirrors ownership of multiple tokens in a batch
     * @dev Can only be called by the authorized oracle
     * @dev Arrays must have matching lengths
     * @param tokenIds Array of token IDs to update
     * @param newOwners Array of corresponding new owner addresses
     * @param primaryBlockNumber The block number on the primary chain for this update
     */
    function mirrorOwnershipBulk(
        uint256[] calldata tokenIds,
        address[] calldata newOwners,
        uint256 primaryBlockNumber
    ) external;

    /**
     * @notice Mirrors ownership using packed data encoding for maximum gas efficiency
     * @dev Can only be called by the authorized oracle
     * @dev Each uint256 in packedData encodes: (tokenId << 160) | uint160(owner)
     * @dev Supports token IDs up to 2^96 - 1
     * @param packedData Array of packed token ID and owner address pairs
     * @param primaryBlockNumber The block number on the primary chain for this update
     */
    function mirrorOwnershipPacked(
        uint256[] calldata packedData,
        uint256 primaryBlockNumber
    ) external;

    /**
     * @notice Updates the authorized oracle address
     * @dev Can only be called by the contract owner/admin
     * @param newOracle The new oracle address
     */
    function setOracle(address newOracle) external;
}
