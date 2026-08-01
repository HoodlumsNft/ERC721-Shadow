// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/decks/MissionDeck1155.sol";

contract MissionDeck1155Test is Test {
    MissionDeck1155 deck;

    uint256 packSignerPk = 0xB0B;
    address packSigner;
    address player = address(0xBEEF);

    uint256 constant RUNNER = 1;
    uint256 constant GHOST = 2;
    uint256 constant WRAITH = 3;
    uint256 constant APEX = 4;

    function setUp() public {
        packSigner = vm.addr(packSignerPk);
        deck = new MissionDeck1155(packSigner, "ipfs://decks/");
        vm.deal(player, 1000 ether);
    }

    function _signPack(address buyer, uint256 packId, uint256 tier, uint256 price, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(deck.OPEN_PACK_TYPEHASH(), buyer, packId, tier, price, deadline));
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(
                    abi.encode(
                        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                        keccak256(bytes("Hoodlums Blacknet Decks")),
                        keccak256(bytes("1")),
                        block.chainid,
                        address(deck)
                    )
                ),
                structHash
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(packSignerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    // ---- direct purchase ----

    function testPurchaseMintsCorrectTierAtCorrectPrice() public {
        assertEq(deck.balanceOf(player, RUNNER), 0);

        vm.prank(player);
        deck.purchase{value: 10 ether}(RUNNER);

        assertEq(deck.balanceOf(player, RUNNER), 1);
        assertEq(address(deck).balance, 10 ether);
    }

    function testPurchaseEachTierAtDefaultPrice() public {
        vm.startPrank(player);
        deck.purchase{value: 10 ether}(RUNNER);
        deck.purchase{value: 25 ether}(GHOST);
        deck.purchase{value: 55 ether}(WRAITH);
        deck.purchase{value: 100 ether}(APEX);
        vm.stopPrank();

        assertEq(deck.balanceOf(player, RUNNER), 1);
        assertEq(deck.balanceOf(player, GHOST), 1);
        assertEq(deck.balanceOf(player, WRAITH), 1);
        assertEq(deck.balanceOf(player, APEX), 1);
    }

    function testPurchaseWrongPaymentReverts() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(MissionDeck1155.WrongPayment.selector, 10 ether, 5 ether));
        deck.purchase{value: 5 ether}(RUNNER);
    }

    function testPurchaseInvalidTierReverts() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(MissionDeck1155.InvalidTier.selector, 5));
        deck.purchase{value: 100 ether}(5);
    }

    function testPurchaseReflectsUpdatedPrice() public {
        deck.setPrice(RUNNER, 12 ether);

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(MissionDeck1155.WrongPayment.selector, 12 ether, 10 ether));
        deck.purchase{value: 10 ether}(RUNNER);

        vm.prank(player);
        deck.purchase{value: 12 ether}(RUNNER);
        assertEq(deck.balanceOf(player, RUNNER), 1);
    }

    function testNonAdminCannotSetPrice() public {
        vm.prank(player);
        vm.expectRevert();
        deck.setPrice(RUNNER, 1 ether);
    }

    // ---- packs ----

    function testOpenPackMintsSignedTier() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signPack(player, 1, WRAITH, 15 ether, deadline);

        vm.prank(player);
        deck.openPack{value: 15 ether}(1, WRAITH, deadline, proof);

        assertEq(deck.balanceOf(player, WRAITH), 1);
    }

    function testOpenPackReplayReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signPack(player, 1, RUNNER, 15 ether, deadline);

        vm.prank(player);
        deck.openPack{value: 15 ether}(1, RUNNER, deadline, proof);

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(MissionDeck1155.PackAlreadyClaimed.selector, 1));
        deck.openPack{value: 15 ether}(1, RUNNER, deadline, proof);
    }

    function testOpenPackWrongSignerReverts() public {
        uint256 wrongPk = 0xA11CE;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(abi.encode(deck.OPEN_PACK_TYPEHASH(), player, uint256(2), APEX, uint256(15 ether), deadline));
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(
                    abi.encode(
                        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                        keccak256(bytes("Hoodlums Blacknet Decks")),
                        keccak256(bytes("1")),
                        block.chainid,
                        address(deck)
                    )
                ),
                structHash
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory badProof = abi.encodePacked(r, s, v);

        vm.prank(player);
        vm.expectRevert(MissionDeck1155.InvalidProof.selector);
        deck.openPack{value: 15 ether}(2, APEX, deadline, badProof);
    }

    function testOpenPackTamperedTierRejected() public {
        uint256 deadline = block.timestamp + 1 hours;
        // signed for RUNNER, player tries to claim APEX with the same proof
        bytes memory proof = _signPack(player, 3, RUNNER, 15 ether, deadline);

        vm.prank(player);
        vm.expectRevert(MissionDeck1155.InvalidProof.selector);
        deck.openPack{value: 15 ether}(3, APEX, deadline, proof);
    }

    function testOpenPackExpiredReverts() public {
        uint256 deadline = block.timestamp + 1;
        bytes memory proof = _signPack(player, 4, GHOST, 15 ether, deadline);

        vm.warp(deadline + 1);
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(MissionDeck1155.ProofExpired.selector, deadline));
        deck.openPack{value: 15 ether}(4, GHOST, deadline, proof);
    }

    function testOpenPackWrongPaymentReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _signPack(player, 5, GHOST, 15 ether, deadline);

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(MissionDeck1155.WrongPayment.selector, 15 ether, 10 ether));
        deck.openPack{value: 10 ether}(5, GHOST, deadline, proof);
    }

    // ---- admin ----

    function testAdminOnlyFunctions() public {
        vm.startPrank(player);
        vm.expectRevert();
        deck.setPrice(RUNNER, 1 ether);
        vm.expectRevert();
        deck.setPackPrice(1 ether);
        vm.expectRevert();
        deck.setPackSigner(player);
        vm.expectRevert();
        deck.setBaseURI("ipfs://evil/");
        vm.expectRevert();
        deck.withdraw(payable(player), 1 ether);
        vm.stopPrank();
    }

    function testWithdrawSendsFundsToTreasury() public {
        vm.prank(player);
        deck.purchase{value: 10 ether}(RUNNER);

        address treasury = address(0xFEED);
        deck.withdraw(payable(treasury), 10 ether);

        assertEq(treasury.balance, 10 ether);
        assertEq(address(deck).balance, 0);
    }

    // ---- views ----

    function testDeckUri() public view {
        assertEq(deck.uri(RUNNER), "ipfs://decks/1.json");
    }
}
