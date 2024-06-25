// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/accumulator/AccumulatorV2.sol";
import {IStrategy} from "herdaddy/interfaces/IStrategy.sol";

/// @title A contract that accumulates 3crv rewards and notifies them to the LGV4
/// @author StakeDAO
contract CRVAccumulatorV2 is AccumulatorV2 {
    address public constant CRV3 = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice Curve strategy address
    IStrategy public immutable strategy = IStrategy(0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd);

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when a token not supported is used
    error WRONG_TOKEN();

    ////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////////////

    constructor(address _gauge, address _locker, address _governance) AccumulatorV2(_gauge, _locker, _governance) {
        SafeTransferLib.safeApprove(CRV, gauge, type(uint256).max);
        SafeTransferLib.safeApprove(CRV3, gauge, type(uint256).max);
    }

    ////////////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    ////////////////////////////////////////////////////////////

    function claimAndNotifyAll(bool notifySDT, bool pullFromFeeReceiver, bool claimFeeStrategy) external override {
        // Claim 3CRV rewards
        strategy.claimNativeRewards();
        uint256 crv3Amount = ERC20(CRV3).balanceOf(address(this));
        uint256 crvAmount = ERC20(CRV).balanceOf(address(this));

        // Sending strategy fees to fee receiver
        if (claimFeeStrategy) {
            _claimFeeStrategy(address(strategy));
        }

        // Notify 3CRV and CRV rewards
        _notifyReward(CRV3, crv3Amount, false);
        _notifyReward(CRV, crvAmount, pullFromFeeReceiver);

        if (notifySDT) {
            _distributeSDT();
        }
    }

    /// @notice Claims 3CRV or CRV rewards for the locker and notify all to the LGV4
    function claimTokenAndNotifyAll(address token, bool notifySDT, bool pullFromFeeReceiver, bool claimFeeStrategy)
        external
        override
    {
        if (token != CRV3 && token != CRV) revert WRONG_TOKEN();

        if (token == CRV3) {
            // claim 3CRV reward
            strategy.claimNativeRewards();
        }

        uint256 amount = ERC20(token).balanceOf(address(this));

        // Sending strategy fees to fee receiver
        if (claimFeeStrategy) {
            _claimFeeStrategy(address(strategy));
        }

        // notify 3CRV or CRV as reward in sdCRV gauge
        _notifyReward(token, amount, pullFromFeeReceiver);

        if (notifySDT) {
            // notify SDT
            _distributeSDT();
        }
    }
}
