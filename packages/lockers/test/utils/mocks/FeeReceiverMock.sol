// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract FeeReceiverMock {
    struct Repartition {
        address[] receivers;
        uint256[] fees; // Fee in basis points, where 10,000 basis points = 100%
    }

    address public governance;
    address public futureGovernance;

    uint256 private constant BASE_FEE = 10_000;

    mapping(address => Repartition) private rewardTokenRepartition;

    error GOVERNANCE();
    error FUTURE_GOVERNANCE();
    error ZERO_ADDRESS();
    error DISTRIBUTION_NOT_SET();
    error INVALID_FEE();
    error INVALID_REPARTITION();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    modifier onlyFutureGovernance() {
        if (msg.sender != futureGovernance) revert FUTURE_GOVERNANCE();
        _;
    }

    constructor(address _governance) {
        governance = _governance;
    }

    function getRepartition(address rewardToken)
        external
        view
        returns (address[] memory receivers, uint256[] memory fees)
    {
        Repartition memory repartition = rewardTokenRepartition[rewardToken];
        return (repartition.receivers, repartition.fees);
    }

    function split(address rewardToken) external {
        Repartition memory repartition = rewardTokenRepartition[rewardToken];
        uint256 length = repartition.receivers.length;
        if (length == 0) revert DISTRIBUTION_NOT_SET();

        uint256 totalBalance = ERC20(rewardToken).balanceOf(address(this));
        if (totalBalance == 0) return;

        for (uint256 i = 0; i < length; i++) {
            uint256 fee = totalBalance * repartition.fees[i] / BASE_FEE;
            SafeTransferLib.safeTransfer(rewardToken, repartition.receivers[i], fee);
        }
    }

    function transferGovernance(address _futureGovernance) external onlyGovernance {
        if (_futureGovernance == address(0)) revert ZERO_ADDRESS();
        futureGovernance = _futureGovernance;
    }

    function acceptGovernance() external onlyFutureGovernance {
        governance = futureGovernance;
        futureGovernance = address(0);
    }

    function setRepartition(address rewardToken, address[] calldata receivers, uint256[] calldata fees)
        external
        onlyGovernance
    {
        if (rewardToken == address(0)) revert ZERO_ADDRESS();
        if (receivers.length == 0 || receivers.length != fees.length) revert INVALID_REPARTITION();

        uint256 totalFee = 0;
        for (uint256 i = 0; i < fees.length; i++) {
            totalFee += fees[i];
        }
        if (totalFee != BASE_FEE) revert INVALID_FEE();

        rewardTokenRepartition[rewardToken] = Repartition(receivers, fees);
    }
}
