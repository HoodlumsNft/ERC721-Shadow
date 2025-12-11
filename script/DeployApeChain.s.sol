// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/ERC721Shadow.sol";
import "../contracts/ERC721ShadowOptimized.sol";
import "../contracts/ERC721ShadowFactory.sol";
import "../contracts/ShadowOracle.sol";

/**
 * @title DeployApeChainScript
 * @notice Deployment script for ERC721Shadow on ApeChain
 * @dev This deploys a shadow contract that mirrors ownership from the primary Monad contract
 * 
 * Primary Contract (Monad): 0x4810C89F79fC1968e53b37958b3b59E216CF91Fa
 * 
 * Usage:
 *   Deploy standard version:
 *     forge script script/DeployApeChain.s.sol:DeployApeChainScript --rpc-url apechain --broadcast --verify
 *   
 *   Deploy optimized version:
 *     forge script script/DeployApeChain.s.sol:DeployApeChainScript --sig "deployOptimized()" --rpc-url apechain --broadcast --verify
 *   
 *   Deploy with oracle:
 *     forge script script/DeployApeChain.s.sol:DeployApeChainScript --sig "deployWithOracle()" --rpc-url apechain --broadcast --verify
 */
contract DeployApeChainScript is Script {
    // Primary contract on Monad that we're mirroring
    address constant PRIMARY_CONTRACT = 0x4810C89F79fC1968e53b37958b3b59E216CF91Fa;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address oracle = vm.envAddress("ORACLE_ADDRESS");
        
        string memory name = vm.envString("COLLECTION_NAME");
        string memory symbol = vm.envString("COLLECTION_SYMBOL");
        string memory baseURI = vm.envString("BASE_URI");
        
        console.log("========================================");
        console.log("Deploying ERC721Shadow to ApeChain");
        console.log("Primary Contract (Monad):", PRIMARY_CONTRACT);
        console.log("========================================");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy factory
        ERC721ShadowFactory factory = new ERC721ShadowFactory();
        console.log("Factory deployed at:", address(factory));
        
        // Use the same salt as the primary contract for consistency
        bytes32 salt = keccak256(abi.encodePacked(name, symbol, "apechain"));
        
        // Deploy shadow contract
        address shadowContract = factory.deployShadow(
            name,
            symbol,
            baseURI,
            oracle,
            salt
        );
        console.log("Shadow contract deployed at:", shadowContract);
        console.log("Oracle address:", oracle);
        
        vm.stopBroadcast();
        
        console.log("========================================");
        console.log("Deployment complete!");
        console.log("Shadow contract is ready to mirror from Monad");
        console.log("========================================");
    }
    
    function deployOptimized() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address oracle = vm.envAddress("ORACLE_ADDRESS");
        
        string memory name = vm.envString("COLLECTION_NAME");
        string memory symbol = vm.envString("COLLECTION_SYMBOL");
        string memory baseURI = vm.envString("BASE_URI");
        
        console.log("========================================");
        console.log("Deploying ERC721ShadowOptimized to ApeChain");
        console.log("Primary Contract (Monad):", PRIMARY_CONTRACT);
        console.log("========================================");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ERC721ShadowFactory factory = new ERC721ShadowFactory();
        console.log("Factory deployed at:", address(factory));
        
        bytes32 salt = keccak256(abi.encodePacked(name, symbol, "apechain-optimized"));
        
        address shadowContract = factory.deployShadowOptimized(
            name,
            symbol,
            baseURI,
            oracle,
            salt
        );
        console.log("Shadow contract (optimized) deployed at:", shadowContract);
        console.log("Oracle address:", oracle);
        
        vm.stopBroadcast();
        
        console.log("========================================");
        console.log("Deployment complete!");
        console.log("Optimized shadow contract is ready to mirror from Monad");
        console.log("========================================");
    }
    
    function deployWithOracle() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        string memory name = vm.envString("COLLECTION_NAME");
        string memory symbol = vm.envString("COLLECTION_SYMBOL");
        string memory baseURI = vm.envString("BASE_URI");
        
        console.log("========================================");
        console.log("Deploying ERC721Shadow + ShadowOracle to ApeChain");
        console.log("Primary Contract (Monad):", PRIMARY_CONTRACT);
        console.log("========================================");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy shadow contract directly (not through factory) with temporary oracle
        // This ensures the deployer becomes the owner and can update the oracle
        ERC721Shadow shadowContract = new ERC721Shadow(
            name,
            symbol,
            baseURI,
            address(0x1)  // Temporary oracle address - will be updated below
        );
        console.log("Shadow contract deployed at:", address(shadowContract));
        
        // Deploy oracle contract with the shadow contract address
        ShadowOracle oracle = new ShadowOracle(address(shadowContract));
        console.log("Oracle deployed at:", address(oracle));
        
        // Update shadow contract with actual oracle address
        // This works because deployer is now the owner
        shadowContract.setOracle(address(oracle));
        console.log("Oracle set on shadow contract");
        
        vm.stopBroadcast();
        
        console.log("========================================");
        console.log("Deployment complete!");
        console.log("Shadow contract:", address(shadowContract));
        console.log("Oracle contract:", address(oracle));
        console.log("Ready to mirror from Monad");
        console.log("========================================");
    }
    
    /**
     * @notice Deploy only the oracle for an existing shadow contract
     * @dev Use this if you already have a shadow contract deployed
     */
    function deployOracleOnly() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address existingShadowContract = vm.envAddress("SHADOW_CONTRACT_ADDRESS");
        
        console.log("========================================");
        console.log("Deploying ShadowOracle for existing shadow contract");
        console.log("Shadow Contract:", existingShadowContract);
        console.log("========================================");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ShadowOracle oracle = new ShadowOracle(existingShadowContract);
        console.log("Oracle deployed at:", address(oracle));
        
        // Update shadow contract with oracle address
        ERC721Shadow(existingShadowContract).setOracle(address(oracle));
        console.log("Oracle set on shadow contract");
        
        vm.stopBroadcast();
        
        console.log("========================================");
        console.log("Oracle deployment complete!");
        console.log("========================================");
    }
}
