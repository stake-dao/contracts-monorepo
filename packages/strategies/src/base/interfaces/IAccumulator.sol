// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IAccumulator {
    function claimerFee() external view returns (uint256);

    function depositToken(address _token, uint256 _amount) external;

    function governance() external view returns (address);

    function notifyAllExtraReward(address _token) external;

    function setGauge(address _gauge) external;
}
