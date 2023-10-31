// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "src/base/accumulator/BaseAccumulator.sol";
import "src/base/interfaces/IYearnStrategy.sol";

/// @title A contract that accumulates YFI rewards and notifies them to the LGV4
/// @author StakeDAO
contract YearnAccumulatorV2 is BaseAccumulator {

    IYearnStrategy public strategy;
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    event StrategySet(address oldS, address newS);

    /* ========== CONSTRUCTOR ========== */
    constructor(address _tokenReward, address _gauge, address _strategy) BaseAccumulator(_tokenReward, _gauge) {
        strategy = IYearnStrategy(_strategy);
        locker = strategy.locker();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /// @notice Claims YFI rewards for the locker and notify an amount to the LGV4
    /// @param _amount amount to notify after the claim
    function claimAndNotify(uint256 _amount) external {
        require(locker != address(0), "locker not set");
        ILocker(locker).claimRewards(tokenReward, address(this));
        _notifyReward(tokenReward, _amount);
        _distributeSDT();
    }

    /// @notice Claims YFI rewards for the locker and notify all to the LGV4
    function claimAndNotifyAll() external {
        require(locker != address(0), "locker not set");
        ILocker(locker).claimRewards(tokenReward, address(this));
        uint256 amount = IERC20(tokenReward).balanceOf(address(this));
        _notifyReward(tokenReward, amount);
        _distributeSDT();
    }

    /// @notice Claims DYFI rewards for the locker and notify all to the LGV4
    function claimAndNotifyAllDyfi() external {
        require(locker != address(0), "locker not set");
        strategy.claimDYfiRewardPool();
        uint256 amount = IERC20(DYFI).balanceOf(address(this));
        _notifyReward(DYFI, amount);
        _distributeSDT();
    }

    /// @notice Sets the strategy to claim the DYFI reward
    /// @dev Can be called only by the governance
    /// @param _strategy strategy address
    function setStrategy(address _strategy) external {
        require(msg.sender == governance, "!gov");
        require(_strategy != address(0), "can't be zero address");
        emit StrategySet(address(strategy), _strategy);
        strategy = IYearnStrategy(_strategy);
    }
}
