// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/ERC721Shadow.sol";
import "../contracts/ERC721ShadowOptimized.sol";
import "../contracts/ERC721ShadowFactory.sol";
import "../contracts/ShadowOracle.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address oracle = vm.envAddress("ORACLE_ADDRESS");
        
        string memory name = vm.envString("COLLECTION_NAME");
        string memory symbol = vm.envString("COLLECTION_SYMBOL");
        string memory baseURI = vm.envString("BASE_URI");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ERC721ShadowFactory factory = new ERC721ShadowFactory();
        console.log("Factory deployed at:", address(factory));
        
        bytes32 salt = keccak256(abi.encodePacked(name, symbol));
        
        address shadowContract = factory.deployShadow(
            name,
            symbol,
            baseURI,
            oracle,
            salt
        );
        console.log("Shadow contract deployed at:", shadowContract);
        
        vm.stopBroadcast();
    }
    
    function deployOptimized() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address oracle = vm.envAddress("ORACLE_ADDRESS");
        
        string memory name = vm.envString("COLLECTION_NAME");
        string memory symbol = vm.envString("COLLECTION_SYMBOL");
        string memory baseURI = vm.envString("BASE_URI");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ERC721ShadowFactory factory = new ERC721ShadowFactory();
        console.log("Factory deployed at:", address(factory));
        
        bytes32 salt = keccak256(abi.encodePacked(name, symbol));
        
        address shadowContract = factory.deployShadowOptimized(
            name,
            symbol,
            baseURI,
            oracle,
            salt
        );
        console.log("Shadow contract (optimized) deployed at:", shadowContract);
        
        vm.stopBroadcast();
    }
    
    function deployWithOracle() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        string memory name = vm.envString("COLLECTION_NAME");
        string memory symbol = vm.envString("COLLECTION_SYMBOL");
        string memory baseURI = vm.envString("BASE_URI");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ERC721ShadowFactory factory = new ERC721ShadowFactory();
        console.log("Factory deployed at:", address(factory));
        
        bytes32 salt = keccak256(abi.encodePacked(name, symbol));
        
        address shadowContract = factory.deployShadow(
            name,
            symbol,
            baseURI,
            address(0x1), // Temporary oracle address
            salt
        );
        console.log("Shadow contract deployed at:", shadowContract);
        
        ShadowOracle oracle = new ShadowOracle(shadowContract);
        console.log("Oracle deployed at:", address(oracle));
        
        ERC721Shadow(shadowContract).setOracle(address(oracle));
        console.log("Oracle set on shadow contract");
        
        vm.stopBroadcast();
    }
}
