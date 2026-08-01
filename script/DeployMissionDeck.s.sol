// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/decks/MissionDeck1155.sol";

/**
 * @title DeployMissionDeckScript
 * @notice Deploys MissionDeck1155 on ApeChain. Default tier prices
 *         (Runner 10 / Ghost 25 / Wraith 55 / Apex 100 APE) and pack price
 *         (15 APE) are set in the constructor — adjust post-deploy via
 *         setPrice/setPackPrice if needed, no redeploy required.
 *
 * Usage:
 *   PACK_SIGNER=0x... DECK_BASE_URI=https://.../decks/ \
 *   forge script script/DeployMissionDeck.s.sol:DeployMissionDeckScript \
 *     --rpc-url apechain_mainnet --broadcast --verify
 */
contract DeployMissionDeckScript is Script {
    function run() external {
        address packSigner = vm.envAddress("PACK_SIGNER");
        string memory deckBaseURI = vm.envString("DECK_BASE_URI");

        vm.startBroadcast();
        MissionDeck1155 deck = new MissionDeck1155(packSigner, deckBaseURI);
        vm.stopBroadcast();

        console.log("MissionDeck1155 deployed:", address(deck));
    }
}
