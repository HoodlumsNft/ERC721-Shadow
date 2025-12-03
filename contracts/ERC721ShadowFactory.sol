// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC721Shadow.sol";
import "./ERC721ShadowOptimized.sol";

/**
 * @title ERC721ShadowFactory
 * @notice Factory for deploying ERC721Shadow contracts with CREATE2
 * @dev Enables deterministic address generation across multiple chains
 */
contract ERC721ShadowFactory {
    /**
     * @notice Emitted when a new shadow contract is deployed
     * @param shadowContract The address of the deployed contract
     * @param name The collection name
     * @param symbol The collection symbol
     * @param oracle The oracle address
     * @param deployer The address that deployed the contract
     * @param salt The salt used for CREATE2
     * @param isOptimized Whether the optimized version was deployed
     */
    event ShadowDeployed(
        address indexed shadowContract,
        string name,
        string symbol,
        address indexed oracle,
        address indexed deployer,
        bytes32 salt,
        bool isOptimized
    );

    /**
     * @notice Deploys a standard ERC721Shadow contract
     * @param name The collection name
     * @param symbol The collection symbol
     * @param baseTokenURI The base URI for token metadata
     * @param oracle The authorized oracle address
     * @param salt The salt for CREATE2 deployment
     * @return shadowContract The address of the deployed contract
     */
    function deployShadow(
        string memory name,
        string memory symbol,
        string memory baseTokenURI,
        address oracle,
        bytes32 salt
    ) external returns (address shadowContract) {
        shadowContract = address(
            new ERC721Shadow{salt: salt}(name, symbol, baseTokenURI, oracle)
        );
        
        emit ShadowDeployed(
            shadowContract,
            name,
            symbol,
            oracle,
            msg.sender,
            salt,
            false
        );
    }

    /**
     * @notice Deploys an optimized ERC721ShadowOptimized contract
     * @param name The collection name
     * @param symbol The collection symbol
     * @param baseTokenURI The base URI for token metadata
     * @param oracle The authorized oracle address
     * @param salt The salt for CREATE2 deployment
     * @return shadowContract The address of the deployed contract
     */
    function deployShadowOptimized(
        string memory name,
        string memory symbol,
        string memory baseTokenURI,
        address oracle,
        bytes32 salt
    ) external returns (address shadowContract) {
        shadowContract = address(
            new ERC721ShadowOptimized{salt: salt}(name, symbol, baseTokenURI, oracle)
        );
        
        emit ShadowDeployed(
            shadowContract,
            name,
            symbol,
            oracle,
            msg.sender,
            salt,
            true
        );
    }

    /**
     * @notice Predicts the address of a standard shadow contract
     * @param name The collection name
     * @param symbol The collection symbol
     * @param baseTokenURI The base URI for token metadata
     * @param oracle The authorized oracle address
     * @param salt The salt for CREATE2 deployment
     * @param deployer The address that will deploy the contract
     * @return predicted The predicted contract address
     */
    function predictShadowAddress(
        string memory name,
        string memory symbol,
        string memory baseTokenURI,
        address oracle,
        bytes32 salt,
        address deployer
    ) external view returns (address predicted) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC721Shadow).creationCode,
            abi.encode(name, symbol, baseTokenURI, oracle)
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );
        
        predicted = address(uint160(uint256(hash)));
    }

    /**
     * @notice Predicts the address of an optimized shadow contract
     * @param name The collection name
     * @param symbol The collection symbol
     * @param baseTokenURI The base URI for token metadata
     * @param oracle The authorized oracle address
     * @param salt The salt for CREATE2 deployment
     * @param deployer The address that will deploy the contract
     * @return predicted The predicted contract address
     */
    function predictShadowOptimizedAddress(
        string memory name,
        string memory symbol,
        string memory baseTokenURI,
        address oracle,
        bytes32 salt,
        address deployer
    ) external view returns (address predicted) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC721ShadowOptimized).creationCode,
            abi.encode(name, symbol, baseTokenURI, oracle)
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );
        
        predicted = address(uint160(uint256(hash)));
    }
}
