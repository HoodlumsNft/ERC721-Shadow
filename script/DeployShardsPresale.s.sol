// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/ShardsPresale.sol";

/**
 * @title DeployShardsPresaleScript
 * @notice Deploys ShardsPresale on ApeChain. Constructor params are immutable once deployed;
 *         override any default via env var.
 *
 * Usage:
 *   HOODLUMS_NFT=0x982bd1F5A87E3F205410df06e15A582df8E1aF6c \
 *   PRESALE_OWNER=0x... \
 *   SALE_START=1234567890 \
 *   forge script script/DeployShardsPresale.s.sol:DeployShardsPresaleScript \
 *     --rpc-url apechain_mainnet --broadcast --verify
 */
contract DeployShardsPresaleScript is Script {
    function run() external {
        address hoodlums = vm.envAddress("HOODLUMS_NFT");
        address owner = vm.envAddress("PRESALE_OWNER");
        uint256 holderPrice = vm.envOr("HOLDER_PRICE_PER_TOKEN_WEI", uint256(0.0017 ether));
        uint256 publicPrice = vm.envOr("PUBLIC_PRICE_PER_TOKEN_WEI", uint256(0.002 ether));
        uint256 perWalletCap = vm.envOr("PER_WALLET_CAP_TOKENS", uint256(2_000_000 ether));
        uint256 saleStart = vm.envOr("SALE_START", block.timestamp + 1 days);

        vm.startBroadcast();
        ShardsPresale presale = new ShardsPresale(hoodlums, owner, holderPrice, publicPrice, perWalletCap, saleStart);
        vm.stopBroadcast();

        console.log("ShardsPresale deployed:", address(presale));
        console.log("saleStart:", saleStart);
        console.log("holderPrice (wei/token):", holderPrice);
        console.log("publicPrice (wei/token):", publicPrice);
    }
}
