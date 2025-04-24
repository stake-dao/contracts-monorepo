// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface ILocker {
    /// @notice Throws if caller is not the governance.
    error GOVERNANCE();

    /// @notice Throws if caller is not the governance or depositor.
    error GOVERNANCE_OR_DEPOSITOR();

    /// @notice Throws if caller is not the governance or depositor.
    error GOVERNANCE_OR_ACCUMULATOR();

    function createLock(uint256, uint256) external;

    function claimAllRewards(address[] calldata _tokens, address _recipient) external;

    function increaseAmount(uint256) external;

    function increaseAmount(uint128) external;

    function increaseUnlockTime(uint256) external;

    function release() external;

    function claimRewards(address, address) external;

    function claimRewards(address, address, address) external;

    function claimRewards(address _recipient, address[] calldata _pools) external;

    function claimFXSRewards(address) external;

    function claimFPISRewards(address) external;

    function execute(address, uint256, bytes calldata) external returns (bool, bytes memory);

    function setGovernance(address) external;

    function voteGaugeWeight(address, uint256) external;

    function setAngleDepositor(address) external;

    function setPendleDepositor(address) external;

    function pendleDepositor() external view returns (address);

    function setDepositor(address) external;

    function setFxsDepositor(address) external;

    function setYFIDepositor(address) external;

    function setYieldDistributor(address) external;

    function setGaugeController(address) external;

    function setAccumulator(address _accumulator) external;

    function governance() external view returns (address);

    function increaseLock(uint256 _value, uint256 _duration) external;

    function release(address _recipient) external;

    function transferGovernance(address _governance) external;

    function acceptGovernance() external;

    function setStrategy(address _strategy) external;
}
