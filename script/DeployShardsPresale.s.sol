// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/ShardsPresale.sol";

/**
 * @title DeployShardsPresaleScript
 * @notice Deploys ShardsPresale on ApeChain. Every parameter is set once here and is immutable on
 *         the deployed contract — double-check them before broadcasting, nothing here is
 *         adjustable after deploy.
 *
 * Defaults below match the current recommendation: 50,000,000 $SHARDS total (5% of supply),
 * 0.0044 APE/token flat price, 2,000,000 $SHARDS flat per-wallet cap (both rounds, no
 * holdings-based tiering), Round 1 (Hoodlums holders only) for 48h, Round 2 (public) for a
 * further 72h. Override any of them via env vars without touching this file.
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
        uint256 pricePerToken = vm.envOr("PRICE_PER_TOKEN_WEI", uint256(0.0044 ether));
        uint256 totalCap = vm.envOr("TOTAL_CAP_TOKENS", uint256(50_000_000 ether));
        uint256 perWalletCap = vm.envOr("PER_WALLET_CAP_TOKENS", uint256(2_000_000 ether));

        uint256 saleStart = vm.envOr("SALE_START", block.timestamp + 1 days);
        uint256 round1Hours = vm.envOr("ROUND1_HOURS", uint256(48));
        uint256 round2Hours = vm.envOr("ROUND2_HOURS", uint256(72));
        uint256 round1End = saleStart + (round1Hours * 1 hours);
        uint256 saleEnd = round1End + (round2Hours * 1 hours);

        vm.startBroadcast();
        ShardsPresale presale =
            new ShardsPresale(hoodlums, owner, pricePerToken, totalCap, perWalletCap, saleStart, round1End, saleEnd);
        vm.stopBroadcast();

        console.log("ShardsPresale deployed:", address(presale));
        console.log("saleStart:", saleStart);
        console.log("round1End:", round1End);
        console.log("saleEnd:", saleEnd);
    }
}
