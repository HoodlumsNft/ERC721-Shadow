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
        uint256 round1Price = vm.envOr("ROUND1_PRICE_PER_TOKEN_WEI", uint256(0.0017 ether));
        uint256 round2Price = vm.envOr("ROUND2_PRICE_PER_TOKEN_WEI", uint256(0.002 ether));
        uint256 perWalletCap = vm.envOr("PER_WALLET_CAP_TOKENS", uint256(2_000_000 ether));

        uint256 saleStart = vm.envOr("SALE_START", block.timestamp + 1 days);
        uint256 round1Hours = vm.envOr("ROUND1_HOURS", uint256(48));
        uint256 round1End = saleStart + (round1Hours * 1 hours);

        vm.startBroadcast();
        ShardsPresale presale = new ShardsPresale(hoodlums, owner, round1Price, round2Price, perWalletCap, saleStart, round1End);
        vm.stopBroadcast();

        console.log("ShardsPresale deployed:", address(presale));
        console.log("saleStart:", saleStart);
        console.log("round1End:", round1End);
        console.log("round1Price (wei/token):", round1Price);
        console.log("round2Price (wei/token):", round2Price);
        console.log("No total raise cap, no fixed end date -- end the sale with pause() when ready.");
    }
}
