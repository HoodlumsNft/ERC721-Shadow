// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC721Shadow.sol";

/**
 * @title ERC721Shadow
 * @notice Standard implementation of cross-chain NFT ownership mirroring
 * @dev This contract maintains a read-only copy of NFT ownership state from a primary chain.
 * Only the authorized oracle can update ownership. No transfers or approvals are supported.
 */
contract ERC721Shadow is IERC721Shadow {
    string private _name;
    string private _symbol;
    string private _baseTokenURI;
    address private _oracle;
    address private _owner;
    uint256 private _totalSupply;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;

    modifier onlyOracle() {
        if (msg.sender != _oracle) revert NotOracle();
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    /**
     * @notice Initializes the shadow contract
     * @param name_ The name of the NFT collection
     * @param symbol_ The symbol of the NFT collection
     * @param baseTokenURI_ The base URI for token metadata
     * @param oracle_ The authorized oracle address
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_,
        address oracle_
    ) {
        if (oracle_ == address(0)) revert ZeroAddress();
        
        _name = name_;
        _symbol = symbol_;
        _baseTokenURI = baseTokenURI_;
        _oracle = oracle_;
        _owner = msg.sender;
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function oracle() external view returns (address) {
        return _oracle;
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function exists(uint256 tokenId) public view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenNotMinted(tokenId);
        return owner;
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _balances[owner];
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (!exists(tokenId)) revert TokenNotMinted(tokenId);
        
        bytes memory baseURI = bytes(_baseTokenURI);
        if (baseURI.length == 0) {
            return "";
        }
        
        return string(abi.encodePacked(_baseTokenURI, _toString(tokenId)));
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function mirrorOwnership(uint256 tokenId, address newOwner) external onlyOracle {
        if (newOwner == address(0)) revert ZeroAddress();
        
        address previousOwner = _owners[tokenId];
        
        if (previousOwner != address(0)) {
            _balances[previousOwner]--;
        } else {
            _totalSupply++;
        }
        
        _owners[tokenId] = newOwner;
        _balances[newOwner]++;
        
        emit OwnershipMirrored(tokenId, previousOwner, newOwner);
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function mirrorOwnershipBulk(
        uint256[] calldata tokenIds,
        address[] calldata newOwners,
        uint256 primaryBlockNumber
    ) external onlyOracle {
        uint256 length = tokenIds.length;
        if (length != newOwners.length) revert ArrayLengthMismatch();
        
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = tokenIds[i];
            address newOwner = newOwners[i];
            
            if (newOwner == address(0)) revert ZeroAddress();
            
            address previousOwner = _owners[tokenId];
            
            if (previousOwner != address(0)) {
                _balances[previousOwner]--;
            } else {
                _totalSupply++;
            }
            
            _owners[tokenId] = newOwner;
            _balances[newOwner]++;
            
            emit OwnershipMirrored(tokenId, previousOwner, newOwner);
        }
        
        emit BulkOwnershipMirrored(length, primaryBlockNumber);
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function mirrorOwnershipPacked(
        uint256[] calldata packedData,
        uint256 primaryBlockNumber
    ) external onlyOracle {
        uint256 length = packedData.length;
        
        for (uint256 i = 0; i < length; i++) {
            uint256 packed = packedData[i];
            
            uint256 tokenId = packed >> 160;
            address newOwner = address(uint160(packed));
            
            if (newOwner == address(0)) revert ZeroAddress();
            
            address previousOwner = _owners[tokenId];
            
            if (previousOwner != address(0)) {
                _balances[previousOwner]--;
            } else {
                _totalSupply++;
            }
            
            _owners[tokenId] = newOwner;
            _balances[newOwner]++;
            
            emit OwnershipMirrored(tokenId, previousOwner, newOwner);
        }
        
        emit BulkOwnershipMirrored(length, primaryBlockNumber);
    }

    /**
     * @inheritdoc IERC721Shadow
     */
    function setOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert ZeroAddress();
        
        address previousOracle = _oracle;
        _oracle = newOracle;
        
        emit OracleUpdated(previousOracle, newOracle);
    }

    /**
     * @notice Converts a uint256 to its ASCII string representation
     * @param value The number to convert
     * @return The string representation
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        
        uint256 temp = value;
        uint256 digits;
        
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
}
