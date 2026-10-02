// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/ShardsPresale.sol";

/**
 * @title DeployShardsPresaleScript
 * @notice Deploys ShardsPresale on ApeChain. Every parameter is set once here and is immutable on
 *         the deployed contract — double-check them before broadcasting, nothing here is
 *         adjustable after deploy except pausing the sale (see pause()/withdraw() on the contract).
 *
 * Defaults below match the current plan: Round 1 (Hoodlums holders only) at 0.0017 APE/token for
 * the first 48h, then Round 2 (public) at 0.002 APE/token forever after — no total raise cap (target
 * is 100,000+ APE, not a hard ceiling) and no fixed end date; the team ends the sale manually by
 * calling pause() once satisfied, which is also what unlocks withdraw() for the real airdrop.
 * perWalletCap (2,000,000 $SHARDS, same both rounds) is the only remaining limit. Override any of
 * these via env vars without touching this file.
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
