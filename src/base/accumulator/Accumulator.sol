// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ISDTDistributor} from "src/base/interfaces/ISDTDistributor.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @title Accumulator
/// @notice Abstract contract used for any accumulator
/// @author StakeDAO
abstract contract Accumulator {
    using SafeTransferLib for ERC20;

    /// @notice sd gauge
    address public gauge;

    /// @notice sd locker
    address public immutable locker;

    /// @notice SDT distributor
    address public sdtDistributor;

    /// @notice governance
    address public governance;

    /// @notice future governance
    address public futureGovernance;

    /// @notice dao fee in percentage (10_000 = 100%)
    uint256 public daoFee;

    /// @notice dao fee recipient address
    address public daoFeeRecipient;

    /// @notice liquidity fee in percentage (10_000 = 100%)
    uint256 public liquidityFee;

    /// @notice liquidity fee recipient
    address public liquidityFeeRecipient;

    /// @notice claimer fee (msg.sender) in percentage (10_000 = 100%)
    uint256 public claimerFee;

    /// @notice Denominator for fixed point math.
    uint256 public constant BASE_FEE = 10_000;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when the sd gauge is set
    event GaugeSet(address gauge);

    /// @notice Event emitted when the claimer fee is set
    event ClaimerFeeSet(uint256 claimerFee);

    /// @notice Event emitted when the dao fee is set
    event DaoFeeSet(uint256 daoFee);

    /// @notice Event emitted when the dao fee recipient is set
    event DaoFeeRecipientSet(address daoFeeRecipient);

    /// @notice Event emitted when an ERC20 token is rescued
    event ERC20Rescued(address token, uint256 amount);

    /// @notice Event emitted when the liquidity fee percentage is set
    event LiquidityFeeSet(uint256 liquidityFee);

    /// @notice Event emitted when a liquidity fee recipient  is set
    event LiquidityFeeRecipientSet(address liquidityFeeRecipient);

    /// @notice Event emitted when a new reward has notified
    event RewardNotified(address gauge, address tokenReward, uint256 amountNotified);

    /// @notice Event emitted when a new future governance has set
    event TransferGovernance(address futureGovernance);

    /// @notice Event emitted when the future governance accepts to be the governance
    event GovernanceAccepted(address governance);

    /// @notice Error emitted when an onlyGov function has called by a different address
    error GOV();

    /// @notice Error emitted when the total fee would be more than 100%
    error FEE_TOO_HIGH();

    /// @notice Error emitted when an onlyFutureGov function has called by a different address
    error FUTURE_GOV();

    /// @notice Error emitted when a zero address is pass
    error ZERO_ADDRESS();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Modifier to check if the caller is the governance
    modifier onlyGov() {
        if (msg.sender != governance) revert GOV();
        _;
    }

    /// @notice Modifier to check if the caller is the future governance
    modifier onlyFutureGov() {
        if (msg.sender != futureGovernance) revert FUTURE_GOV();
        _;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _daoFeeRecipient dao fee recipient
    /// @param _liquidityFeeRecipient liquidity fee recipient
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

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll() external virtual {}

    /// @notice Claims a single reward token for the locker and notify them to the LGV4
    function claimSingleTokenAndNotifyAll(address _token) external virtual {}

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

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
    /// @param _token token to approve to be spent by the gauge
    /// @param _amount amount to approve
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
    /// @param _token token to charge fee for
    /// @param _amount amount to charge fee for
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

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////

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
    /// @param _daoFeeRecipient dao fee recipient
    function setDaoFeeRecipient(address _daoFeeRecipient) external onlyGov {
        emit DaoFeeRecipientSet(daoFeeRecipient = _daoFeeRecipient);
    }

    /// @notice Sets liquidity fee recipient
    /// @dev Can be called only by the governance
    /// @param _liquidityFeeRecipient liquidity fee recipient
    function setLiquidityFeeRecipient(address _liquidityFeeRecipient) external onlyGov {
        emit LiquidityFeeRecipientSet(liquidityFeeRecipient = _liquidityFeeRecipient);
    }

    /// @notice Sets dao fee
    /// @dev Can be called only by the governance
    /// @param _daoFee dao fee in percentage (10_000 = 100%)
    function setDaoFee(uint256 _daoFee) external onlyGov {
        if (_daoFee + liquidityFee + claimerFee > BASE_FEE) revert FEE_TOO_HIGH();
        emit DaoFeeSet(daoFee = _daoFee);
    }

    /// @notice Sets liquidity fee
    /// @dev Can be called only by the governance
    /// @param _liquidityFee liquidity fee in percentage (10_000 = 100%)
    function setLiquidityFee(uint256 _liquidityFee) external onlyGov {
        if (daoFee + _liquidityFee + claimerFee > BASE_FEE) revert FEE_TOO_HIGH();
        emit LiquidityFeeSet(liquidityFee = _liquidityFee);
    }

    /// @notice Sets claimer fee
    /// @dev Can be called only by the governance
    /// @param _claimerFee claimer fee in percentage (10_000 = 100%)
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
}
