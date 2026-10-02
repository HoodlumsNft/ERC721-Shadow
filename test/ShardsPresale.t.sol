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

/// @notice Mock for delegate.xyz's DelegateRegistry, etched at its canonical mainnet address in tests.
contract MockDelegateRegistry {
    mapping(bytes32 => bool) public allDelegations;
    mapping(bytes32 => bool) public contractDelegations;

    function setAllDelegation(address to, address from, bool allowed) external {
        allDelegations[keccak256(abi.encode(to, from))] = allowed;
    }

    function setContractDelegation(address to, address from, address contract_, bool allowed) external {
        contractDelegations[keccak256(abi.encode(to, from, contract_))] = allowed;
    }

    function checkDelegateForAll(address to, address from, bytes32) external view returns (bool) {
        return allDelegations[keccak256(abi.encode(to, from))];
    }

    function checkDelegateForContract(address to, address from, address contract_, bytes32) external view returns (bool) {
        return contractDelegations[keccak256(abi.encode(to, from, contract_))];
    }
}

contract ShardsPresaleTest is Test {
    address constant DELEGATE_REGISTRY_ADDR = 0x00000000000000447e69651d841bD8D104Bed493;

    ShardsPresale presale;
    MockHoodlums hoodlums;
    MockDelegateRegistry registry;

    address owner = address(0x0123456789012345678901234567890123456789);
    address holder = address(0xBEEF);
    address holder2 = address(0xBEE2);
    address nonHolder = address(0xDEAD);
    address vault = address(0x7A017);
    address treasury = address(0x7EA5);

    uint256 constant HOLDER_PRICE = 0.0017 ether; // wei of APE per 1e18 SHARDS
    uint256 constant PUBLIC_PRICE = 0.002 ether;
    uint256 constant WALLET_CAP = 2_000_000 ether;
    uint256 saleStart;

    event Contributed(address indexed buyer, uint256 apePaid, uint256 tokensOwed, uint256 refunded, bool isHolder);
    event Withdrawn(address indexed to, uint256 amount);

    function setUp() public {
        hoodlums = new MockHoodlums();
        hoodlums.mint(holder);
        hoodlums.mint(holder2);

        MockDelegateRegistry mockImpl = new MockDelegateRegistry();
        vm.etch(DELEGATE_REGISTRY_ADDR, address(mockImpl).code);
        registry = MockDelegateRegistry(DELEGATE_REGISTRY_ADDR);

        saleStart = block.timestamp + 1 days;

        presale = new ShardsPresale(address(hoodlums), owner, HOLDER_PRICE, PUBLIC_PRICE, WALLET_CAP, saleStart);

        vm.deal(holder, 100_000 ether);
        vm.deal(holder2, 100_000 ether);
        vm.deal(nonHolder, 100_000 ether);
    }

    // ---- construction ----

    function test_constructor_rejectsZeroHoodlums() public {
        vm.expectRevert(ShardsPresale.ZeroAddress.selector);
        new ShardsPresale(address(0), owner, HOLDER_PRICE, PUBLIC_PRICE, WALLET_CAP, saleStart);
    }

    function test_constructor_rejectsZeroPriceOrCap() public {
        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, 0, PUBLIC_PRICE, WALLET_CAP, saleStart);

        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, HOLDER_PRICE, 0, WALLET_CAP, saleStart);

        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, HOLDER_PRICE, PUBLIC_PRICE, 0, saleStart);
    }

    function test_constructor_rejectsPublicPriceBelowHolderPrice() public {
        vm.expectRevert(ShardsPresale.InvalidConfig.selector);
        new ShardsPresale(address(hoodlums), owner, PUBLIC_PRICE, HOLDER_PRICE, WALLET_CAP, saleStart);
    }

    // ---- gating ----

    function test_contribute_revertsBeforeSaleStart() public {
        vm.prank(holder);
        vm.expectRevert(ShardsPresale.SaleNotOpen.selector);
        presale.contribute{value: 1 ether}(address(0));
    }

    function test_nonHolder_canBuyFromSaleStart_atPublicPrice() public {
        vm.warp(saleStart);
        vm.prank(nonHolder);
        presale.contribute{value: 1 ether}(address(0));
        assertGt(presale.contributed(nonHolder), 0);
    }

    // ---- purchase math ----

    function test_contribute_usesHolderPriceForHolder() public {
        vm.warp(saleStart);
        uint256 apeIn = 1.7 ether; // divides evenly at HOLDER_PRICE=0.0017 ether -> exactly 1,000 tokens
        vm.prank(holder);
        presale.contribute{value: apeIn}(address(0));
        assertEq(presale.contributed(holder), 1_000 ether);
        assertEq(presale.totalSold(), 1_000 ether);
        assertEq(presale.totalRaised(), apeIn);
    }

    function test_contribute_usesPublicPriceForNonHolder() public {
        vm.warp(saleStart);
        uint256 apeIn = 2 ether; // divides evenly at PUBLIC_PRICE=0.002 ether -> exactly 1,000 tokens
        vm.prank(nonHolder);
        presale.contribute{value: apeIn}(address(0));
        assertEq(presale.contributed(nonHolder), 1_000 ether);
        assertEq(presale.totalRaised(), apeIn);
    }

    function test_contribute_refundsExcessBeyondWalletCap() public {
        vm.warp(saleStart);
        uint256 costForCap = (WALLET_CAP * HOLDER_PRICE) / 1e18;
        uint256 sent = costForCap + 5 ether;
        uint256 balBefore = holder.balance;

        vm.prank(holder);
        presale.contribute{value: sent}(address(0));

        assertEq(presale.contributed(holder), WALLET_CAP);
        assertEq(holder.balance, balBefore - costForCap);
    }

    function test_contribute_secondCallToppedUpToWalletCapThenReverts() public {
        vm.warp(saleStart);
        uint256 half = (WALLET_CAP / 2 * HOLDER_PRICE) / 1e18;
        vm.startPrank(holder);
        presale.contribute{value: half}(address(0));
        presale.contribute{value: half}(address(0));
        assertApproxEqAbs(presale.contributed(holder), WALLET_CAP, 1e12); // rounding dust only

        vm.expectRevert(ShardsPresale.WalletCapReached.selector);
        presale.contribute{value: 1 ether}(address(0));
        vm.stopPrank();
    }

    function test_contribute_noTotalRaiseCap_acceptsArbitrarilyLargeDemand() public {
        vm.warp(saleStart);
        address[] memory buyers = new address[](3);
        buyers[0] = address(0xA1);
        buyers[1] = address(0xA2);
        buyers[2] = address(0xA3);
        uint256 costForCap = (WALLET_CAP * PUBLIC_PRICE) / 1e18;
        for (uint256 i = 0; i < buyers.length; i++) {
            vm.deal(buyers[i], costForCap);
            vm.prank(buyers[i]);
            presale.contribute{value: costForCap}(address(0));
            assertEq(presale.contributed(buyers[i]), WALLET_CAP);
        }
        assertEq(presale.totalSold(), WALLET_CAP * 3);
    }

    function test_contribute_revertsOnZeroValue() public {
        vm.warp(saleStart);
        vm.prank(holder);
        vm.expectRevert(ShardsPresale.ZeroContribution.selector);
        presale.contribute{value: 0}(address(0));
    }

    function test_contribute_emitsWithHolderFlagAndPrice() public {
        vm.warp(saleStart);
        vm.expectEmit(true, false, false, true, address(presale));
        emit Contributed(holder, 1.7 ether, 1_000 ether, 0, true);
        vm.prank(holder);
        presale.contribute{value: 1.7 ether}(address(0));

        vm.expectEmit(true, false, false, true, address(presale));
        emit Contributed(nonHolder, 2 ether, 1_000 ether, 0, false);
        vm.prank(nonHolder);
        presale.contribute{value: 2 ether}(address(0));
    }

    function test_contribute_priceFollowsCurrentHoldingsNotASnapshot() public {
        // A wallet that acquires a Hoodlum between contributions immediately gets the holder price.
        vm.warp(saleStart);
        vm.prank(nonHolder);
        presale.contribute{value: 2 ether}(address(0)); // public price -> 1,000 tokens

        hoodlums.mint(nonHolder);
        vm.prank(nonHolder);
        presale.contribute{value: 1.7 ether}(address(0)); // now a holder -> holder price -> another 1,000 tokens

        assertEq(presale.contributed(nonHolder), 2_000 ether);
    }

    // ---- delegation ----

    function test_delegation_allScope_getsHolderPrice() public {
        hoodlums.mint(vault);
        registry.setAllDelegation(nonHolder, vault, true);

        vm.warp(saleStart);
        vm.prank(nonHolder);
        presale.contribute{value: 1.7 ether}(vault);
        assertEq(presale.contributed(nonHolder), 1_000 ether); // holder price applied
    }

    function test_delegation_contractScope_getsHolderPrice() public {
        hoodlums.mint(vault);
        registry.setContractDelegation(nonHolder, vault, address(hoodlums), true);

        vm.warp(saleStart);
        vm.prank(nonHolder);
        presale.contribute{value: 1.7 ether}(vault);
        assertEq(presale.contributed(nonHolder), 1_000 ether);
    }

    function test_delegation_ignoredIfVaultHoldsNoHoodlum() public {
        // registry says delegated, but the vault itself doesn't actually hold a Hoodlum
        registry.setAllDelegation(nonHolder, vault, true);

        vm.warp(saleStart);
        vm.prank(nonHolder);
        presale.contribute{value: 2 ether}(vault);
        assertEq(presale.contributed(nonHolder), 1_000 ether); // public price (2 ether / 0.002)
    }

    function test_delegation_ignoredIfNoRealDelegationRecord() public {
        // vault genuinely holds a Hoodlum, but never delegated to nonHolder -- passing its address
        // as `vault` must not be enough on its own to claim the holder price.
        hoodlums.mint(vault);

        vm.warp(saleStart);
        vm.prank(nonHolder);
        presale.contribute{value: 2 ether}(vault);
        assertEq(presale.contributed(nonHolder), 1_000 ether); // still public price
    }

    // ---- withdraw ----

    function test_withdraw_revertsWhileSaleStillActive() public {
        vm.warp(saleStart);
        vm.prank(holder);
        presale.contribute{value: 1 ether}(address(0));

        vm.prank(owner);
        vm.expectRevert(ShardsPresale.SaleStillActive.selector);
        presale.withdraw(payable(treasury), 1 ether);
    }

    function test_withdraw_unlocksOncePaused() public {
        vm.warp(saleStart);
        vm.prank(holder);
        presale.contribute{value: 10 ether}(address(0));

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
        presale.contribute{value: 1 ether}(address(0));

        vm.prank(owner);
        presale.unpause();
        vm.prank(holder);
        presale.contribute{value: 1 ether}(address(0)); // works again
    }

    // ---- views ----

    function test_previewTokensOut_matchesActualClamping() public {
        vm.warp(saleStart);
        assertEq(presale.previewTokensOut(holder, address(0), 1 ether), (1 ether * 1e18) / HOLDER_PRICE);
        assertEq(presale.previewTokensOut(nonHolder, address(0), 1 ether), (1 ether * 1e18) / PUBLIC_PRICE);
    }

    function test_previewTokensOut_isZeroWhilePaused() public {
        vm.warp(saleStart);
        vm.prank(owner);
        presale.pause();
        assertEq(presale.previewTokensOut(holder, address(0), 1 ether), 0);
    }

    function test_priceFor_reflectsHoldingsAndDelegation() public view {
        assertEq(presale.priceFor(holder, address(0)), HOLDER_PRICE);
        assertEq(presale.priceFor(nonHolder, address(0)), PUBLIC_PRICE);
    }

    function test_remainingWalletCap_decreasesAsContributed() public {
        vm.warp(saleStart);
        assertEq(presale.remainingWalletCap(holder), WALLET_CAP);
        vm.prank(holder);
        presale.contribute{value: 1 ether}(address(0));
        assertEq(presale.remainingWalletCap(holder), WALLET_CAP - presale.contributed(holder));
    }
}
