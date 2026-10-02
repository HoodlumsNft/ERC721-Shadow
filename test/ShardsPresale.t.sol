// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/ShardsPresale.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockHoodlums is ERC721 {
    uint256 public nextId;

    constructor() ERC721("MockHoodlums", "MHOOD") {}

    function mint(address to) external {
        _mint(to, nextId++);
    }
}

contract ShardsPresaleTest is Test {
    ShardsPresale presale;
    MockHoodlums hoodlums;

    address owner = address(0x0123456789012345678901234567890123456789);
    address holder = address(0xBEEF);
    address holder2 = address(0xBEE2);
    address nonHolder = address(0xDEAD);
    address treasury = address(0x7EA5);

    uint256 constant ROUND1_PRICE = 0.0017 ether; // wei of APE per 1e18 SHARDS, holders-only round
    uint256 constant ROUND2_PRICE = 0.002 ether; // public round, priced higher
    uint256 constant WALLET_CAP = 2_000_000 ether;
    uint256 saleStart;
    uint256 round1End;

    event Contributed(address indexed buyer, uint256 apePaid, uint256 tokensOwed, uint256 refunded, uint8 round);
    event Withdrawn(address indexed to, uint256 amount);

    function setUp() public {
        hoodlums = new MockHoodlums();
        hoodlums.mint(holder);
        hoodlums.mint(holder2);

        saleStart = block.timestamp + 1 days;
        round1End = saleStart + 2 days;

        presale = new ShardsPresale(address(hoodlums), owner, ROUND1_PRICE, ROUND2_PRICE, WALLET_CAP, saleStart, round1End);

        // WALLET_CAP worth of tokens costs up to 2,000,000 * ROUND2_PRICE = 4,000 ether at the
        // higher round's price — deal generously so every test can afford to hit caps without a
        // coincidental balance revert.
        vm.deal(holder, 100_000 ether);
        vm.deal(holder2, 100_000 ether);
        vm.deal(nonHolder, 100_000 ether);
    }

    // ---- construction ----

    function test_constructor_rejectsZeroHoodlums() public {
        vm.expectRevert(ShardsPresale.ZeroAddress.selector);
        new ShardsPresale(address(0), owner, ROUND1_PRICE, ROUND2_PRICE, WALLET_CAP, saleStart, round1End);
    }

    function test_constructor_rejectsZeroPriceOrCap() public {
        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, 0, ROUND2_PRICE, WALLET_CAP, saleStart, round1End);

        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, ROUND1_PRICE, 0, WALLET_CAP, saleStart, round1End);

        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, ROUND1_PRICE, ROUND2_PRICE, 0, saleStart, round1End);
    }

    function test_constructor_rejectsRound2PriceBelowRound1() public {
        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, ROUND2_PRICE, ROUND1_PRICE, WALLET_CAP, saleStart, round1End);
    }

    function test_constructor_rejectsBadTimeOrdering() public {
        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, ROUND1_PRICE, ROUND2_PRICE, WALLET_CAP, round1End, saleStart);
    }

    // ---- round gating ----

    function test_contribute_revertsBeforeSaleStart() public {
        vm.prank(holder);
        vm.expectRevert(ShardsPresale.SaleNotOpen.selector);
        presale.contribute{value: 1 ether}();
    }

    function test_round1_rejectsNonHolder() public {
        vm.warp(saleStart);
        vm.prank(nonHolder);
        vm.expectRevert(ShardsPresale.NotAHoodlumsHolder.selector);
        presale.contribute{value: 1 ether}();
    }

    function test_round1_acceptsHolder() public {
        vm.warp(saleStart);
        vm.prank(holder);
        presale.contribute{value: 1 ether}();
        assertGt(presale.contributed(holder), 0);
    }

    function test_round2_acceptsNonHolder() public {
        vm.warp(round1End);
        vm.prank(nonHolder);
        presale.contribute{value: 1 ether}();
        assertGt(presale.contributed(nonHolder), 0);
    }

    function test_round2_hasNoEnd_stillAcceptsContributionsFarInTheFuture() public {
        // The headline change: there is no saleEnd anymore. Round 2 just keeps running.
        vm.warp(round1End + 365 days);
        vm.prank(nonHolder);
        presale.contribute{value: 1 ether}();
        assertGt(presale.contributed(nonHolder), 0);
    }

    function test_currentRound_reportsCorrectly() public {
        assertEq(presale.currentRound(), 0);
        vm.warp(saleStart);
        assertEq(presale.currentRound(), 1);
        vm.warp(round1End);
        assertEq(presale.currentRound(), 2);
        vm.warp(round1End + 365 days);
        assertEq(presale.currentRound(), 2); // stays 2 forever, no auto-close
    }

    // ---- purchase math ----

    function test_contribute_usesRound1PriceDuringRound1() public {
        vm.warp(saleStart);
        uint256 apeIn = 1.7 ether; // divides evenly at ROUND1_PRICE=0.0017 ether -> exactly 1,000 tokens
        vm.prank(holder);
        presale.contribute{value: apeIn}();
        assertEq(presale.contributed(holder), 1_000 ether);
        assertEq(presale.totalSold(), 1_000 ether);
        assertEq(presale.totalRaised(), apeIn);
    }

    function test_contribute_usesRound2PriceDuringRound2() public {
        vm.warp(round1End);
        uint256 apeIn = 2 ether; // divides evenly at ROUND2_PRICE=0.002 ether -> exactly 1,000 tokens
        vm.prank(nonHolder);
        presale.contribute{value: apeIn}();
        assertEq(presale.contributed(nonHolder), 1_000 ether);
        assertEq(presale.totalRaised(), apeIn);
    }

    function test_contribute_refundsExcessBeyondWalletCap() public {
        vm.warp(saleStart);
        // WALLET_CAP (2,000,000 tokens) costs 2,000,000 * ROUND1_PRICE / 1e18 = 3,400 ether
        uint256 costForCap = (WALLET_CAP * ROUND1_PRICE) / 1e18;
        uint256 sent = costForCap + 5 ether;
        uint256 balBefore = holder.balance;

        vm.prank(holder);
        presale.contribute{value: sent}();

        assertEq(presale.contributed(holder), WALLET_CAP);
        assertEq(holder.balance, balBefore - costForCap); // the extra 5 ether came straight back
    }

    function test_contribute_secondCallToppedUpToWalletCapThenReverts() public {
        vm.warp(saleStart);
        uint256 half = (WALLET_CAP / 2 * ROUND1_PRICE) / 1e18;
        vm.startPrank(holder);
        presale.contribute{value: half}();
        presale.contribute{value: half}();
        assertApproxEqAbs(presale.contributed(holder), WALLET_CAP, 1e12); // rounding dust only

        vm.expectRevert(ShardsPresale.WalletCapReached.selector);
        presale.contribute{value: 1 ether}();
        vm.stopPrank();
    }

    function test_contribute_noTotalRaiseCap_acceptsArbitrarilyLargeDemand() public {
        // Headline change: there is no totalCap anymore. Many wallets can each hit their own
        // perWalletCap with nothing stopping the sale overall.
        vm.warp(round1End);
        address[] memory buyers = new address[](3);
        buyers[0] = address(0xA1);
        buyers[1] = address(0xA2);
        buyers[2] = address(0xA3);
        uint256 costForCap = (WALLET_CAP * ROUND2_PRICE) / 1e18;
        for (uint256 i = 0; i < buyers.length; i++) {
            vm.deal(buyers[i], costForCap);
            vm.prank(buyers[i]);
            presale.contribute{value: costForCap}();
            assertEq(presale.contributed(buyers[i]), WALLET_CAP);
        }
        assertEq(presale.totalSold(), WALLET_CAP * 3);
    }

    function test_contribute_revertsOnZeroValue() public {
        vm.warp(saleStart);
        vm.prank(holder);
        vm.expectRevert(ShardsPresale.ZeroContribution.selector);
        presale.contribute{value: 0}();
    }

    function test_contribute_emitsWithCorrectRoundAndPrice() public {
        vm.warp(saleStart);
        vm.expectEmit(true, false, false, true, address(presale));
        emit Contributed(holder, 1.7 ether, 1_000 ether, 0, 1);
        vm.prank(holder);
        presale.contribute{value: 1.7 ether}();

        vm.warp(round1End);
        vm.expectEmit(true, false, false, true, address(presale));
        emit Contributed(nonHolder, 2 ether, 1_000 ether, 0, 2);
        vm.prank(nonHolder);
        presale.contribute{value: 2 ether}();
    }

    // ---- withdraw ----

    function test_withdraw_revertsWhileSaleStillActive() public {
        vm.warp(saleStart);
        vm.prank(holder);
        presale.contribute{value: 1 ether}();

        vm.prank(owner);
        vm.expectRevert(ShardsPresale.SaleStillActive.selector);
        presale.withdraw(payable(treasury), 1 ether);
    }

    function test_withdraw_unlocksOncePaused() public {
        vm.warp(saleStart);
        vm.prank(holder);
        presale.contribute{value: 10 ether}();

        vm.prank(owner);
        presale.pause();

        vm.prank(owner);
        presale.withdraw(payable(treasury), 4 ether);
        assertEq(treasury.balance, 4 ether);
        assertEq(presale.totalWithdrawn(), 4 ether);

        vm.prank(owner);
        vm.expectRevert(ShardsPresale.InsufficientBalance.selector);
        presale.withdraw(payable(treasury), 10 ether); // only 6 ether left
    }

    function test_withdraw_onlyOwner() public {
        vm.prank(owner);
        presale.pause();
        vm.expectRevert();
        presale.withdraw(payable(treasury), 0);
    }

    // ---- pause ----

    function test_pause_blocksContributions() public {
        vm.warp(saleStart);
        vm.prank(owner);
        presale.pause();

        vm.prank(holder);
        vm.expectRevert();
        presale.contribute{value: 1 ether}();

        vm.prank(owner);
        presale.unpause();
        vm.prank(holder);
        presale.contribute{value: 1 ether}(); // works again
    }

    // ---- views ----

    function test_previewTokensOut_matchesActualClamping() public {
        vm.warp(saleStart);
        uint256 preview = presale.previewTokensOut(holder, 1 ether);
        assertEq(preview, (1 ether * 1e18) / ROUND1_PRICE);

        assertEq(presale.previewTokensOut(nonHolder, 1 ether), 0); // gated out of round 1

        vm.warp(round1End);
        assertEq(presale.previewTokensOut(nonHolder, 1 ether), (1 ether * 1e18) / ROUND2_PRICE);
    }

    function test_previewTokensOut_isZeroWhilePaused() public {
        vm.warp(saleStart);
        vm.prank(owner);
        presale.pause();
        assertEq(presale.previewTokensOut(holder, 1 ether), 0);
    }

    function test_currentPrice_switchesAtRound1End() public {
        vm.warp(saleStart);
        assertEq(presale.currentPrice(), ROUND1_PRICE);
        vm.warp(round1End);
        assertEq(presale.currentPrice(), ROUND2_PRICE);
    }

    function test_remainingWalletCap_decreasesAsContributed() public {
        vm.warp(saleStart);
        assertEq(presale.remainingWalletCap(holder), WALLET_CAP);
        vm.prank(holder);
        presale.contribute{value: 1 ether}();
        assertEq(presale.remainingWalletCap(holder), WALLET_CAP - presale.contributed(holder));
    }
}
