// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC721Shadow.sol";

/**
 * @title ERC721ShadowOptimized
 * @notice Gas-optimized implementation using inline assembly
 * @dev This contract achieves maximum gas efficiency through assembly-level optimizations.
 * Use this implementation when gas costs are critical. Thoroughly audit before production use.
 */
contract ERC721ShadowOptimized is IERC721Shadow {
    /// @notice Standard ERC721 Transfer event for marketplace compatibility
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    string private _name;
    string private _symbol;
    string private _baseTokenURI;
    address private _oracle;
    address private _owner;
    uint256 private _totalSupply;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;

    modifier onlyOracle() {
        assembly {
            if iszero(eq(caller(), sload(_oracle.slot))) {
                mstore(0x00, 0x0c3e2e6b) // NotOracle() selector
                revert(0x1c, 0x04)
            }
        }
        _;
    }

    modifier onlyOwner() {
        assembly {
            if iszero(eq(caller(), sload(_owner.slot))) {
                mstore(0x00, 0x4e6f74206f776e6572) // "Not owner"
                revert(0x00, 0x20)
            }
        }
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_,
        address oracle_
    ) {
        assembly {
            if iszero(oracle_) {
                mstore(0x00, 0xd92e233d) // ZeroAddress() selector
                revert(0x1c, 0x04)
            }
        }
        
        _name = name_;
        _symbol = symbol_;
        _baseTokenURI = baseTokenURI_;
        _oracle = oracle_;
        _owner = msg.sender;
    }

    /**
     * @notice Returns true if this contract implements the interface defined by `interfaceId`
     * @dev Implements ERC165 for marketplace detection
     * @param interfaceId The interface identifier to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f;   // ERC721Metadata
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice Returns the contract-level metadata URI
     * @dev Used by OpenSea and other marketplaces for collection info
     */
    function contractURI() external view returns (string memory) {
        return string(abi.encodePacked(_baseTokenURI, "contract"));
    }

    function oracle() external view returns (address) {
        return _oracle;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function exists(uint256 tokenId) public view returns (bool) {
        address owner;
        assembly {
            mstore(0x00, tokenId)
            mstore(0x20, _owners.slot)
            owner := sload(keccak256(0x00, 0x40))
        }
        return owner != address(0);
    }

    function ownerOf(uint256 tokenId) external view returns (address owner) {
        assembly {
            mstore(0x00, tokenId)
            mstore(0x20, _owners.slot)
            owner := sload(keccak256(0x00, 0x40))
            
            if iszero(owner) {
                mstore(0x00, 0xceea21b6) // TokenNotMinted(uint256) selector
                mstore(0x20, tokenId)
                revert(0x1c, 0x24)
            }
        }
    }

    function balanceOf(address owner) external view returns (uint256 bal) {
        assembly {
            if iszero(owner) {
                mstore(0x00, 0xd92e233d) // ZeroAddress() selector
                revert(0x1c, 0x04)
            }
            
            mstore(0x00, owner)
            mstore(0x20, _balances.slot)
            bal := sload(keccak256(0x00, 0x40))
        }
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (!exists(tokenId)) revert TokenNotMinted(tokenId);
        
        bytes memory baseURI = bytes(_baseTokenURI);
        if (baseURI.length == 0) {
            return "";
        }
        
        return string(abi.encodePacked(_baseTokenURI, _toString(tokenId)));
    }

    function mirrorOwnership(uint256 tokenId, address newOwner) external onlyOracle {
        assembly {
            if iszero(newOwner) {
                mstore(0x00, 0xd92e233d) // ZeroAddress() selector
                revert(0x1c, 0x04)
            }
            
            mstore(0x00, tokenId)
            mstore(0x20, _owners.slot)
            let ownerSlot := keccak256(0x00, 0x40)
            let previousOwner := sload(ownerSlot)
            
            if iszero(previousOwner) {
                let supply := sload(_totalSupply.slot)
                sstore(_totalSupply.slot, add(supply, 1))
            }
            
            if previousOwner {
                mstore(0x00, previousOwner)
                mstore(0x20, _balances.slot)
                let prevBalanceSlot := keccak256(0x00, 0x40)
                let prevBalance := sload(prevBalanceSlot)
                sstore(prevBalanceSlot, sub(prevBalance, 1))
            }
            
            sstore(ownerSlot, newOwner)
            
            mstore(0x00, newOwner)
            mstore(0x20, _balances.slot)
            let newBalanceSlot := keccak256(0x00, 0x40)
            let newBalance := sload(newBalanceSlot)
            sstore(newBalanceSlot, add(newBalance, 1))
            
            mstore(0x00, tokenId)
            mstore(0x20, previousOwner)
            mstore(0x40, newOwner)
            log4(0x00, 0x60, 
                0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925, // OwnershipMirrored event signature (placeholder)
                tokenId, previousOwner, newOwner)
        }
    }

    function mirrorOwnershipBulk(
        uint256[] calldata tokenIds,
        address[] calldata newOwners,
        uint256 primaryBlockNumber
    ) external onlyOracle {
        uint256 length = tokenIds.length;
        
        assembly {
            if iszero(eq(length, newOwners.length)) {
                mstore(0x00, 0x3b800a46) // ArrayLengthMismatch() selector
                revert(0x1c, 0x04)
            }
        }
        
        for (uint256 i = 0; i < length; ) {
            uint256 tokenId = tokenIds[i];
            address newOwner = newOwners[i];
            
            if (newOwner == address(0)) revert ZeroAddress();
            
            address previousOwner = _owners[tokenId];
            
            if (previousOwner == address(0)) {
                _totalSupply++;
            } else {
                _balances[previousOwner]--;
            }
            
            _owners[tokenId] = newOwner;
            _balances[newOwner]++;
            
            emit Transfer(previousOwner, newOwner, tokenId);
            emit OwnershipMirrored(tokenId, previousOwner, newOwner);
            
            unchecked {
                i++;
            }
        }
        
        emit BulkOwnershipMirrored(length, primaryBlockNumber);
    }

    function mirrorOwnershipPacked(
        uint256[] calldata packedData,
        uint256 primaryBlockNumber
    ) external onlyOracle {
        uint256 length = packedData.length;
        
        for (uint256 i = 0; i < length; ) {
            uint256 packed = packedData[i];
            
            uint256 tokenId = packed >> 160;
            address newOwner = address(uint160(packed));
            
            if (newOwner == address(0)) revert ZeroAddress();
            
            address previousOwner = _owners[tokenId];
            
            if (previousOwner == address(0)) {
                _totalSupply++;
            } else {
                _balances[previousOwner]--;
            }
            
            _owners[tokenId] = newOwner;
            _balances[newOwner]++;
            
            emit Transfer(previousOwner, newOwner, tokenId);
            emit OwnershipMirrored(tokenId, previousOwner, newOwner);
            
            unchecked {
                i++;
            }
        }
        
        emit BulkOwnershipMirrored(length, primaryBlockNumber);
    }

    function setOracle(address newOracle) external onlyOwner {
        assembly {
            if iszero(newOracle) {
                mstore(0x00, 0xd92e233d) // ZeroAddress() selector
                revert(0x1c, 0x04)
            }
        }
        
        address previousOracle = _oracle;
        _oracle = newOracle;
        
        emit OracleUpdated(previousOracle, newOracle);
    }

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
