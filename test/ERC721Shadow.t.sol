// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/ERC721Shadow.sol";
import "../contracts/ERC721ShadowOptimized.sol";
import "../contracts/ERC721ShadowFactory.sol";
import "../contracts/ShadowOracle.sol";

contract ERC721ShadowTest is Test {
    ERC721Shadow public shadow;
    ERC721ShadowOptimized public shadowOptimized;
    ERC721ShadowFactory public factory;
    ShadowOracle public oracle;
    
    address public owner = address(this);
    address public oracleAddress = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);
    
    string constant NAME = "Test NFT";
    string constant SYMBOL = "TNFT";
    string constant BASE_URI = "https://example.com/metadata/";
    
    event OwnershipMirrored(
        uint256 indexed tokenId,
        address indexed previousOwner,
        address indexed newOwner
    );
    
    event BulkOwnershipMirrored(uint256 count, uint256 blockNumber);
    
    function setUp() public {
        shadow = new ERC721Shadow(NAME, SYMBOL, BASE_URI, oracleAddress);
        shadowOptimized = new ERC721ShadowOptimized(NAME, SYMBOL, BASE_URI, oracleAddress);
        factory = new ERC721ShadowFactory();
    }
    
    function testDeployment() public {
        assertEq(shadow.name(), NAME);
        assertEq(shadow.symbol(), SYMBOL);
        assertEq(shadow.baseURI(), BASE_URI);
        assertEq(shadow.oracle(), oracleAddress);
        assertEq(shadow.totalSupply(), 0);
    }
    
    function testCannotDeployWithZeroOracle() public {
        vm.expectRevert(IERC721Shadow.ZeroAddress.selector);
        new ERC721Shadow(NAME, SYMBOL, BASE_URI, address(0));
    }
    
    function testMirrorOwnership() public {
        vm.prank(oracleAddress);
        vm.expectEmit(true, true, true, true);
        emit OwnershipMirrored(1, address(0), user1);
        shadow.mirrorOwnership(1, user1);
        
        assertEq(shadow.ownerOf(1), user1);
        assertEq(shadow.balanceOf(user1), 1);
        assertEq(shadow.totalSupply(), 1);
        assertTrue(shadow.exists(1));
    }
    
    function testCannotMirrorOwnershipAsNonOracle() public {
        vm.prank(user1);
        vm.expectRevert(IERC721Shadow.NotOracle.selector);
        shadow.mirrorOwnership(1, user1);
    }
    
    function testCannotMirrorToZeroAddress() public {
        vm.prank(oracleAddress);
        vm.expectRevert(IERC721Shadow.ZeroAddress.selector);
        shadow.mirrorOwnership(1, address(0));
    }
    
    function testMirrorOwnershipTransfer() public {
        vm.startPrank(oracleAddress);
        shadow.mirrorOwnership(1, user1);
        
        vm.expectEmit(true, true, true, true);
        emit OwnershipMirrored(1, user1, user2);
        shadow.mirrorOwnership(1, user2);
        vm.stopPrank();
        
        assertEq(shadow.ownerOf(1), user2);
        assertEq(shadow.balanceOf(user1), 0);
        assertEq(shadow.balanceOf(user2), 1);
        assertEq(shadow.totalSupply(), 1);
    }
    
    function testMirrorOwnershipBulk() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;
        
        address[] memory owners = new address[](3);
        owners[0] = user1;
        owners[1] = user2;
        owners[2] = user3;
        
        vm.prank(oracleAddress);
        vm.expectEmit(true, false, false, true);
        emit BulkOwnershipMirrored(3, 100);
        shadow.mirrorOwnershipBulk(tokenIds, owners, 100);
        
        assertEq(shadow.ownerOf(1), user1);
        assertEq(shadow.ownerOf(2), user2);
        assertEq(shadow.ownerOf(3), user3);
        assertEq(shadow.balanceOf(user1), 1);
        assertEq(shadow.balanceOf(user2), 1);
        assertEq(shadow.balanceOf(user3), 1);
        assertEq(shadow.totalSupply(), 3);
    }
    
    function testCannotMirrorBulkWithMismatchedArrays() public {
        uint256[] memory tokenIds = new uint256[](2);
        address[] memory owners = new address[](3);
        
        vm.prank(oracleAddress);
        vm.expectRevert(IERC721Shadow.ArrayLengthMismatch.selector);
        shadow.mirrorOwnershipBulk(tokenIds, owners, 100);
    }
    
    function testMirrorOwnershipPacked() public {
        uint256[] memory packedData = new uint256[](3);
        packedData[0] = (uint256(1) << 160) | uint160(user1);
        packedData[1] = (uint256(2) << 160) | uint160(user2);
        packedData[2] = (uint256(3) << 160) | uint160(user3);
        
        vm.prank(oracleAddress);
        shadow.mirrorOwnershipPacked(packedData, 100);
        
        assertEq(shadow.ownerOf(1), user1);
        assertEq(shadow.ownerOf(2), user2);
        assertEq(shadow.ownerOf(3), user3);
        assertEq(shadow.totalSupply(), 3);
    }
    
    function testTokenURI() public {
        vm.prank(oracleAddress);
        shadow.mirrorOwnership(123, user1);
        
        string memory uri = shadow.tokenURI(123);
        assertEq(uri, "https://example.com/metadata/123");
    }
    
    function testCannotGetTokenURIForNonExistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Shadow.TokenNotMinted.selector, 999));
        shadow.tokenURI(999);
    }
    
    function testCannotGetOwnerOfNonExistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Shadow.TokenNotMinted.selector, 999));
        shadow.ownerOf(999);
    }
    
    function testCannotGetBalanceOfZeroAddress() public {
        vm.expectRevert(IERC721Shadow.ZeroAddress.selector);
        shadow.balanceOf(address(0));
    }
    
    function testSetOracle() public {
        address newOracle = address(0x5);
        shadow.setOracle(newOracle);
        assertEq(shadow.oracle(), newOracle);
    }
    
    function testCannotSetOracleToZeroAddress() public {
        vm.expectRevert(IERC721Shadow.ZeroAddress.selector);
        shadow.setOracle(address(0));
    }
    
    function testCannotSetOracleAsNonOwner() public {
        vm.prank(user1);
        vm.expectRevert("Not owner");
        shadow.setOracle(address(0x5));
    }
    
    function testFactoryDeployShadow() public {
        bytes32 salt = keccak256("test");
        address deployed = factory.deployShadow(NAME, SYMBOL, BASE_URI, oracleAddress, salt);
        
        ERC721Shadow deployedShadow = ERC721Shadow(deployed);
        assertEq(deployedShadow.name(), NAME);
        assertEq(deployedShadow.symbol(), SYMBOL);
        assertEq(deployedShadow.oracle(), oracleAddress);
    }
    
    function testFactoryDeployShadowOptimized() public {
        bytes32 salt = keccak256("test");
        address deployed = factory.deployShadowOptimized(NAME, SYMBOL, BASE_URI, oracleAddress, salt);
        
        ERC721ShadowOptimized deployedShadow = ERC721ShadowOptimized(deployed);
        assertEq(deployedShadow.name(), NAME);
        assertEq(deployedShadow.symbol(), SYMBOL);
        assertEq(deployedShadow.oracle(), oracleAddress);
    }
    
    function testOracleContract() public {
        oracle = new ShadowOracle(address(shadow));
        shadow.setOracle(address(oracle));
        
        assertEq(oracle.shadowContract(), address(shadow));
        assertEq(oracle.owner(), address(this));
        assertTrue(oracle.relayers(address(this)));
    }
    
    function testOracleRelayBulk() public {
        oracle = new ShadowOracle(address(shadow));
        shadow.setOracle(address(oracle));
        
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        
        address[] memory owners = new address[](2);
        owners[0] = user1;
        owners[1] = user2;
        
        oracle.relayOwnershipBulk(tokenIds, owners, 100);
        
        assertEq(shadow.ownerOf(1), user1);
        assertEq(shadow.ownerOf(2), user2);
        assertEq(oracle.lastProcessedBlock(), 100);
    }
    
    function testOracleRelayPacked() public {
        oracle = new ShadowOracle(address(shadow));
        shadow.setOracle(address(oracle));
        
        uint256[] memory packedData = new uint256[](2);
        packedData[0] = (uint256(1) << 160) | uint160(user1);
        packedData[1] = (uint256(2) << 160) | uint160(user2);
        
        oracle.relayOwnershipPacked(packedData, 100);
        
        assertEq(shadow.ownerOf(1), user1);
        assertEq(shadow.ownerOf(2), user2);
    }
    
    function testOraclePackUnpack() public {
        oracle = new ShadowOracle(address(shadow));
        
        uint256 packed = oracle.packOwnership(123, user1);
        (uint256 tokenId, address owner) = oracle.unpackOwnership(packed);
        
        assertEq(tokenId, 123);
        assertEq(owner, user1);
    }
    
    function testOracleAddRemoveRelayer() public {
        oracle = new ShadowOracle(address(shadow));
        
        oracle.addRelayer(user1);
        assertTrue(oracle.relayers(user1));
        
        oracle.removeRelayer(user1);
        assertFalse(oracle.relayers(user1));
    }
    
    function testOptimizedMatchesStandard() public {
        vm.startPrank(oracleAddress);
        
        shadow.mirrorOwnership(1, user1);
        shadowOptimized.mirrorOwnership(1, user1);
        
        assertEq(shadow.ownerOf(1), shadowOptimized.ownerOf(1));
        assertEq(shadow.balanceOf(user1), shadowOptimized.balanceOf(user1));
        assertEq(shadow.totalSupply(), shadowOptimized.totalSupply());
        
        shadow.mirrorOwnership(1, user2);
        shadowOptimized.mirrorOwnership(1, user2);
        
        assertEq(shadow.ownerOf(1), shadowOptimized.ownerOf(1));
        assertEq(shadow.balanceOf(user1), shadowOptimized.balanceOf(user1));
        assertEq(shadow.balanceOf(user2), shadowOptimized.balanceOf(user2));
        
        vm.stopPrank();
    }
    
    function testFuzzMirrorOwnership(uint256 tokenId, address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(tokenId < type(uint96).max);
        
        vm.prank(oracleAddress);
        shadow.mirrorOwnership(tokenId, newOwner);
        
        assertEq(shadow.ownerOf(tokenId), newOwner);
        assertEq(shadow.balanceOf(newOwner), 1);
    }
    
    function testFuzzPackedEncoding(uint96 tokenId, address owner) public {
        vm.assume(owner != address(0));
        
        oracle = new ShadowOracle(address(shadow));
        uint256 packed = oracle.packOwnership(uint256(tokenId), owner);
        (uint256 decodedTokenId, address decodedOwner) = oracle.unpackOwnership(packed);
        
        assertEq(decodedTokenId, uint256(tokenId));
        assertEq(decodedOwner, owner);
    }
    
    function testGasMirrorOwnershipSingle() public {
        vm.prank(oracleAddress);
        uint256 gasBefore = gasleft();
        shadow.mirrorOwnership(1, user1);
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas used for single mirror (standard)", gasUsed);
        
        vm.prank(oracleAddress);
        gasBefore = gasleft();
        shadowOptimized.mirrorOwnership(2, user1);
        gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas used for single mirror (optimized)", gasUsed);
    }
    
    function testGasMirrorOwnershipBulk() public {
        uint256[] memory tokenIds = new uint256[](10);
        address[] memory owners = new address[](10);
        
        for (uint256 i = 0; i < 10; i++) {
            tokenIds[i] = i + 1;
            owners[i] = user1;
        }
        
        vm.prank(oracleAddress);
        uint256 gasBefore = gasleft();
        shadow.mirrorOwnershipBulk(tokenIds, owners, 100);
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas used for bulk mirror 10 tokens (standard)", gasUsed);
        
        vm.prank(oracleAddress);
        gasBefore = gasleft();
        shadowOptimized.mirrorOwnershipBulk(tokenIds, owners, 100);
        gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas used for bulk mirror 10 tokens (optimized)", gasUsed);
    }
    
    function testGasMirrorOwnershipPacked() public {
        uint256[] memory packedData = new uint256[](10);
        
        for (uint256 i = 0; i < 10; i++) {
            packedData[i] = ((i + 1) << 160) | uint160(user1);
        }
        
        vm.prank(oracleAddress);
        uint256 gasBefore = gasleft();
        shadow.mirrorOwnershipPacked(packedData, 100);
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas used for packed mirror 10 tokens (standard)", gasUsed);
        
        vm.prank(oracleAddress);
        gasBefore = gasleft();
        shadowOptimized.mirrorOwnershipPacked(packedData, 100);
        gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas used for packed mirror 10 tokens (optimized)", gasUsed);
    }
}
