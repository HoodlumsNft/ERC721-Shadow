// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title GearModule1155
 * @notice Hoodlums: Blacknet — ERC-1155 Gear Modules (50 modules, tiers 1-50).
 *         Compiled from Data Shards via BlackMarketCompiler; see
 *         blacknet/docs/gear-modules.md for the module roster.
 *
 * Plain ERC-1155 (no creator-token/royalty machinery, unlike DataShard1155) —
 * gear isn't a primary-sale asset the way shard claims are; revisit if
 * secondary gear trading becomes a priority.
 *
 * ponytail: single trusted minter (the Compiler) rather than a role system —
 * add AccessControl if a second minter is ever needed.
 */
contract GearModule1155 is ERC1155, Ownable {
    using Strings for uint256;

    uint256 public constant MIN_MODULE = 1;
    uint256 public constant MAX_MODULE = 50;

    /// @notice Only this address (the BlackMarketCompiler) may mint.
    address public minter;

    string private _baseURI;

    event MinterUpdated(address indexed minter);

    error NotMinter();
    error InvalidModule(uint256 id);

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    constructor(address minter_, string memory baseURI_) ERC1155("") Ownable(msg.sender) {
        minter = minter_;
        _baseURI = baseURI_;
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts) external onlyMinter {
        for (uint256 i; i < ids.length; i++) {
            if (ids[i] < MIN_MODULE || ids[i] > MAX_MODULE) revert InvalidModule(ids[i]);
        }
        _mintBatch(to, ids, amounts, "");
    }

    // ---- admin ----

    function setMinter(address minter_) external onlyOwner {
        minter = minter_;
        emit MinterUpdated(minter_);
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseURI = baseURI_;
    }

    // ---- views ----

    function uri(uint256 id) public view override returns (string memory) {
        return string.concat(_baseURI, id.toString(), ".json");
    }
}
