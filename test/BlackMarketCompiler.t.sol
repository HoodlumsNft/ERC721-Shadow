// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/gear/GearModule1155.sol";
import "../contracts/gear/BlackMarketCompiler.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/**
 * Minimal freely-mintable ERC1155 standing in for DataShard1155 — unit tests
 * here cover the Compiler's OWN logic (signature verification, replay,
 * recipe cost enforcement, atomicity). DataShard1155 is ERC1155C with a
 * Limitbreak transfer validator in front of every transfer, which can't be
 * exercised in the same compilation unit as this contract without an OZ
 * 4.8.3/5.5.0 identifier collision (DataShard1155's dependency chain mixes
 * both). That interaction is verified for real against the deployed mainnet
 * DataShard1155 + Compiler during the live E2E deploy step instead — a
 * stronger check than a mock could give anyway.
 */
contract MockShard is ERC1155 {
    constructor() ERC1155("") {}
    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
}

contract BlackMarketCompilerTest is Test {
    MockShard shard;
    GearModule1155 gear;
    BlackMarketCompiler compiler;

    uint256 craftSignerPk = 0xB0B;
    address craftSigner;
    address player = address(0xBEEF);

    // Scrap Assembly: 5x Glitch Bit (tier 1) -> 1 output
    uint256 constant RECIPE_SCRAP = 1;

    function setUp() public {
        craftSigner = vm.addr(craftSignerPk);

        shard = new MockShard();
        gear = new GearModule1155(address(0), "ipfs://gear/"); // minter set after compiler deploys
        compiler = new BlackMarketCompiler(address(shard), address(gear), craftSigner);
        gear.setMinter(address(compiler));

        uint256[] memory costTiers = new uint256[](1);
        uint256[] memory costAmounts = new uint256[](1);
        costTiers[0] = 1;
        costAmounts[0] = 5;
        compiler.setRecipe(RECIPE_SCRAP, costTiers, costAmounts, true);

        shard.mint(player, 1, 5);
        vm.prank(player);
        shard.setApprovalForAll(address(compiler), true);
    }

    function _signCompile(
        address operator,
        uint256 recipeId,
        uint256 craftId,
        uint256[] memory outputIds,
        uint256[] memory outputAmounts,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                compiler.COMPILE_TYPEHASH(),
                operator,
                recipeId,
                craftId,
                keccak256(abi.encodePacked(outputIds)),
                keccak256(abi.encodePacked(outputAmounts)),
                deadline
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(
                    abi.encode(
                        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                        keccak256(bytes("Hoodlums Blacknet Compiler")),
                        keccak256(bytes("1")),
                        block.chainid,
                        address(compiler)
                    )
                ),
                structHash
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(craftSignerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _defaultOutput() internal pure returns (uint256[] memory ids, uint256[] memory amounts) {
        ids = new uint256[](1);
        amounts = new uint256[](1);
        ids[0] = 1; // Neon Shiv
        amounts[0] = 1;
    }

    function testCompileBurnsShardsAndMintsGear() public {
        (uint256[] memory outIds, uint256[] memory outAmounts) = _defaultOutput();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signCompile(player, RECIPE_SCRAP, 42, outIds, outAmounts, deadline);

        assertEq(shard.balanceOf(player, 1), 5);
        assertEq(gear.balanceOf(player, 1), 0);

        vm.prank(player);
        compiler.compile(RECIPE_SCRAP, 42, outIds, outAmounts, deadline, proof);

        assertEq(shard.balanceOf(player, 1), 0, "shards burned");
        assertEq(shard.balanceOf(compiler.BURN_ADDRESS(), 1), 5, "shards sent to burn address");
        assertEq(gear.balanceOf(player, 1), 1, "gear minted");
    }

    function testTwoOutputItemsMintBoth() public {
        uint256[] memory outIds = new uint256[](2);
        uint256[] memory outAmounts = new uint256[](2);
        outIds[0] = 1;
        outIds[1] = 30;
        outAmounts[0] = 1;
        outAmounts[1] = 1;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signCompile(player, RECIPE_SCRAP, 43, outIds, outAmounts, deadline);

        vm.prank(player);
        compiler.compile(RECIPE_SCRAP, 43, outIds, outAmounts, deadline, proof);

        assertEq(gear.balanceOf(player, 1), 1);
        assertEq(gear.balanceOf(player, 30), 1);
    }

    function testCraftReplayReverts() public {
        (uint256[] memory outIds, uint256[] memory outAmounts) = _defaultOutput();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signCompile(player, RECIPE_SCRAP, 42, outIds, outAmounts, deadline);

        vm.prank(player);
        compiler.compile(RECIPE_SCRAP, 42, outIds, outAmounts, deadline, proof);

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(BlackMarketCompiler.CraftAlreadyClaimed.selector, 42));
        compiler.compile(RECIPE_SCRAP, 42, outIds, outAmounts, deadline, proof);
    }

    function testWrongSignerReverts() public {
        (uint256[] memory outIds, uint256[] memory outAmounts) = _defaultOutput();
        uint256 deadline = block.timestamp + 1 hours;
        uint256 wrongPk = 0xA11CE;
        bytes32 structHash = keccak256(
            abi.encode(compiler.COMPILE_TYPEHASH(), player, RECIPE_SCRAP, uint256(99), keccak256(abi.encodePacked(outIds)), keccak256(abi.encodePacked(outAmounts)), deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"), keccak256(bytes("Hoodlums Blacknet Compiler")), keccak256(bytes("1")), block.chainid, address(compiler))),
                structHash
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory badProof = abi.encodePacked(r, s, v);

        vm.prank(player);
        vm.expectRevert(BlackMarketCompiler.InvalidProof.selector);
        compiler.compile(RECIPE_SCRAP, 99, outIds, outAmounts, deadline, badProof);
    }

    function testTamperedOutputRejected() public {
        (uint256[] memory outIds, uint256[] memory outAmounts) = _defaultOutput();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signCompile(player, RECIPE_SCRAP, 44, outIds, outAmounts, deadline);

        // player tries to swap the signed output for a better module after the fact
        uint256[] memory tamperedIds = new uint256[](1);
        tamperedIds[0] = 5; // ApeNet Cannon instead of the signed Neon Shiv
        vm.prank(player);
        vm.expectRevert(BlackMarketCompiler.InvalidProof.selector);
        compiler.compile(RECIPE_SCRAP, 44, tamperedIds, outAmounts, deadline, proof);
    }

    function testExpiredProofReverts() public {
        (uint256[] memory outIds, uint256[] memory outAmounts) = _defaultOutput();
        uint256 deadline = block.timestamp + 1;
        bytes memory proof = _signCompile(player, RECIPE_SCRAP, 7, outIds, outAmounts, deadline);

        vm.warp(deadline + 1);
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(BlackMarketCompiler.ProofExpired.selector, deadline));
        compiler.compile(RECIPE_SCRAP, 7, outIds, outAmounts, deadline, proof);
    }

    function testUnknownRecipeReverts() public {
        (uint256[] memory outIds, uint256[] memory outAmounts) = _defaultOutput();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signCompile(player, 999, 8, outIds, outAmounts, deadline);

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(BlackMarketCompiler.UnknownRecipe.selector, 999));
        compiler.compile(999, 8, outIds, outAmounts, deadline, proof);
    }

    function testCompileWithoutApprovalReverts() public {
        address other = address(0xCAFE);
        vm.prank(player);
        shard.safeTransferFrom(player, other, 1, 5, "");

        (uint256[] memory outIds, uint256[] memory outAmounts) = _defaultOutput();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signCompile(other, RECIPE_SCRAP, 55, outIds, outAmounts, deadline);

        vm.prank(other);
        vm.expectRevert();
        compiler.compile(RECIPE_SCRAP, 55, outIds, outAmounts, deadline, proof);
    }

    function testCompileWithoutEnoughShardsReverts() public {
        vm.prank(player);
        shard.safeTransferFrom(player, address(0xCAFE), 1, 3, "");

        (uint256[] memory outIds, uint256[] memory outAmounts) = _defaultOutput();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signCompile(player, RECIPE_SCRAP, 66, outIds, outAmounts, deadline);

        vm.prank(player);
        vm.expectRevert();
        compiler.compile(RECIPE_SCRAP, 66, outIds, outAmounts, deadline, proof);
    }

    function testOnlyCompilerCanMintGear() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = 1;
        amounts[0] = 1;
        vm.expectRevert(GearModule1155.NotMinter.selector);
        gear.mintBatch(player, ids, amounts);
    }

    function testGearRejectsOutOfRangeModuleId() public {
        (uint256[] memory outIds, uint256[] memory outAmounts) = _defaultOutput();
        outIds[0] = 51; // out of range (1-50)
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signCompile(player, RECIPE_SCRAP, 100, outIds, outAmounts, deadline);

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(GearModule1155.InvalidModule.selector, 51));
        compiler.compile(RECIPE_SCRAP, 100, outIds, outAmounts, deadline, proof);
    }

    function testAdminOnlyFunctions() public {
        uint256[] memory tiers = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        tiers[0] = 1;
        amounts[0] = 1;

        vm.startPrank(player);
        vm.expectRevert();
        compiler.setRecipe(2, tiers, amounts, true);
        vm.expectRevert();
        compiler.setCraftSigner(player);
        vm.expectRevert();
        gear.setMinter(player);
        vm.stopPrank();
    }

    function testGearUri() public view {
        assertEq(gear.uri(5), "ipfs://gear/5.json");
    }
}
