# ERC721-Shadow

A minimal, gas-efficient smart contract standard for mirroring NFT ownership from a primary blockchain to secondary chains.

## Overview

ERC721-Shadow enables NFT collections to exist across multiple chains without the complexity and risk of traditional bridging mechanisms. The shadow contract maintains a read-only copy of ownership state, updated exclusively by an authorized oracle that watches events on the primary chain.

## Features

- Minimal gas consumption through optimized storage and batch operations
- Read-only ownership mirroring without transfer or approval logic
- Efficient bulk update mechanisms for oracle synchronization
- Packed data encoding supporting token IDs up to 2^96 - 1
- CREATE2 factory deployment for deterministic cross-chain addresses
- ERC721-compatible read functions for wallet and marketplace integration

## Architecture

The implementation consists of four core contracts:

- `IERC721Shadow` - Interface defining the standard
- `ERC721Shadow` - Standard implementation with Solidity optimizations
- `ERC721ShadowOptimized` - Assembly-optimized version for maximum gas efficiency
- `ERC721ShadowFactory` - Deployment factory with CREATE2 support
- `ShadowOracle` - Reference oracle implementation

## Installation

```bash
forge install
```

## Usage

### Deploying a Shadow Contract

```solidity
// Deploy factory
ERC721ShadowFactory factory = new ERC721ShadowFactory();

// Deploy shadow contract with deterministic address
bytes32 salt = keccak256("my-collection");
address shadow = factory.deployShadow(
    "My NFT Collection",
    "MNFT",
    "https://api.example.com/metadata/",
    oracleAddress,
    salt
);
```

### Mirroring Ownership

```solidity
// Single token update
shadow.mirrorOwnership(tokenId, newOwner);

// Bulk update
uint256[] memory tokenIds = new uint256[](3);
address[] memory owners = new address[](3);
// ... populate arrays
shadow.mirrorOwnershipBulk(tokenIds, owners, blockNumber);

// Packed update (most gas efficient)
uint256[] memory packed = new uint256[](3);
packed[0] = (tokenId << 160) | uint160(owner);
// ... populate array
shadow.mirrorOwnershipPacked(packed, blockNumber);
```

### Reading Ownership

```solidity
// Standard ERC721 read functions
address owner = shadow.ownerOf(tokenId);
uint256 balance = shadow.balanceOf(ownerAddress);
string memory uri = shadow.tokenURI(tokenId);
uint256 supply = shadow.totalSupply();
bool exists = shadow.exists(tokenId);
```

## Gas Benchmarks

Based on test results with 10 token batch updates:

| Operation | Standard | Optimized | Savings |
|-----------|----------|-----------|---------|
| Single Mirror | 78,546 gas | 76,873 gas | 2.1% |
| Bulk Mirror (10) | 309,838 gas | 309,101 gas | 0.2% |
| Packed Mirror (10) | 306,370 gas | 305,792 gas | 0.2% |

The packed encoding method provides the most gas-efficient bulk updates.

## Deployment

### Environment Setup

Create a `.env` file:

```bash
PRIVATE_KEY=your_private_key
ORACLE_ADDRESS=0x...
COLLECTION_NAME="My NFT Collection"
COLLECTION_SYMBOL="MNFT"
BASE_URI="https://api.example.com/metadata/"
MONAD_TESTNET_RPC_URL=https://...
```

### Deploy Standard Version

```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $MONAD_TESTNET_RPC_URL --broadcast
```

### Deploy Optimized Version

```bash
forge script script/Deploy.s.sol:DeployScript --sig "deployOptimized()" --rpc-url $MONAD_TESTNET_RPC_URL --broadcast
```

### Deploy with Oracle

```bash
forge script script/Deploy.s.sol:DeployScript --sig "deployWithOracle()" --rpc-url $MONAD_TESTNET_RPC_URL --broadcast
```

## Oracle Implementation

The oracle watches Transfer events on the primary chain and relays ownership updates to the shadow contract. A reference implementation is provided in `ShadowOracle.sol`.

### Oracle Responsibilities

1. Monitor Transfer events on primary chain contract
2. Aggregate ownership changes into batches
3. Submit batched updates at regular intervals
4. Track last processed block to prevent duplicates
5. Handle chain reorganizations

### Example Oracle Flow

```javascript
// Off-chain oracle pseudocode
const primaryContract = new ethers.Contract(PRIMARY_ADDRESS, ABI, provider);
const shadowContract = new ethers.Contract(SHADOW_ADDRESS, ABI, signer);

// Watch for Transfer events
primaryContract.on("Transfer", async (from, to, tokenId) => {
    // Aggregate into batch
    batch.push({ tokenId, owner: to });
    
    // Submit batch when size threshold reached
    if (batch.length >= BATCH_SIZE) {
        const tokenIds = batch.map(b => b.tokenId);
        const owners = batch.map(b => b.owner);
        const blockNumber = await provider.getBlockNumber();
        
        await shadowContract.mirrorOwnershipBulk(tokenIds, owners, blockNumber);
        batch = [];
    }
});
```

## Testing

Run the full test suite:

```bash
forge test -vv
```

Run with gas reporting:

```bash
forge test --gas-report
```

Run fuzz tests with extended runs:

```bash
forge test --fuzz-runs 10000
```

Generate coverage report:

```bash
forge coverage
```

## Security Considerations

1. **Oracle Key Management** - The oracle private key controls all ownership updates on the shadow chain. Use multi-signature or hardware wallet protection in production.

2. **State Divergence** - Shadow contract state can diverge from primary chain if oracle fails or is delayed. Implement monitoring and alerting.

3. **Read-Only Nature** - Shadow chain ownership is informational only. Users cannot transfer tokens on the shadow chain.

4. **Admin Functions** - Protect `setOracle` with timelock or multi-signature in production deployments.

5. **Block Reorganizations** - Oracle must handle chain reorgs on the primary chain to maintain accurate state.

## License

MIT

## Contributing

Contributions are welcome. Please ensure all tests pass and maintain test coverage above 90%.

## Contact

- Author: Diluk Angelo
- Twitter: https://x.com/cryptoangelodev
- Repository: https://github.com/HoodlumsNft/ERC721-Shadow
