/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Vault is ERC4626 {
    address public immutable REWARD_DISTRIBUTOR;

    constructor(address asset, address rewardDistributor)
        ERC4626(IERC20(asset))
        ERC20(
            string.concat("StakeDAO ", IERC20Metadata(asset).symbol(), " Vault"),
            string.concat("sd-", IERC20Metadata(asset).symbol(), "-vault")
        )
    {
        REWARD_DISTRIBUTOR = rewardDistributor;
    }
}
