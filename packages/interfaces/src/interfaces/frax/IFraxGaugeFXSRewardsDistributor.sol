// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IFraxGaugeFXSRewardsDistributor {
    event DistributionsToggled(bool distibutions_state);
    event GaugeStateChanged(address gauge_address, bool is_middleman, bool is_active);
    event OwnerChanged(address oldOwner, address newOwner);
    event OwnerNominated(address newOwner);
    event RecoveredERC20(address token, uint256 amount);
    event RewardDistributed(address indexed gauge_address, uint256 reward_amount);

    function acceptOwnership() external;
    function distributeReward(address gauge_address) external returns (uint256 weeks_elapsed, uint256 reward_tally);
    function nominateNewOwner(address _owner) external;
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;
    function setCurator(address _new_curator_address) external;
    function setGaugeController(address _gauge_controller_address) external;
    function setGaugeState(address _gauge_address, bool _is_middleman, bool _is_active) external;
    function setTimelock(address _new_timelock) external;
    function toggleDistributions() external;
    function curator_address() external view returns (address);
    function currentReward(address gauge_address) external view returns (uint256 reward_amount);
    function distributionsOn() external view returns (bool);
    function gauge_whitelist(address) external view returns (bool);
    function is_middleman(address) external view returns (bool);
    function last_time_gauge_paid(address) external view returns (uint256);
    function nominatedOwner() external view returns (address);
    function owner() external view returns (address);
    function timelock_address() external view returns (address);
}
