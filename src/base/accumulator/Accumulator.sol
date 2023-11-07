// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ISDTDistributor} from "src/base/interfaces/ISDTDistributor.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @title A contract that accumulates YFI and dYFI rewards and notifies them to the LGV4
/// @author StakeDAO
abstract contract Accumulator {
    using SafeTransferLib for ERC20;

    error GOV();
    error FEE_TOO_HIGH();
    error FUTURE_GOV();
    error ZERO_ADDRESS();

    address public gauge;
    address public immutable locker;
    address public sdtDistributor;
    address public governance;
    address public futureGovernance;

    // fee
    uint256 public daoFee;
    address public daoFeeRecipient;
    uint256 public liquidityFee;
    address public liquidityFeeRecipient;
    uint256 public claimerFee;

    uint256 public constant BASE_FEE = 10_000;

    event GaugeSet(address gauge);
    event ClaimerFeeSet(uint256 claimerFee);
    event DaoFeeSet(uint256 daoFee);
    event DaoFeeRecipientSet(address daoFeeRecipient);
    event ERC20Rescued(address token, uint256 amount);
    event LiquidityFeeSet(uint256 liquidityFee);
    event LiquidityFeeRecipientSet(address liquidityFeeRecipient);
    event RewardNotified(address gauge, address tokenReward, uint256 amountNotified);
    event TransferGovernance(address futureGovernance);
    event GovernanceAccepted(address governance);

    modifier onlyGov() {
        if (msg.sender != governance) revert GOV();
        _;
    }

    modifier onlyFutureGov() {
        if (msg.sender != futureGovernance) revert FUTURE_GOV();
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    constructor(address _gauge, address _locker, address _daoFeeRecipient, address _liquidityFeeRecipient) {
        gauge = _gauge;
        locker = _locker;
        daoFeeRecipient = _daoFeeRecipient;
        liquidityFeeRecipient = _liquidityFeeRecipient;

        governance = msg.sender;

        // default fees
        daoFee = 500; // 5%
        liquidityFee = 1_000; // 10%
        claimerFee = 50; // 0.5%
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll() external virtual {}

    /// @notice Claims a single reward token for the locker and notify them to the LGV4
    function claimSingleTokenAndNotifyAll(address _token) external virtual {}

    /// @notice A function that rescue any ERC20 token
    /// @dev Can be called only by the governance
    /// @param _token token address
    /// @param _amount amount to rescue
    /// @param _recipient address to send token rescued
    function rescueERC20(address _token, uint256 _amount, address _recipient) external onlyGov {
        if (_recipient == address(0)) revert ZERO_ADDRESS();
        SafeTransferLib.safeTransfer(_token, _recipient, _amount);
        //ERC20(_token).safeTransfer(_recipient, _amount);
        emit ERC20Rescued(_token, _amount);
    }

    /// @notice Sets gauge for the accumulator which will receive and distribute the rewards
    /// @dev Can be called only by the governance
    /// @param _gauge gauge address
    function setGauge(address _gauge) external onlyGov {
        if (_gauge == address(0)) revert ZERO_ADDRESS();
        gauge = _gauge;
        emit GaugeSet(gauge);
    }

    /// @notice Sets dao fee recipient
    /// @dev Can be called only by the governance
    function setDaoFeeRecipient(address _daoFeeRecipient) external onlyGov {
        emit DaoFeeRecipientSet(daoFeeRecipient = _daoFeeRecipient);
    }

    /// @notice Sets liquidity fee recipient
    /// @dev Can be called only by the governance
    function setLiquidityFeeRecipient(address _liquidityFeeRecipient) external onlyGov {
        emit LiquidityFeeRecipientSet(liquidityFeeRecipient = _liquidityFeeRecipient);
    }

    /// @notice Sets dao fee
    /// @dev Can be called only by the governance
    function setDaoFee(uint256 _daoFee) external onlyGov {
        if (_daoFee + liquidityFee + claimerFee > BASE_FEE) revert FEE_TOO_HIGH();
        emit DaoFeeSet(daoFee = _daoFee);
    }

    /// @notice Sets liquidity fee
    /// @dev Can be called only by the governance
    function setLiquidityFee(uint256 _liquidityFee) external onlyGov {
        if (daoFee + _liquidityFee + claimerFee > BASE_FEE) revert FEE_TOO_HIGH();
        emit LiquidityFeeSet(liquidityFee = _liquidityFee);
    }

    /// @notice Sets claimer fee
    /// @dev Can be called only by the governance
    function setClaimerFee(uint256 _claimerFee) external onlyGov {
        if (daoFee + liquidityFee + _claimerFee > BASE_FEE) revert FEE_TOO_HIGH();
        emit ClaimerFeeSet(claimerFee = _claimerFee);
    }

    /// @notice Set a new future governance that can accept it
    /// @dev Can be called only by the governance
    /// @param _futureGovernance future governance address
    function transferGovernance(address _futureGovernance) external onlyGov {
        if (_futureGovernance == address(0)) revert ZERO_ADDRESS();
        futureGovernance = _futureGovernance;
        emit TransferGovernance(_futureGovernance);
    }

    /// @notice Accept the governance
    /// @dev Can be called only by future governance
    function acceptGovernance() external onlyFutureGov {
        governance = futureGovernance;
        emit GovernanceAccepted(governance);
    }

    /// @notice Notify the new reward to the LGV4
    /// @param _tokenReward token to notify
    /// @param _amount amount to notify
    function _notifyReward(address _tokenReward, uint256 _amount) internal virtual {
        if (_amount == 0) {
            return;
        }
        if (ILiquidityGauge(gauge).reward_data(_tokenReward).distributor == address(this)) {
            _approveTokenIfNeeded(_tokenReward, _amount);
            ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);

            emit RewardNotified(gauge, _tokenReward, _amount);
        }
    }

    /// @notice Do a max approve if the allowance is not enough
    function _approveTokenIfNeeded(address _token, uint256 _amount) internal {
        if (ERC20(_token).allowance(_token, gauge) < _amount) {
            SafeTransferLib.safeApprove(_token, gauge, type(uint256).max);
        }
    }

    /// @notice Distribute SDT to the gauge
    function _distributeSDT() internal {
        if (sdtDistributor != address(0)) {
            ISDTDistributor(sdtDistributor).distribute(gauge);
        }
    }

    /// @notice Charge fee for dao, liquidity, claimer
    function _chargeFee(address _token, uint256 _amount) internal returns (uint256 _charged) {
        if (daoFee != 0) {
            uint256 daoPart = _amount * daoFee / BASE_FEE;
            SafeTransferLib.safeTransfer(_token, daoFeeRecipient, daoPart);
            _charged += daoPart;
        }
        if (liquidityFee != 0) {
            uint256 liquidityPart = _amount * liquidityFee / BASE_FEE;
            SafeTransferLib.safeTransfer(_token, liquidityFeeRecipient, liquidityPart);
            _charged += liquidityPart;
        }
        if (claimerFee != 0) {
            uint256 claimerPart = _amount * liquidityFee / BASE_FEE;
            SafeTransferLib.safeTransfer(_token, msg.sender, claimerPart);
            _charged += claimerPart;
        }
    }
}
