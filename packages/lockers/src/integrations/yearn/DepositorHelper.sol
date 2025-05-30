// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YearnDepositor} from "src/integrations/yearn/Depositor.sol";

/// @title DepositorHelper
/// @notice Helper contract to enable Yearn vesting factory
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract DepositorHelper {
    using SafeERC20 for IERC20;

    address public immutable token;
    address public immutable depositor;

    constructor(address _depositor, address _token) {
        depositor = _depositor;
        token = _token;
    }

    /// @notice deposits an amount of token into the depositor and send staked tokens to the sender
    /// @param _amount amount to be sent to the locker
    function deposit(uint256 _amount) external returns (uint256) {
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(token).approve(depositor, _amount);
        uint256 lockIncentive = YearnDepositor(depositor).incentiveToken();
        YearnDepositor(depositor).deposit(_amount, true, true, msg.sender);

        return _amount + lockIncentive;
    }
}
