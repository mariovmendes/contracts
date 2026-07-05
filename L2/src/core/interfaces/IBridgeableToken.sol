// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title IBridgeableToken Interface
 * @notice Interface for tokens that support bridge-controlled minting and burning.
 *
 * @author
 * SSV Labs
 */
interface IBridgeableToken {

    /// @notice Reverts if caller is not an authorized bridge contract.
    error Unauthorized();

    /// @notice Burns a specified amount of tokens from an account.
    /// @param account Address to burn from.
    /// @param value Amount to burn.
    function burn(address account, uint256 value) external;

    /// @notice Mints a specified amount of tokens to an account.
    /// @param account Address to mint to.
    /// @param value Amount to mint.
    function mint(address account, uint256 value) external;

    /// @notice Transfer a specified amount of tokens to an account.
    /// @param account Address to transfer to.
    /// @param value Amount to transfer.
    function transfer(address account, uint256 value) external returns (bool);
}
