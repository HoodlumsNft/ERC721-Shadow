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

    uint256 constant PRICE = 0.0044 ether; // wei of APE per 1e18 SHARDS
    uint256 constant TOTAL_CAP = 50_000_000 ether;
    uint256 constant WALLET_CAP = 2_000_000 ether;
    uint256 saleStart;
    uint256 round1End;
    uint256 saleEnd;

    event Contributed(address indexed buyer, uint256 apePaid, uint256 tokensOwed, uint256 refunded, uint8 round);
    event Withdrawn(address indexed to, uint256 amount);

    function setUp() public {
        hoodlums = new MockHoodlums();
        hoodlums.mint(holder);
        hoodlums.mint(holder2);

        saleStart = block.timestamp + 1 days;
        round1End = saleStart + 2 days;
        saleEnd = round1End + 3 days;

        presale =
            new ShardsPresale(address(hoodlums), owner, PRICE, TOTAL_CAP, WALLET_CAP, saleStart, round1End, saleEnd);

        // WALLET_CAP worth of tokens costs (2,000,000 * PRICE) = 8,800 ether at PRICE=0.0044 ether —
        // deal generously so every test can afford to hit caps without a coincidental balance revert.
        vm.deal(holder, 100_000 ether);
        vm.deal(holder2, 100_000 ether);
        vm.deal(nonHolder, 100_000 ether);
    }

    // ---- construction ----

    function test_constructor_rejectsZeroHoodlums() public {
        vm.expectRevert(ShardsPresale.ZeroAddress.selector);
        new ShardsPresale(address(0), owner, PRICE, TOTAL_CAP, WALLET_CAP, saleStart, round1End, saleEnd);
    }

    function test_constructor_rejectsZeroPriceOrCaps() public {
        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, 0, TOTAL_CAP, WALLET_CAP, saleStart, round1End, saleEnd);

        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, PRICE, 0, WALLET_CAP, saleStart, round1End, saleEnd);

        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, PRICE, TOTAL_CAP, 0, saleStart, round1End, saleEnd);
    }

    function test_constructor_rejectsBadTimeOrdering() public {
        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, PRICE, TOTAL_CAP, WALLET_CAP, round1End, saleStart, saleEnd);

        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, PRICE, TOTAL_CAP, WALLET_CAP, saleStart, saleEnd, round1End);
    }

    // ---- round gating ----

    function test_contribute_revertsBeforeSaleStart() public {
        vm.prank(holder);
        vm.expectRevert(ShardsPresale.SaleNotOpen.selector);
        presale.contribute{value: 1 ether}();
    }

    function test_contribute_revertsAfterSaleEnd() public {
        vm.warp(saleEnd);
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

    function test_currentRound_reportsCorrectly() public {
        assertEq(presale.currentRound(), 0);
        vm.warp(saleStart);
        assertEq(presale.currentRound(), 1);
        vm.warp(round1End);
        assertEq(presale.currentRound(), 2);
        vm.warp(saleEnd);
        assertEq(presale.currentRound(), 0);
    }

    // ---- purchase math ----

    function test_contribute_grantsExactTokensForApe() public {
        vm.warp(saleStart);
        uint256 apeIn = 4.4 ether; // divides evenly at PRICE=0.0044 ether -> exactly 1,000 tokens, zero rounding dust
        vm.prank(holder);
        presale.contribute{value: apeIn}();
        assertEq(presale.contributed(holder), 1_000 ether);
        assertEq(presale.totalSold(), 1_000 ether);
        assertEq(presale.totalRaised(), apeIn);
    }

    function test_contribute_refundsExcessBeyondWalletCap() public {
        vm.warp(saleStart);
        // WALLET_CAP (2,000,000 tokens) costs 2,000,000 * PRICE / 1e18 = 8,800 ether
        uint256 costForCap = (WALLET_CAP * PRICE) / 1e18;
        uint256 sent = costForCap + 5 ether;
        uint256 balBefore = holder.balance;

        vm.prank(holder);
        presale.contribute{value: sent}();

        assertEq(presale.contributed(holder), WALLET_CAP);
        assertEq(holder.balance, balBefore - costForCap); // the extra 5 ether came straight back
    }

    function test_contribute_secondCallToppedUpToWalletCapThenReverts() public {
        vm.warp(saleStart);
        uint256 half = (WALLET_CAP / 2 * PRICE) / 1e18;
        vm.startPrank(holder);
        presale.contribute{value: half}();
        presale.contribute{value: half}();
        assertApproxEqAbs(presale.contributed(holder), WALLET_CAP, 1e12); // rounding dust only

        vm.expectRevert(ShardsPresale.WalletCapReached.selector);
        presale.contribute{value: 1 ether}();
        vm.stopPrank();
    }

    function test_contribute_refundsExcessBeyondTotalCap() public {
        // shrink the world to make totalCap reachable in-test
        ShardsPresale small = new ShardsPresale(
            address(hoodlums), owner, PRICE, 1_000_000 ether, WALLET_CAP, saleStart, round1End, saleEnd
        );
        vm.warp(saleStart);
        uint256 costForAllOfIt = (1_000_000 ether * PRICE) / 1e18;
        uint256 balBefore = holder.balance;

        vm.prank(holder);
        small.contribute{value: costForAllOfIt + 10 ether}();

        assertEq(small.totalSold(), 1_000_000 ether);
        assertEq(holder.balance, balBefore - costForAllOfIt);

        vm.prank(holder2);
        vm.expectRevert(ShardsPresale.CapReached.selector);
        small.contribute{value: 1 ether}();
    }

    function test_contribute_revertsOnZeroValue() public {
        vm.warp(saleStart);
        vm.prank(holder);
        vm.expectRevert(ShardsPresale.ZeroContribution.selector);
        presale.contribute{value: 0}();
    }

    function test_contribute_emitsWithCorrectRound() public {
        // 4.4 ether divides evenly at PRICE=0.0044 ether (exactly 1,000 tokens) so the expected
        // refund is exactly zero, not rounding dust.
        vm.warp(saleStart);
        vm.expectEmit(true, false, false, true, address(presale));
        emit Contributed(holder, 4.4 ether, 1_000 ether, 0, 1);
        vm.prank(holder);
        presale.contribute{value: 4.4 ether}();

        vm.warp(round1End);
        vm.expectEmit(true, false, false, true, address(presale));
        emit Contributed(nonHolder, 4.4 ether, 1_000 ether, 0, 2);
        vm.prank(nonHolder);
        presale.contribute{value: 4.4 ether}();
    }

    // ---- withdraw ----

    function test_withdraw_revertsBeforeSaleEnd() public {
        vm.warp(saleStart);
        vm.prank(holder);
        presale.contribute{value: 1 ether}();

        vm.prank(owner);
        vm.expectRevert(ShardsPresale.TooEarlyToWithdraw.selector);
        presale.withdraw(payable(treasury), 1 ether);
    }

    function test_withdraw_onlyOwner() public {
        vm.warp(saleEnd);
        vm.expectRevert();
        presale.withdraw(payable(treasury), 0);
    }

    function test_withdraw_paysOutAndTracksCumulative() public {
        vm.warp(saleStart);
        vm.prank(holder);
        presale.contribute{value: 10 ether}();
        vm.warp(saleEnd);

        vm.prank(owner);
        presale.withdraw(payable(treasury), 4 ether);
        assertEq(treasury.balance, 4 ether);
        assertEq(presale.totalWithdrawn(), 4 ether);

        vm.prank(owner);
        vm.expectRevert(ShardsPresale.InsufficientBalance.selector);
        presale.withdraw(payable(treasury), 10 ether); // only 6 ether left
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
        assertEq(preview, (1 ether * 1e18) / PRICE);

        assertEq(presale.previewTokensOut(nonHolder, 1 ether), 0); // gated out of round 1

        vm.warp(round1End);
        assertEq(presale.previewTokensOut(nonHolder, 1 ether), (1 ether * 1e18) / PRICE);
    }

    function test_remainingCap_decreasesAsSold() public {
        assertEq(presale.remainingCap(), TOTAL_CAP);
        vm.warp(saleStart);
        vm.prank(holder);
        presale.contribute{value: 4.4 ether}();
        assertEq(presale.remainingCap(), TOTAL_CAP - 1_000 ether);
    }

    function test_remainingWalletCap_decreasesAsContributed() public {
        vm.warp(saleStart);
        assertEq(presale.remainingWalletCap(holder), WALLET_CAP);
        vm.prank(holder);
        presale.contribute{value: 1 ether}();
        assertEq(presale.remainingWalletCap(holder), WALLET_CAP - presale.contributed(holder));
    }
}
