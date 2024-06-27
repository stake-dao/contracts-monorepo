// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IVeFPISYieldDistributorV5 {
    event DefaultInitialization();
    event OldYieldCollected(address indexed user, uint256 yield, address token_address);
    event OwnerChanged(address oldOwner, address newOwner);
    event OwnerNominated(address newOwner);
    event RecoveredERC20(address token, uint256 amount);
    event RewardAdded(uint256 reward, uint256 yieldRate);
    event YieldCollected(address indexed user, uint256 yield, address token_address);
    event YieldDurationUpdated(uint256 newDuration);
    event YieldPeriodRenewed(address token, uint256 yieldRate);

    function acceptOwnership() external;
    function checkpoint() external;
    function checkpointOtherUser(address user_addr) external;
    function getYield() external returns (uint256 yield0);
    function greylistAddress(address _address) external;
    function nominateNewOwner(address _owner) external;
    function notifyRewardAmount(uint256 amount) external;
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;
    function setPauses(bool _yieldCollectionPaused) external;
    function setTimelock(address _new_timelock) external;
    function setYieldDuration(uint256 _yieldDuration) external;
    function setYieldRate(uint256 _new_rate0, bool sync_too) external;
    function sync() external;
    function toggleRewardNotifier(address notifier_addr) external;
    function earned(address account) external view returns (uint256);
    function eligibleCurrentVeFPIS(address account)
        external
        view
        returns (uint256 eligible_vefpis_bal, uint256 stored_ending_timestamp);
    function emittedToken() external view returns (address);
    function emitted_token_address() external view returns (address);
    function fractionParticipating() external view returns (uint256);
    function getYieldForDuration() external view returns (uint256);
    function greylist(address) external view returns (bool);
    function lastTimeYieldApplicable() external view returns (uint256);
    function lastUpdateTime() external view returns (uint256);
    function nominatedOwner() external view returns (address);
    function owner() external view returns (address);
    function periodFinish() external view returns (uint256);
    function reward_notifiers(address) external view returns (bool);
    function timelock_address() external view returns (address);
    function totalVeFPISParticipating() external view returns (uint256);
    function totalVeFPISSupplyStored() external view returns (uint256);
    function userIsInitialized(address) external view returns (bool);
    function userVeFPISCheckpointed(address) external view returns (uint256);
    function userVeFPISEndpointCheckpointed(address) external view returns (uint256);
    function userYieldPerTokenPaid(address) external view returns (uint256);
    function yieldCollectionPaused() external view returns (bool);
    function yieldDuration() external view returns (uint256);
    function yieldPerVeFPIS() external view returns (uint256);
    function yieldPerVeFPISStored() external view returns (uint256);
    function yieldRate() external view returns (uint256);
    function yields(address) external view returns (uint256);
}
