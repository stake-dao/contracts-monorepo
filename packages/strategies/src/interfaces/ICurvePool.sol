// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ICurvePool {
    function name() external view returns (string memory);
    function decimals() external view returns (uint8);
    function coins(uint256 index) external view returns (address);
    function lp_token() external view returns (IERC20Metadata);
}

interface ICurveStableSwapPool is ICurvePool {
    /// @dev Calculates the total value of all assets in the pool (using the StableSwap invariant)
    ///      and divides it by the total supply of LP tokens. The returned value is scaled up by 1e18.
    ///      The value is always denominated in the pool's "unit of account" (e.g., USD for a DAI/USDC/USDT pool).
    function get_virtual_price() external view returns (uint256);
}

interface ICurveCryptoSwapPool is ICurvePool {
    function lp_price() external view returns (uint256);
}
