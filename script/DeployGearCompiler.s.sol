// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/gear/GearModule1155.sol";
import "../contracts/gear/BlackMarketCompiler.sol";

/**
 * @title DeployGearCompilerScript
 * @notice Deploys GearModule1155 + BlackMarketCompiler on ApeChain and wires
 *         up the 8 recipes from blacknet/docs/game.md §7.3.
 *
 * Usage:
 *   DATASHARD_ADDRESS=0x605d412716Ce99A1f9792d5e0Ae874c9E115778e \
 *   CRAFT_SIGNER=0x... GEAR_BASE_URI=https://.../gear/ \
 *   forge script script/DeployGearCompiler.s.sol:DeployGearCompilerScript \
 *     --rpc-url apechain_mainnet --broadcast --verify
 */
contract DeployGearCompilerScript is Script {
    function run() external {
        address dataShard = vm.envAddress("DATASHARD_ADDRESS");
        address craftSigner = vm.envAddress("CRAFT_SIGNER");
        string memory gearBaseURI = vm.envString("GEAR_BASE_URI");

        vm.startBroadcast();

        GearModule1155 gear = new GearModule1155(address(0), gearBaseURI);
        BlackMarketCompiler compiler = new BlackMarketCompiler(dataShard, address(gear), craftSigner);
        gear.setMinter(address(compiler));

        _setRecipes(compiler);

        vm.stopBroadcast();

        console.log("GearModule1155 deployed:", address(gear));
        console.log("BlackMarketCompiler deployed:", address(compiler));
    }

    function _setRecipes(BlackMarketCompiler compiler) internal {
        // 1. Scrap Assembly: 5x Glitch Bit (tier 1)
        _recipe(compiler, 1, _tiers1(1), _amounts1(5));
        // 2. Circuit Salvage: 3x Glitch Bit + 2x Data Chip
        _recipe(compiler, 2, _tiers2(1, 2), _amounts2(3, 2));
        // 3. Packet Fusion: 4x Encrypted Packet (tier 3)
        _recipe(compiler, 3, _tiers1(3), _amounts1(4));
        // 4. Neon Overclock: 3x Neon Shard + 2x Data Chip
        _recipe(compiler, 4, _tiers2(4, 2), _amounts2(3, 2));
        // 5. Firewall Breach: 3x Firewall Core + 1x Ghost Key
        _recipe(compiler, 5, _tiers2(5, 6), _amounts2(3, 1));
        // 6. Black ICE Protocol: 3x Black ICE + 3x Zero-Day
        _recipe(compiler, 6, _tiers2(7, 8), _amounts2(3, 3));
        // 7. Root Directive: 2x Root Access + 3x Black ICE
        _recipe(compiler, 7, _tiers2(9, 7), _amounts2(2, 3));
        // 8. Genesis Protocol: 1x Genesis Key + 2x Root Access
        _recipe(compiler, 8, _tiers2(10, 9), _amounts2(1, 2));
    }

    function _recipe(BlackMarketCompiler compiler, uint256 id, uint256[] memory tiers, uint256[] memory amounts) internal {
        compiler.setRecipe(id, tiers, amounts, true);
    }

    function _tiers1(uint256 a) internal pure returns (uint256[] memory t) {
        t = new uint256[](1);
        t[0] = a;
    }

    function _amounts1(uint256 a) internal pure returns (uint256[] memory t) {
        t = new uint256[](1);
        t[0] = a;
    }

    function _tiers2(uint256 a, uint256 b) internal pure returns (uint256[] memory t) {
        t = new uint256[](2);
        t[0] = a;
        t[1] = b;
    }

    function _amounts2(uint256 a, uint256 b) internal pure returns (uint256[] memory t) {
        t = new uint256[](2);
        t[0] = a;
        t[1] = b;
    }
}
