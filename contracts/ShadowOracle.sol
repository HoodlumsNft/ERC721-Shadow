// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC721Shadow.sol";

/**
 * @title ShadowOracle
 * @notice Reference implementation of an oracle for mirroring NFT ownership
 * @dev This contract demonstrates patterns for batching and relaying ownership updates.
 * Production implementations should use multi-signature control or decentralized oracle networks.
 */
contract ShadowOracle {
    address public owner;
    address public immutable shadowContract;
    uint256 public lastProcessedBlock;
    
    mapping(address => bool) public relayers;
    
    event RelayerAdded(address indexed relayer);
    event RelayerRemoved(address indexed relayer);
    event OwnershipRelayed(uint256 indexed blockNumber, uint256 count);
    
    error NotAuthorized();
    error ZeroAddress();
    error InvalidBlockNumber();
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }
    
    modifier onlyRelayer() {
        if (!relayers[msg.sender] && msg.sender != owner) revert NotAuthorized();
        _;
    }
    
    /**
     * @notice Initializes the oracle
     * @param shadowContract_ The shadow contract address to update
     */
    constructor(address shadowContract_) {
        if (shadowContract_ == address(0)) revert ZeroAddress();
        
        owner = msg.sender;
        shadowContract = shadowContract_;
        relayers[msg.sender] = true;
    }
    
    /**
     * @notice Adds a relayer address
     * @param relayer The address to authorize as a relayer
     */
    function addRelayer(address relayer) external onlyOwner {
        if (relayer == address(0)) revert ZeroAddress();
        relayers[relayer] = true;
        emit RelayerAdded(relayer);
    }
    
    /**
     * @notice Removes a relayer address
     * @param relayer The address to remove from relayers
     */
    function removeRelayer(address relayer) external onlyOwner {
        relayers[relayer] = false;
        emit RelayerRemoved(relayer);
    }
    
    /**
     * @notice Relays ownership updates using standard bulk method
     * @param tokenIds Array of token IDs to update
     * @param newOwners Array of new owner addresses
     * @param primaryBlockNumber Block number on primary chain
     */
    function relayOwnershipBulk(
        uint256[] calldata tokenIds,
        address[] calldata newOwners,
        uint256 primaryBlockNumber
    ) external onlyRelayer {
        if (primaryBlockNumber <= lastProcessedBlock) revert InvalidBlockNumber();
        
        IERC721Shadow(shadowContract).mirrorOwnershipBulk(
            tokenIds,
            newOwners,
            primaryBlockNumber
        );
        
        lastProcessedBlock = primaryBlockNumber;
        emit OwnershipRelayed(primaryBlockNumber, tokenIds.length);
    }
    
    /**
     * @notice Relays ownership updates using packed data method
     * @param packedData Array of packed token ID and owner pairs
     * @param primaryBlockNumber Block number on primary chain
     */
    function relayOwnershipPacked(
        uint256[] calldata packedData,
        uint256 primaryBlockNumber
    ) external onlyRelayer {
        if (primaryBlockNumber <= lastProcessedBlock) revert InvalidBlockNumber();
        
        IERC721Shadow(shadowContract).mirrorOwnershipPacked(
            packedData,
            primaryBlockNumber
        );
        
        lastProcessedBlock = primaryBlockNumber;
        emit OwnershipRelayed(primaryBlockNumber, packedData.length);
    }
    
    /**
     * @notice Transfers ownership of the oracle
     * @param newOwner The new owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
    
    /**
     * @notice Packs a token ID and owner address into a single uint256
     * @param tokenId The token ID
     * @param owner The owner address
     * @return packed The packed data
     */
    function packOwnership(uint256 tokenId, address owner) 
        external 
        pure 
        returns (uint256 packed) 
    {
        packed = (tokenId << 160) | uint160(owner);
    }
    
    /**
     * @notice Unpacks a uint256 into token ID and owner address
     * @param packed The packed data
     * @return tokenId The token ID
     * @return owner The owner address
     */
    function unpackOwnership(uint256 packed) 
        external 
        pure 
        returns (uint256 tokenId, address owner) 
    {
        tokenId = packed >> 160;
        owner = address(uint160(packed));
    }
}
