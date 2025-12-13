/**
 * Shadow Oracle Service
 * 
 * Listens for Transfer events on the primary NFT contract (Monad)
 * and mirrors ownership updates to the shadow contract (ApeChain).
 */

import { ethers } from 'ethers';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

dotenv.config();

// Configuration
const config = {
  privateKey: process.env.PRIVATE_KEY,
  monadRpcUrl: process.env.MONAD_RPC_URL,
  apechainRpcUrl: process.env.APECHAIN_RPC_URL,
  primaryContract: process.env.PRIMARY_CONTRACT,
  shadowContract: process.env.SHADOW_CONTRACT,
  oracleContract: process.env.ORACLE_CONTRACT,
  batchSize: parseInt(process.env.BATCH_SIZE || '10'),
  batchIntervalMs: parseInt(process.env.BATCH_INTERVAL_MS || '30000'),
  startBlock: parseInt(process.env.START_BLOCK || '0'),
};

// Validate configuration
function validateConfig() {
  const required = ['privateKey', 'monadRpcUrl', 'apechainRpcUrl', 'primaryContract', 'shadowContract', 'oracleContract'];
  const missing = required.filter(key => !config[key]);
  
  if (missing.length > 0) {
    console.error('❌ Missing required configuration:', missing.join(', '));
    console.error('Please check your .env file');
    process.exit(1);
  }
}

// ERC721 Transfer event ABI
const ERC721_ABI = [
  'event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)',
  'function ownerOf(uint256 tokenId) view returns (address)',
  'function totalSupply() view returns (uint256)',
];

// ShadowOracle ABI
const SHADOW_ORACLE_ABI = [
  'function relayOwnershipBulk(uint256[] calldata tokenIds, address[] calldata newOwners, uint256 primaryBlockNumber) external',
  'function relayOwnershipPacked(uint256[] calldata packedData, uint256 primaryBlockNumber) external',
  'function lastProcessedBlock() view returns (uint256)',
  'function owner() view returns (address)',
  'function relayers(address) view returns (bool)',
];

// State file to persist processed block
const STATE_FILE = path.join(__dirname, '.oracle-state.json');

// Load persisted state
function loadState() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      const data = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
      return data;
    }
  } catch (e) {
    console.warn('⚠️ Could not load state file, starting fresh');
  }
  return { lastProcessedBlock: config.startBlock };
}

// Save state
function saveState(state) {
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

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

class ShadowOracle {
  constructor() {
    this.pendingUpdates = new Map(); // tokenId -> owner (latest owner wins)
    this.batchTimer = null;
    this.isProcessing = false;
    this.state = loadState();
  }

  async initialize() {
    console.log('🔮 Shadow Oracle Service');
    console.log('========================');
    console.log('');
    
    // Setup providers (auto-detect http vs websocket)
    this.monadProvider = createProvider(config.monadRpcUrl);
    this.apechainProvider = createProvider(config.apechainRpcUrl);
    
    // Setup wallet for ApeChain
    this.wallet = new ethers.Wallet(config.privateKey, this.apechainProvider);
    
    // Setup contracts
    this.primaryContract = new ethers.Contract(config.primaryContract, ERC721_ABI, this.monadProvider);
    this.oracleContract = new ethers.Contract(config.oracleContract, SHADOW_ORACLE_ABI, this.wallet);
    
    // Verify relayer authorization
    const isRelayer = await this.oracleContract.relayers(this.wallet.address);
    const oracleOwner = await this.oracleContract.owner();
    
    if (!isRelayer && this.wallet.address.toLowerCase() !== oracleOwner.toLowerCase()) {
      console.error('❌ Wallet is not authorized as a relayer on the ShadowOracle contract');
      console.error('   Wallet:', this.wallet.address);
      console.error('   Oracle Owner:', oracleOwner);
      process.exit(1);
    }
    
    // Get chain info
    const [monadNetwork, apechainNetwork] = await Promise.all([
      this.monadProvider.getNetwork(),
      this.apechainProvider.getNetwork(),
    ]);
    
    console.log('📡 Networks:');
    console.log(`   Monad (Primary): Chain ID ${monadNetwork.chainId}`);
    console.log(`   ApeChain (Shadow): Chain ID ${apechainNetwork.chainId}`);
    console.log('');
    console.log('📜 Contracts:');
    console.log(`   Primary (Monad): ${config.primaryContract}`);
    console.log(`   Shadow (ApeChain): ${config.shadowContract}`);
    console.log(`   Oracle (ApeChain): ${config.oracleContract}`);
    console.log('');
    console.log('🔑 Relayer:', this.wallet.address);
    console.log('');
    console.log('⚙️  Config:');
    console.log(`   Batch Size: ${config.batchSize}`);
    console.log(`   Batch Interval: ${config.batchIntervalMs}ms`);
    console.log(`   Last Processed Block: ${this.state.lastProcessedBlock}`);
    console.log('');
  }

  async start() {
    console.log('🚀 Starting oracle service...');
    console.log('');
    
    // Get current block
    const currentBlock = await this.monadProvider.getBlockNumber();
    console.log(`📦 Current Monad block: ${currentBlock}`);
    
    // Process historical events if needed
    if (this.state.lastProcessedBlock < currentBlock) {
      console.log(`📜 Processing historical events from block ${this.state.lastProcessedBlock} to ${currentBlock}...`);
      await this.processHistoricalEvents(this.state.lastProcessedBlock, currentBlock);
    }
    
    // Start listening for new events
    console.log('👂 Listening for Transfer events...');
    console.log('');
    
    this.primaryContract.on('Transfer', async (from, to, tokenId, event) => {
      await this.handleTransfer(from, to, tokenId, event);
    });
    
    // Start batch timer
    this.startBatchTimer();
    
    // Graceful shutdown
    process.on('SIGINT', () => this.shutdown());
    process.on('SIGTERM', () => this.shutdown());
  }

  async processHistoricalEvents(fromBlock, toBlock) {
    const CHUNK_SIZE = 500; // Monad RPC limits block range - keep small
    
    for (let start = fromBlock; start <= toBlock; start += CHUNK_SIZE) {
      const end = Math.min(start + CHUNK_SIZE - 1, toBlock);
      
      console.log(`   Fetching events from block ${start} to ${end}...`);
      
      const filter = this.primaryContract.filters.Transfer();
      const events = await this.primaryContract.queryFilter(filter, start, end);
      
      console.log(`   Found ${events.length} Transfer events`);
      
      for (const event of events) {
        const { from, to, tokenId } = event.args;
        this.queueUpdate(tokenId.toString(), to);
      }
      
      // Update state after each chunk
      this.state.lastProcessedBlock = end;
      saveState(this.state);
    }
    
    // Process any pending updates
    if (this.pendingUpdates.size > 0) {
      await this.processBatch();
    }
    
    console.log('✅ Historical sync complete');
    console.log('');
  }

  async handleTransfer(from, to, tokenId, event) {
    const block = event.log?.blockNumber || event.blockNumber;
    
    console.log(`📥 Transfer detected:`);
    console.log(`   Token ID: ${tokenId.toString()}`);
    console.log(`   From: ${from}`);
    console.log(`   To: ${to}`);
    console.log(`   Block: ${block}`);
    
    this.queueUpdate(tokenId.toString(), to);
    
    // Check if we should process immediately
    if (this.pendingUpdates.size >= config.batchSize) {
      await this.processBatch();
    }
  }

  queueUpdate(tokenId, owner) {
    // Latest owner for each token wins (handles multiple transfers in same batch)
    this.pendingUpdates.set(tokenId, owner);
    console.log(`   ➕ Queued update: Token ${tokenId} → ${owner} (${this.pendingUpdates.size} pending)`);
  }

  startBatchTimer() {
    this.batchTimer = setInterval(async () => {
      if (this.pendingUpdates.size > 0 && !this.isProcessing) {
        console.log('⏰ Batch interval reached, processing...');
        await this.processBatch();
      }
    }, config.batchIntervalMs);
  }

  async processBatch() {
    if (this.isProcessing || this.pendingUpdates.size === 0) {
      return;
    }
    
    this.isProcessing = true;
    
    try {
      // Get current block from Monad (for scanning progress)
      const currentBlock = await this.monadProvider.getBlockNumber();
      
      // Get last processed block from contract (for nonce/ordering)
      const contractLastBlock = await this.oracleContract.lastProcessedBlock();
      
      // Determine the block number to use for this batch
      // Must be strictly greater than contractLastBlock
      // And at least currentBlock (to match reality as close as possible)
      // If contract is ahead (due to sync-existing), we must skip ahead
      let relayBlock = BigInt(currentBlock);
      if (relayBlock <= contractLastBlock) {
        relayBlock = contractLastBlock + 1n;
        console.log(`   ⚠️ Adjusting block number for contract: ${currentBlock} -> ${relayBlock}`);
      }
      
      // Convert pending updates to arrays
      const updates = Array.from(this.pendingUpdates.entries());
      const tokenIds = updates.map(([tokenId]) => BigInt(tokenId));
      const owners = updates.map(([, owner]) => owner);
      
      console.log('');
      console.log(`📤 Relaying ${updates.length} ownership updates...`);
      console.log(`   Scanned up to Monad block: ${currentBlock}`);
      console.log(`   Relaying as block: ${relayBlock}`);
      
      // Use packed method for gas efficiency
      const packedData = updates.map(([tokenId, owner]) => packOwnership(tokenId, owner));
      
      // Estimate gas
      const gasEstimate = await this.oracleContract.relayOwnershipPacked.estimateGas(
        packedData,
        relayBlock
      );
      
      console.log(`   Estimated gas: ${gasEstimate.toString()}`);
      
      // Send transaction
      const tx = await this.oracleContract.relayOwnershipPacked(
        packedData,
        relayBlock,
        { gasLimit: gasEstimate * 120n / 100n } // 20% buffer
      );
      
      console.log(`   Transaction: ${tx.hash}`);
      
      // Wait for confirmation
      const receipt = await tx.wait();
      
      console.log(`   ✅ Confirmed in block ${receipt.blockNumber}`);
      console.log(`   Gas used: ${receipt.gasUsed.toString()}`);
      console.log('');
      
      // Clear processed updates
      this.pendingUpdates.clear();
      
      // Update state
      this.state.lastProcessedBlock = currentBlock;
      saveState(this.state);
      
    } catch (error) {
      console.error('❌ Error relaying updates:', error.message);
      
      // Handle specific errors
      if (error.message.includes('InvalidBlockNumber')) {
        console.error('   Block number already processed, clearing batch...');
        this.pendingUpdates.clear();
      }
    } finally {
      this.isProcessing = false;
    }
  }

  async shutdown() {
    console.log('');
    console.log('🛑 Shutting down oracle service...');
    
    // Clear timer
    if (this.batchTimer) {
      clearInterval(this.batchTimer);
    }
    
    // Process remaining updates
    if (this.pendingUpdates.size > 0) {
      console.log(`   Processing ${this.pendingUpdates.size} remaining updates...`);
      await this.processBatch();
    }
    
    // Save state
    saveState(this.state);
    
    console.log('   ✅ State saved');
    console.log('   Goodbye! 👋');
    process.exit(0);
  }
}

// Main entry point
async function main() {
  validateConfig();
  
  const oracle = new ShadowOracle();
  await oracle.initialize();
  await oracle.start();
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
