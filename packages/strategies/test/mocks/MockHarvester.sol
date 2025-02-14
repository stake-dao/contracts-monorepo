// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IHarvester} from "src/interfaces/IHarvester.sol";

contract MockHarvester is IHarvester {
    ERC20Mock public immutable rewardToken;

    constructor(address rewardToken_) {
        rewardToken = ERC20Mock(rewardToken_);
    }

    function harvest(address, bytes memory harvestData)
        external
        override
        returns (uint256 feeSubjectAmount, uint256 feeExemptAmount)
    {
        (uint256 amount, uint256 randomSplit) = abi.decode(harvestData, (uint256, uint256));

        rewardToken.mint(address(this), amount);

        /// Calculate the fee subject amount.
        feeSubjectAmount = amount * randomSplit / 1e18;

        /// Calculate the fee exempt amount.
        feeExemptAmount = amount - feeSubjectAmount;

        return (feeSubjectAmount, feeExemptAmount);
    }
}
