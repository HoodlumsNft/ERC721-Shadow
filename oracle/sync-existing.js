/**
 * Sync Existing Ownership
 * 
 * Fetches all current token ownership from the primary contract (Monad)
 * and syncs it to the shadow contract (ApeChain).
 * 
 * Use this for initial setup or to resync state.
 */

import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

// Configuration
const config = {
  privateKey: process.env.PRIVATE_KEY,
  monadRpcUrl: process.env.MONAD_RPC_URL,
  apechainRpcUrl: process.env.APECHAIN_RPC_URL,
  primaryContract: process.env.PRIMARY_CONTRACT,
  oracleContract: process.env.ORACLE_CONTRACT,
  tokenIdStart: parseInt(process.env.TOKEN_ID_START || '0'),
};

// ERC721 ABI
const ERC721_ABI = [
  'event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)',
  'function ownerOf(uint256 tokenId) view returns (address)',
  'function totalSupply() view returns (uint256)',
  'function balanceOf(address owner) view returns (uint256)',
];

// ShadowOracle ABI
const SHADOW_ORACLE_ABI = [
  'function relayOwnershipBulk(uint256[] calldata tokenIds, address[] calldata newOwners, uint256 primaryBlockNumber) external',
  'function relayOwnershipPacked(uint256[] calldata packedData, uint256 primaryBlockNumber) external',
  'function lastProcessedBlock() view returns (uint256)',
];

// Create provider based on URL protocol (http/https or ws/wss)
function createProvider(url) {
  if (url.startsWith('ws://') || url.startsWith('wss://')) {
    return new ethers.WebSocketProvider(url);
  }
  return new ethers.JsonRpcProvider(url);
}

// Pack tokenId and owner into single uint256
function packOwnership(tokenId, owner) {
  const tokenIdBigInt = BigInt(tokenId);
  const ownerBigInt = BigInt(owner);
  return (tokenIdBigInt << 160n) | ownerBigInt;
}

async function main() {
  console.log('🔄 Sync Existing Ownership');
  console.log('==========================');
  console.log('');

  // Setup providers (auto-detect http vs websocket)
  const monadProvider = createProvider(config.monadRpcUrl);
  const apechainProvider = createProvider(config.apechainRpcUrl);
  
  // Setup wallet for ApeChain
  const wallet = new ethers.Wallet(config.privateKey, apechainProvider);
  
  // Setup contracts
  const primaryContract = new ethers.Contract(config.primaryContract, ERC721_ABI, monadProvider);
  const oracleContract = new ethers.Contract(config.oracleContract, SHADOW_ORACLE_ABI, wallet);
  
  console.log('📜 Primary Contract:', config.primaryContract);
  console.log('🔮 Oracle Contract:', config.oracleContract);
  console.log('🔑 Relayer:', wallet.address);
  console.log('');

  // Get current block
  const currentBlock = await monadProvider.getBlockNumber();
  console.log(`📦 Current Monad block: ${currentBlock}`);
  
  // Try to get total supply
  let totalSupply;
  try {
    totalSupply = await primaryContract.totalSupply();
    console.log(`📊 Total Supply: ${totalSupply.toString()}`);
  } catch (e) {
    console.log('⚠️ Could not get totalSupply, will scan Transfer events instead');
    totalSupply = null;
  }
  console.log('');

  // Method 1: If we have totalSupply, query each token
  if (totalSupply !== null && totalSupply > 0) {
    await syncByTokenId(primaryContract, oracleContract, totalSupply, currentBlock);
  } else {
    // Method 2: Scan Transfer events to find all tokens
    await syncByEvents(primaryContract, oracleContract, monadProvider, currentBlock);
  }
  
  console.log('');
  console.log('✅ Sync complete!');
}

async function syncByTokenId(primaryContract, oracleContract, totalSupply, currentBlock) {
  console.log('📋 Syncing by token ID...');
  console.log(`   Token ID range: ${config.tokenIdStart} to ${Number(totalSupply) - 1 + config.tokenIdStart}`);
  console.log('');
  
  const BATCH_SIZE = 50;
  const ownership = [];
  
  // Calculate the end token ID based on totalSupply and start index
  const startId = config.tokenIdStart;
  const endId = Number(totalSupply) - 1 + config.tokenIdStart;
  
  // Query ownership for each token
  for (let tokenId = startId; tokenId <= endId; tokenId++) {
    try {
      const owner = await primaryContract.ownerOf(tokenId);
      ownership.push({ tokenId, owner });
      
      const progress = tokenId - startId + 1;
      const total = endId - startId + 1;
      if (progress % 100 === 0) {
        console.log(`   Queried ${progress}/${total} tokens...`);
      }
    } catch (e) {
      // Token might not exist (burned) or non-sequential IDs
      console.log(`   ⚠️ Token ${tokenId} not found, skipping`);
    }
  }
  
  console.log(`   Found ${ownership.length} tokens with owners`);
  console.log('');
  
  // Relay in batches
  await relayInBatches(oracleContract, ownership, currentBlock, BATCH_SIZE);
}

async function syncByEvents(primaryContract, oracleContract, provider, currentBlock) {
  console.log('📋 Syncing by Transfer events...');
  console.log('');
  
  const BATCH_SIZE = 50;
  const CHUNK_SIZE = 500; // Monad RPC limits block range
  
  // Get contract deployment block (approximate - use 0 for full scan)
  const fromBlock = 0;
  
  // Track final owners
  const ownershipMap = new Map(); // tokenId -> owner
  
  // Scan all Transfer events
  for (let start = fromBlock; start <= currentBlock; start += CHUNK_SIZE) {
    const end = Math.min(start + CHUNK_SIZE - 1, currentBlock);
    
    console.log(`   Scanning blocks ${start} to ${end}...`);
    
    const filter = primaryContract.filters.Transfer();
    const events = await primaryContract.queryFilter(filter, start, end);
    
    console.log(`   Found ${events.length} Transfer events`);
    
    for (const event of events) {
      const { from, to, tokenId } = event.args;
      
      // Skip burns (transfer to 0x0)
      if (to === ethers.ZeroAddress) {
        ownershipMap.delete(tokenId.toString());
      } else {
        ownershipMap.set(tokenId.toString(), to);
      }
    }
  }
  
  console.log('');
  console.log(`   Total tokens: ${ownershipMap.size}`);
  
  // Convert to array
  const ownership = Array.from(ownershipMap.entries()).map(([tokenId, owner]) => ({
    tokenId: parseInt(tokenId),
    owner,
  }));
  
  // Relay in batches
  await relayInBatches(oracleContract, ownership, currentBlock + 1, BATCH_SIZE);
}

async function relayInBatches(oracleContract, ownership, blockNumber, batchSize) {
  console.log(`📤 Relaying ${ownership.length} ownership records in batches of ${batchSize}...`);
  console.log('');
  
  for (let i = 0; i < ownership.length; i += batchSize) {
    const batch = ownership.slice(i, i + batchSize);
    const packedData = batch.map(({ tokenId, owner }) => packOwnership(tokenId, owner));
    
    // Increment block number for each batch to satisfy oracle validation
    const batchBlockNumber = blockNumber + Math.floor(i / batchSize);
    
    console.log(`   Batch ${Math.floor(i / batchSize) + 1}/${Math.ceil(ownership.length / batchSize)}: ${batch.length} tokens`);
    
    try {
      const tx = await oracleContract.relayOwnershipPacked(packedData, batchBlockNumber);
      console.log(`   Transaction: ${tx.hash}`);
      
      const receipt = await tx.wait();
      console.log(`   ✅ Confirmed in block ${receipt.blockNumber} (gas: ${receipt.gasUsed})`);
    } catch (error) {
      console.error(`   ❌ Error: ${error.message}`);
      
      if (error.message.includes('InvalidBlockNumber')) {
        console.log('   ⚠️ Block number already processed, continuing...');
      } else {
        throw error;
      }
    }
  }
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
