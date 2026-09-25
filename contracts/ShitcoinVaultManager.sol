// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ShitcoinVaultManager
/// @notice NEVM side of the Shitcoin UTXO<->NEVM bridge ("Shitbridge").
/// Deployed in genesis at 0x7904299b3D3dC1b03d1DdEb45E9fDF3576aCBd5f.
/// The UTXO chain validates TokenFreeze events emitted from this address to
/// mint UTXO assets (see CheckSyscoinMint in the UTXO node). The event
/// signature below MUST NOT change:
///   TokenFreeze(uint64,address,uint256,string)
contract ShitcoinVaultManager {
    /// @notice Asset GUID used for native SHIT on the UTXO side.
    /// Must be non-zero: the UTXO chain rejects guid 0 ("mint-missing-freeze-log").
    uint64 public constant NATIVE_SHIT_ASSET_GUID = 1;

    address public owner;

    /// @notice UTXO burn tx hashes already minted on NEVM. Prevents double-mint.
    mapping(bytes32 => bool) public spentBurns;

    /// @notice Exact event the UTXO chain parses. DO NOT change the signature.
    /// @param assetGuid UTXO asset GUID to mint (1 = native SHIT).
    /// @param freezer NEVM address that locked the funds.
    /// @param amount Satoshis of SHIT locked (18 decimals, like wei).
    /// @param syscoinAddress Destination UTXO address (string).
    event TokenFreeze(uint64 indexed assetGuid, address indexed freezer, uint256 amount, string syscoinAddress);

    event Mint(address indexed to, uint256 amount, bytes32 indexed burnTxHash);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice One-time owner setup (genesis alloc leaves owner at 0x0).
    function initialize(address initialOwner) external {
        require(owner == address(0), "already initialized");
        require(initialOwner != address(0), "zero owner");
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @notice Lock native SHIT to bridge it to the UTXO chain.
    /// Emits TokenFreeze; anyone may then submit the receipt proof to the
    /// UTXO chain to mint the corresponding UTXO asset.
    /// @param syscoinAddress Destination UTXO address (base58/bech32 string).
    function freeze(string calldata syscoinAddress) external payable {
        require(msg.value > 0, "nothing to freeze");
        require(bytes(syscoinAddress).length > 0 && bytes(syscoinAddress).length <= 128, "bad destination");
        emit TokenFreeze(NATIVE_SHIT_ASSET_GUID, msg.sender, msg.value, syscoinAddress);
    }

    /// @notice Mint NEVM SHIT for a verified UTXO burn (v1: owner-relayed).
    /// A trustless SPV relay can replace the owner check when ready.
    /// @param to NEVM address to credit.
    /// @param amount Satoshis of SHIT to release from the vault.
    /// @param burnTxHash UTXO burn tx hash (prevents double-mint).
    function mint(address to, uint256 amount, bytes32 burnTxHash) external {
        require(msg.sender == owner, "not owner");
        require(to != address(0), "zero address");
        require(amount > 0, "zero amount");
        require(!spentBurns[burnTxHash], "already minted");
        require(address(this).balance >= amount, "insufficient vault balance");
        spentBurns[burnTxHash] = true;
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "transfer failed");
        emit Mint(to, amount, burnTxHash);
    }

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "not owner");
        require(newOwner != address(0), "zero owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    receive() external payable {}
}
