// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Maverick Locker
/// @author StakeDAO
contract Locker {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */
    address public governance;
    address public depositor;
    address public accumulator;
    address public rewardPool;

    address public immutable token;
    address public immutable veToken;

    /* ========== EVENTS ========== */
    event LockCreated(address indexed user, uint256 value, uint256 duration);
    event TokenClaimed(address indexed user, uint256 value);
    event VotedOnGaugeWeight(address indexed _gauge, uint256 _weight);
    event Released(address indexed user, uint256 value);
    event GovernanceChanged(address indexed newGovernance);
    event YFIDepositorChanged(address indexed newYearnDepositor);
    event AccumulatorChanged(address indexed newAccumulator);
    event RewardPoolChanged(address indexed newRewardPool);

    /* ========== CONSTRUCTOR ========== */
    constructor(address _governance, address _accumulator, address _token, address _veToken, address _rewardPool) {
        governance = _governance;
        accumulator = _accumulator;
        token = _token;
        veToken = _veToken;
        rewardPool = _rewardPool;
    }

    /* ========== MODIFIERS ========== */
    modifier onlyGovernance() {
        require(msg.sender == governance, "!gov");
        _;
    }

    modifier onlyGovernanceOrAcc() {
        require(msg.sender == governance || msg.sender == accumulator, "!(gov||acc)");
        _;
    }

    modifier onlyGovernanceOrDepositor() {
        require(msg.sender == governance || msg.sender == depositor, "!(gov||YearnDepositor)");
        _;
    }

    /// @notice execute a function
    /// @param to Address to sent the value to
    /// @param value Value to be sent
    /// @param data Call function data
    function execute(address to, uint256 value, bytes calldata data)
        external
        onlyGovernance
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }
}
