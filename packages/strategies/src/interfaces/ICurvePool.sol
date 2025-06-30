// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface ICurveStableSwapPool {
    /// @dev Calculates the total value of all assets in the pool (using the StableSwap invariant)
    ///      and divides it by the total supply of LP tokens. The returned value is scaled up by 1e18.
    ///      The value is always denominated in the pool's "unit of account" (e.g., USD for a DAI/USDC/USDT pool).
    function get_virtual_price() external view returns (uint256);
    function name() external view returns (string memory);
}
