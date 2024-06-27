// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IFeeSplitter} from "src/base/interfaces/IFeeSplitter.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ISDTDistributor} from "src/base/interfaces/ISDTDistributor.sol";

/// @title Accumulator
/// @notice Abstract contract used for any accumulator
/// @author StakeDAO
abstract contract Accumulator {
    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice sd gauge
    address public immutable gauge;

    /// @notice sd locker
    address public immutable locker;

    /// @notice governance
    address public governance;

    /// @notice future governance
    address public futureGovernance;

    /// @notice SDT distributor
    address public sdtDistributor;

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

    /// @notice fee splitter contract to pull strategies fees
    address public feeSplitter;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when the claimer fee is set
    event ClaimerFeeSet(uint256 claimerFee);

    /// @notice Event emitted when the dao fee is set
    event DaoFeeSet(uint256 daoFee);

    /// @notice Event emitted when the dao fee recipient is set
    event DaoFeeRecipientSet(address daoFeeRecipient);

    /// @notice Event emitted when the fees are charged during reward notify
    event FeeCharged(uint256 daoPart, uint256 liquidityPart, uint256 claimerPart);

    /// @notice Emitted when the fee splitter is set
    event FeeSplitterSet(address _feeSplitter);

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
    event GovernanceChanged(address governance);

    /// @notice Error emitted when an onlyGovernance function has called by a different address
    error GOVERNANCE();

    /// @notice Error emitted when the total fee would be more than 100%
    error FEE_TOO_HIGH();

    /// @notice Error emitted when an onlyFutureGovernance function has called by a different address
    error FUTURE_GOVERNANCE();

    /// @notice Error emitted when a zero address is pass
    error ZERO_ADDRESS();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Modifier to check if the caller is the governance
    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    /// @notice Modifier to check if the caller is the future governance
    modifier onlyFutureGovernance() {
        if (msg.sender != futureGovernance) revert FUTURE_GOVERNANCE();
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
    /// @param _governance governance
    constructor(
        address _gauge,
        address _locker,
        address _daoFeeRecipient,
        address _liquidityFeeRecipient,
        address _governance
    ) {
        gauge = _gauge;
        locker = _locker;
        daoFeeRecipient = _daoFeeRecipient;
        liquidityFeeRecipient = _liquidityFeeRecipient;

        governance = _governance;

        // default fees
        daoFee = 500; // 5%
        liquidityFee = 1_000; // 10%
        claimerFee = 50; // 0.5%
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll(bool _notifySDT, bool _pullFromFeeSplitter) external virtual {}

    /// @notice Claims a reward token for the locker and notify them to the LGV4
    function claimTokenAndNotifyAll(address _token, bool _notifySDT, bool _pullFromFeeSplitter) external virtual {}

    /// @notice Notify the whole acc balance of a token
    /// @param _token token to notify
    /// @param _notifySDT if notify SDT or not
    /// @param _pullFromFeeSplitter if pull tokens from the fee splitter or not
    function notifyReward(address _token, bool _notifySDT, bool _pullFromFeeSplitter) public virtual {
        uint256 amount = ERC20(_token).balanceOf(address(this));
        // notify token as reward in sdToken gauge
        _notifyReward(_token, amount, _pullFromFeeSplitter);

        if (_notifySDT) {
            // notify SDT
            _distributeSDT();
        }
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Notify the new reward to the LGV4
    /// @param _tokenReward token to notify
    /// @param _amount amount to notify
    function _notifyReward(address _tokenReward, uint256 _amount, bool _pullFromFeeSplitter) internal virtual {
        _chargeFee(_tokenReward, _amount);

        if (_pullFromFeeSplitter) {
            // Pull token reserved for acc from FeeSplitter if there is any
            IFeeSplitter(feeSplitter).split();

            address rewardToken = IFeeSplitter(feeSplitter).token();
            if (_tokenReward != rewardToken) {
                uint256 _rewardTokenAmount = ERC20(rewardToken).balanceOf(address(this));

                if (_rewardTokenAmount == 0) return;
                ILiquidityGauge(gauge).deposit_reward_token(rewardToken, _rewardTokenAmount);
            }
        }

        _amount = ERC20(_tokenReward).balanceOf(address(this));

        if (_amount == 0) return;
        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);

        emit RewardNotified(gauge, _tokenReward, _amount);
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
        if (_amount == 0) return 0;

        uint256 daoPart;
        uint256 liquidityPart;
        uint256 claimerPart;

        if (daoFee != 0) {
            daoPart = _amount * daoFee / DENOMINATOR;
            SafeTransferLib.safeTransfer(_token, daoFeeRecipient, daoPart);
            _charged += daoPart;
        }
        if (liquidityFee != 0) {
            liquidityPart = _amount * liquidityFee / DENOMINATOR;
            SafeTransferLib.safeTransfer(_token, liquidityFeeRecipient, liquidityPart);
            _charged += liquidityPart;
        }
        if (claimerFee != 0) {
            claimerPart = _amount * claimerFee / DENOMINATOR;
            SafeTransferLib.safeTransfer(_token, msg.sender, claimerPart);
            _charged += claimerPart;
        }
        emit FeeCharged(daoPart, liquidityPart, claimerPart);
    }

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Set SDT distributor.
    /// @param _distributor SDT distributor address.
    function setDistributor(address _distributor) external onlyGovernance {
        sdtDistributor = _distributor;
    }

    /// @notice Sets dao fee recipient
    /// @dev Can be called only by the governance
    /// @param _daoFeeRecipient dao fee recipient
    function setDaoFeeRecipient(address _daoFeeRecipient) external onlyGovernance {
        emit DaoFeeRecipientSet(daoFeeRecipient = _daoFeeRecipient);
    }

    /// @notice Sets liquidity fee recipient
    /// @dev Can be called only by the governance
    /// @param _liquidityFeeRecipient liquidity fee recipient
    function setLiquidityFeeRecipient(address _liquidityFeeRecipient) external onlyGovernance {
        emit LiquidityFeeRecipientSet(liquidityFeeRecipient = _liquidityFeeRecipient);
    }

    /// @notice Sets dao fee
    /// @dev Can be called only by the governance
    /// @param _daoFee dao fee in percentage (10_000 = 100%)
    function setDaoFee(uint256 _daoFee) external onlyGovernance {
        if (_daoFee + liquidityFee + claimerFee > DENOMINATOR) revert FEE_TOO_HIGH();
        emit DaoFeeSet(daoFee = _daoFee);
    }

    /// @notice Sets liquidity fee
    /// @dev Can be called only by the governance
    /// @param _liquidityFee liquidity fee in percentage (10_000 = 100%)
    function setLiquidityFee(uint256 _liquidityFee) external onlyGovernance {
        if (daoFee + _liquidityFee + claimerFee > DENOMINATOR) revert FEE_TOO_HIGH();
        emit LiquidityFeeSet(liquidityFee = _liquidityFee);
    }

    /// @notice Sets claimer fee
    /// @dev Can be called only by the governance
    /// @param _claimerFee claimer fee in percentage (10_000 = 100%)
    function setClaimerFee(uint256 _claimerFee) external onlyGovernance {
        if (daoFee + liquidityFee + _claimerFee > DENOMINATOR) revert FEE_TOO_HIGH();
        emit ClaimerFeeSet(claimerFee = _claimerFee);
    }

    /// @notice Set a fee splitter
    /// @param _feeSplitter fee splitter address
    function setFeeSplitter(address _feeSplitter) external onlyGovernance {
        emit FeeSplitterSet(feeSplitter = _feeSplitter);
    }

    /// @notice Set a new future governance that can accept it
    /// @dev Can be called only by the governance
    /// @param _futureGovernance future governance address
    function transferGovernance(address _futureGovernance) external onlyGovernance {
        if (_futureGovernance == address(0)) revert ZERO_ADDRESS();
        futureGovernance = _futureGovernance;
        emit TransferGovernance(_futureGovernance);
    }

    /// @notice Accept the governance
    /// @dev Can be called only by future governance
    function acceptGovernance() external onlyFutureGovernance {
        governance = futureGovernance;
        emit GovernanceChanged(governance);
    }

    /// @notice Approve the distribution of a new token reward from the Accumulator.
    /// @param _newTokenReward New token reward to be approved.
    function approveNewTokenReward(address _newTokenReward) external onlyGovernance {
        SafeTransferLib.safeApprove(_newTokenReward, gauge, type(uint256).max);
    }

    /// @notice A function that rescue any ERC20 token
    /// @dev Can be called only by the governance
    /// @param _token token address
    /// @param _amount amount to rescue
    /// @param _recipient address to send token rescued
    function rescueERC20(address _token, uint256 _amount, address _recipient) external onlyGovernance {
        if (_recipient == address(0)) revert ZERO_ADDRESS();
        SafeTransferLib.safeTransfer(_token, _recipient, _amount);
        emit ERC20Rescued(_token, _amount);
    }
}
