// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface IFeeReceiver {
    struct Repartition {
        address[] receivers;
        uint256[] fees; // Fee in basis points, where 10,000 basis points = 100%
    }

    function governance() external view returns (address);
    function futureGovernance() external view returns (address);
    function acceptGovernance() external;
    function transferGovernance(address _futureGovernance) external;

    function getRepartition(address rewardToken)
        external
        view
        returns (address[] memory receivers, uint256[] memory fees);
    function setRepartition(address rewardToken, address[] calldata receivers, uint256[] calldata fees) external;

    function split(address rewardToken) external;
}
