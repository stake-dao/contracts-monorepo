// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";

contract Redeem {
    address public token;
    address public sdToken;
    address public sdTokenGauge;

    error ZERO_AMOUNT();

    event RedeemedAmount(address user, uint256 amount);

    constructor(address _token, address _sdToken, address _sdTokenGauge) {
        token = _token;
        sdToken = _sdToken;
        sdTokenGauge = _sdTokenGauge;
    }

    function redeem() external {
        uint256 sdTokenBalance = ERC20(sdToken).balanceOf(msg.sender);
        if (sdTokenBalance > 0) {
            ERC20(sdToken).transferFrom(msg.sender, address(this), sdTokenBalance);
        }

        uint256 sdTokenGaugeBalance = ILiquidityGauge(sdTokenGauge).balanceOf(msg.sender);
        if (sdTokenGaugeBalance > 0) {
            ILiquidityGauge(sdTokenGauge).claim_rewards(msg.sender);
            ERC20(sdTokenGauge).transferFrom(msg.sender, address(this), sdTokenGaugeBalance);
            ILiquidityGauge(sdTokenGauge).withdraw(sdTokenGaugeBalance, false);
        }

        uint256 redeemAmount = ERC20(sdToken).balanceOf(address(this));
        if (redeemAmount == 0) revert ZERO_AMOUNT();
        ISdToken(sdToken).burn(address(this), redeemAmount);
        ERC20(token).transfer(msg.sender, redeemAmount);

        emit RedeemedAmount(msg.sender, redeemAmount);
    }
}
