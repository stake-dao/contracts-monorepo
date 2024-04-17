// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {ILocker} from "src/base/interfaces/ILocker.sol";
import {SafeExecute} from "src/base/libraries/SafeExecute.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ISDTDistributor} from "src/base/interfaces/ISDTDistributor.sol";

/// @notice Main access point of the locker.
/// @dev Is Upgradable.
abstract contract Strategy is UUPSUpgradeable {
    using SafeExecute for ILocker;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Address of the locker contract.
    ILocker public immutable locker;

    /// @notice Address of the Voting Escrow contract.
    address public immutable veToken;

    /// @notice Address of the token being rewarded.
    address public immutable rewardToken;

    /// @notice Address of the rewardToken Minter.
    /// @dev Eg. CRV Minter.
    address public immutable minter;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance contract.
    address public futureGovernance;

    /// @notice Interface for Stake DAO token Accumulator
    address public accumulator;

    /// @notice Curve DAO token Fee Distributor
    address public feeDistributor;

    /// @notice Reward Token for veToken holders.
    address public feeRewardToken;

    /// @notice Stake DAO SDT Distributor
    address public SDTDistributor;

    /// @notice Address of the factory.
    address public factory;

    /// @notice Address accruing protocol fees.
    address public feeReceiver;

    /// @notice Percentage of fees charged on `rewardToken` claimed.
    uint256 public protocolFeesPercent;

    /// @notice Amount of fees charged on `rewardToken` claimed
    uint256 public feesAccrued;

    /// @notice Percentage of fees charged on `rewardToken` claimed to incentivize claimers.
    uint256 public claimIncentiveFee;

    /// @notice Map vaults address -> is vault active
    mapping(address => bool) public vaults;

    /// @notice Map `_asset_`to corresponding liquidity gauge.
    mapping(address => address) public gauges;

    /// @notice Map liquidity gauge address -> gauge type (0,1,2,3).
    mapping(address => uint256) public lGaugeType;

    /// @notice Map native liquidity gauge to Stake DAO Reward Distributor.
    mapping(address => address) public rewardDistributors;

    /// @notice Map addresses allowed to interact with the `execute` function.
    mapping(address => bool) public allowed;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when governance is changed.
    /// @param newGovernance Address of the new governance.
    event GovernanceChanged(address indexed newGovernance);

    /// @notice Error emitted when input address is null
    error ADDRESS_NULL();

    /// @notice Error emitted when low level call failed
    error LOW_LEVEL_CALL_FAILED();

    /// @notice Error emitted when sum of fees is above 100%
    error FEE_TOO_HIGH();

    /// @notice Error emitted when auth failed
    error GOVERNANCE();

    /// @notice Error emitted when auth failed
    error UNAUTHORIZED();

    /// @notice Error emitted when auth failed
    error GOVERNANCE_OR_FACTORY();

    /// @notice Error emitted when trying to allow an EOA.
    error NOT_CONTRACT();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor(address owner, address _locker, address _veToken, address _rewardToken, address _minter) {
        governance = owner;

        minter = _minter;
        veToken = _veToken;
        locker = ILocker(_locker);
        rewardToken = _rewardToken;
    }

    /// @notice Initialize the strategy.
    /// @param owner Address of the owner.
    /// @dev The implementation should not be initalized since the constructor already define the governance.
    function initialize(address owner) external virtual {
        if (governance != address(0)) revert GOVERNANCE();
        governance = owner;

        /// Initialize the SDT Distributor.
        SDTDistributor = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C;
    }

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    modifier onlyVault() {
        if (!vaults[msg.sender]) revert UNAUTHORIZED();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    modifier onlyGovernanceOrAllowed() {
        if (msg.sender != governance && !allowed[msg.sender]) revert UNAUTHORIZED();
        _;
    }

    modifier onlyGovernanceOrFactory() {
        if (msg.sender != governance && msg.sender != factory) revert GOVERNANCE_OR_FACTORY();
        _;
    }

    //////////////////////////////////////////////////////
    /// --- DEPOSIT / WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////

    /// @notice Deposit LP token.
    /// @param asset Address of LP token to deposit.
    /// @param amount Amount of LP token to deposit.
    /// @dev Only callable by approved vaults.
    function deposit(address asset, uint256 amount) external onlyVault {
        // Transfer the token to this contract.
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(this), amount);

        /// Deposit the token in the locker.
        _deposit(asset, amount);
    }

    /// @notice Withdraw LP token.
    /// @param asset Address of LP token to withdraw.
    /// @param amount Amount of LP token to withdraw.
    /// @dev Only callable by approved vaults.
    function withdraw(address asset, uint256 amount) external onlyVault {
        /// Withdraw from the locker.
        _withdraw(asset, amount);

        /// Transfer the token to the vault.
        SafeTransferLib.safeTransfer(asset, msg.sender, amount);
    }

    //////////////////////////////////////////////////////
    /// --- LOCKER FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Deposit into the gauge trhoug the Locker.
    /// @param asset Address of LP token to deposit.
    /// @param gauge Address of Liqudity gauge corresponding to LP token.
    /// @param amount Amount of LP token to deposit.
    function _depositIntoLocker(address asset, address gauge, uint256 amount) internal virtual {
        /// Transfer the LP token to the Locker.
        SafeTransferLib.safeTransfer(asset, address(locker), amount);

        /// Deposit into the Gauge trough the Locker.
        locker.execute(gauge, 0, abi.encodeWithSignature("deposit(uint256)", amount));
    }

    /// @notice Withdraw from the gauge trhoug the Locker.
    /// @param asset Address of LP token to withdraw.
    /// @param gauge Address of Liqudity gauge corresponding to LP token.
    /// @param amount Amount of LP token to withdraw.
    function _withdrawFromLocker(address asset, address gauge, uint256 amount) internal virtual {
        /// Withdraw from the Gauge trough the Locker.
        locker.execute(gauge, 0, abi.encodeWithSignature("withdraw(uint256)", amount));

        /// Transfer the _asset_ from the Locker to this contract.
        _transferFromLocker(asset, address(this), amount);
    }

    //////////////////////////////////////////////////////
    /// --- CLAIM & DISTRIBUTION LOGIC
    //////////////////////////////////////////////////////

    /// @notice Claim `FeeRewardToken` from the Fee Distributor and send it to the Accumulator contract.
    function claimNativeRewards() external {
        /// Claim from the Fee Distributor.
        _claimNativeRewards();
    }

    /// @notice Harvest rewards from the gauge trhoug the Locker.
    /// @param asset Address of LP token to harvest.
    /// @param distributeSDT Boolean indicating if SDT should be distributed to the rewarDistributor.
    /// @dev distributeSDT Should be called only if the rewardDistributor is valid to receive SDT inflation.
    /// @param claimExtra Boolean indicating if extra rewards should be claimed from the Locker.
    function harvest(address asset, bool distributeSDT, bool claimExtra) public virtual {
        /// If the _asset is valid, it should be mapped to a gauge.
        address gauge = gauges[asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Cache the rewardDistributor address.
        address rewardDistributor = rewardDistributors[gauge];

        /// 1. Claim `rewardToken` from the Gauge.
        uint256 claimed = _claimRewardToken(gauge);

        /// 2. Distribute SDT
        // Distribute SDT to the related gauge
        if (distributeSDT) {
            ISDTDistributor(SDTDistributor).distribute(rewardDistributor);
        }

        /// 3. Check for additional rewards from the Locker.
        /// If there's the `rewardToken` as extra reward, we add it to the `_claimed` amount in order to distribute it only
        /// once.
        if (claimExtra) {
            claimed += _claimExtraRewards(gauge, rewardDistributor);
        }

        /// 4. Take Fees from _claimed amount.
        claimed -= (_chargeProtocolFees(claimed) + _distributeClaimIncentive(claimed));

        /// 5. Distribute the rewardToken.
        ILiquidityGauge(rewardDistributor).deposit_reward_token(rewardToken, claimed);
    }

    //////////////////////////////////////////////////////
    /// --- PROTOCOL FEES ACCOUNTING
    //////////////////////////////////////////////////////

    /// @notice Claim protocol fees and send them to the fee receiver.
    function claimProtocolFees() external {
        if (feesAccrued == 0) return;
        if (feeReceiver == address(0)) revert ADDRESS_NULL();

        uint256 _feesAccrued = feesAccrued;
        feesAccrued = 0;

        SafeTransferLib.safeTransfer(rewardToken, feeReceiver, _feesAccrued);
    }

    /// @notice Internal function to charge protocol fees from `rewardToken` claimed by the locker.
    /// @return _amount Amount left after charging protocol fees.
    function _chargeProtocolFees(uint256 amount) internal returns (uint256) {
        if (amount == 0 || protocolFeesPercent == 0) return 0;

        uint256 _feeAccrued = amount.mulDiv(protocolFeesPercent, DENOMINATOR);
        feesAccrued += _feeAccrued;

        return _feeAccrued;
    }

    /// @notice Distribute claim incentive to the claimer to incentivize claiming.
    /// @return _amount Amount left after distributing claim incentive.
    function _distributeClaimIncentive(uint256 amount) internal returns (uint256) {
        if (amount == 0 || claimIncentiveFee == 0) return 0;

        uint256 claimerIncentive = amount.mulDiv(claimIncentiveFee, DENOMINATOR);

        SafeTransferLib.safeTransfer(rewardToken, msg.sender, claimerIncentive);

        return claimerIncentive;
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL DEPOSIT / WITHDRAWAL IMPLEMENTATIONS
    //////////////////////////////////////////////////////

    /// @notice Deposit LP token.
    /// @param asset Address of LP token to deposit.
    /// @param amount Amount of LP token to deposit.
    function _deposit(address asset, uint256 amount) internal virtual {
        address gauge = gauges[asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        _depositIntoLocker(asset, gauge, amount);
    }

    /// @notice Withdraw LP token.
    /// @param token Address of LP token to withdraw.
    /// @param amount Amount of LP token to withdraw.
    function _withdraw(address token, uint256 amount) internal virtual {
        address gauge = gauges[token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        _withdrawFromLocker(token, gauge, amount);
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL CLAIM IMPLEMENTATIONS
    //////////////////////////////////////////////////////

    /// @notice Internal implementation of native reward claim compatible with FeeDistributor.vy like contracts.
    function _claimNativeRewards() internal virtual {
        locker.execute(feeDistributor, 0, abi.encodeWithSignature("claim()"));

        /// Check if there is something to send.
        uint256 _claimed = ERC20(feeRewardToken).balanceOf(address(locker));
        if (_claimed == 0) return;

        /// Transfer the rewards to the Accumulator contract.
        _transferFromLocker(feeRewardToken, accumulator, _claimed);
    }

    /// @notice Claim `rewardToken` allocated for a gauge.
    /// @param gauge Address of the liquidity gauge to claim for.
    function _claimRewardToken(address gauge) internal virtual returns (uint256 _claimed) {
        /// Snapshot before claim.
        uint256 _snapshotBalance = ERC20(rewardToken).balanceOf(address(locker));

        /// Claim.
        locker.execute(minter, 0, abi.encodeWithSignature("mint(address)", gauge));

        /// Snapshot after claim.
        _claimed = ERC20(rewardToken).balanceOf(address(locker)) - _snapshotBalance;

        /// Transfer the claimed amount to this contract.
        _transferFromLocker(rewardToken, address(this), _claimed);
    }

    /// @notice Claim extra rewards from the locker.
    /// @param gauge Address of the liquidity gauge to claim from.
    /// @param rewardDistributor Address of the reward distributor to distribute the extra rewards to.
    /// @return _rewardTokenClaimed Amount of `rewardToken` claimed.
    /// @dev If `rewardToken` is an extra reward, it will be added to the `_rewardTokenClaimed` amount to avoid double distribution.
    function _claimExtraRewards(address gauge, address rewardDistributor)
        internal
        virtual
        returns (uint256 _rewardTokenClaimed)
    {
        /// If the gauge doesn't support extra rewards, skip.
        if (lGaugeType[gauge] > 0) return 0;

        // Cache the reward tokens and their balance before locker
        address[8] memory extraRewardTokens;
        uint256[8] memory snapshotLockerRewardBalances;

        uint8 i;
        address extraRewardToken;
        /// There can be up to 8 extra reward tokens.
        for (i; i < 8;) {
            /// Get extra reward token address.
            extraRewardToken = ILiquidityGauge(gauge).reward_tokens(i);
            if (extraRewardToken == address(0)) break;

            // Add the reward token address on the array
            extraRewardTokens[i] = extraRewardToken;
            // Add the reward token balance ot the locker on the array
            snapshotLockerRewardBalances[i] = ERC20(extraRewardToken).balanceOf(address(locker));

            unchecked {
                ++i;
            }
        }

        /// There's two ways to claim extra rewards:
        /// 1. Call claim_rewards on the gauge with the strategy as receiver.
        /// 2. Call claim_rewards on the gauge with the locker as receiver, then transfer the rewards from the locker to the strategy.
        /// 1 is not supported by all gauges, so we try to call it first, and if it fails, we fallback to 2.
        (bool isRewardReceived,) = locker.execute(
            gauge, 0, abi.encodeWithSignature("claim_rewards(address,address)", address(locker), address(this))
        );

        if (!isRewardReceived) {
            ILiquidityGauge(gauge).claim_rewards(address(locker));
        }

        for (i = 0; i < 8;) {
            extraRewardToken = extraRewardTokens[i];
            if (extraRewardToken == address(0)) break;
            uint256 claimed;
            if (!isRewardReceived) {
                claimed = ERC20(extraRewardToken).balanceOf(address(locker)) - snapshotLockerRewardBalances[i];
                if (claimed != 0) {
                    // Transfer the freshly rewards from the locker to this contract.
                    _transferFromLocker(extraRewardToken, address(this), claimed);
                }
            }

            if (extraRewardToken == rewardToken) {
                _rewardTokenClaimed += claimed;
            } else {
                claimed = ERC20(extraRewardToken).balanceOf(address(this));
                if (claimed != 0) {
                    // Distribute the extra reward token.
                    ILiquidityGauge(rewardDistributor).deposit_reward_token(extraRewardToken, claimed);
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    function balanceOf(address asset) public view virtual returns (uint256) {
        // Get the gauge address
        address gauge = gauges[asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        return ILiquidityGauge(gauge).balanceOf(address(locker));
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL HELPER FUNCTIONS
    //////////////////////////////////////////////////////

    function _transferFromLocker(address asset, address recipient, uint256 amount) internal virtual {
        locker.safeExecute(asset, 0, abi.encodeWithSignature("transfer(address,uint256)", recipient, amount));
    }

    //////////////////////////////////////////////////////
    /// --- MIGRATION LOGIC
    //////////////////////////////////////////////////////

    /// @notice If we ever decide to migrate the strategy, we can use this function to migrate the LP token.
    /// @dev Only callable by the vault.
    /// @param asset Address of LP token to migrate.
    /// @dev Built only to support the old implementation of the vault, but it will be killed.
    function migrateLP(address asset) public virtual onlyVault {
        // Get gauge address
        address gauge = gauges[asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Get the amount of LP token staked in the gauge by the locker
        uint256 amount = ERC20(gauge).balanceOf(address(locker));

        // Locker withdraw all from the gauge
        locker.safeExecute(gauge, 0, abi.encodeWithSignature("withdraw(uint256)", amount));

        // Locker transfer the LP token to the vault
        _transferFromLocker(asset, msg.sender, amount);
    }

    //////////////////////////////////////////////////////
    /// --- FACTORY STRATEGY SETTERS
    //////////////////////////////////////////////////////

    /// @notice Toogle vault status
    /// @param vault Address of the vault to toggle
    function toggleVault(address vault) external onlyGovernanceOrFactory {
        if (vault == address(0)) revert ADDRESS_NULL();
        vaults[vault] = !vaults[vault];
    }

    /// @notice Set gauge address for a LP token
    /// @param token Address of LP token corresponding to `gauge`
    /// @param gauge Address of liquidity gauge corresponding to `token`
    function setGauge(address token, address gauge) external virtual onlyGovernanceOrFactory {
        if (token == address(0)) revert ADDRESS_NULL();
        if (gauge == address(0)) revert ADDRESS_NULL();

        gauges[token] = gauge;

        /// Approve trough the locker.
        locker.safeExecute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, 0));
        locker.safeExecute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, type(uint256).max));
    }

    /// @notice Set type for a Liquidity gauge
    /// @param gauge Address of Liquidity gauge
    /// @param gaugeType Type of Liquidity gauge
    function setLGtype(address gauge, uint256 gaugeType) external onlyGovernanceOrFactory {
        if (gauge == address(0)) revert ADDRESS_NULL();
        lGaugeType[gauge] = gaugeType;
    }

    /// @notice Set rewardDistributor for a Liquidity gauge
    /// @param gauge Address of Liquidity gauge
    /// @param rewardDistributor Address of rewardDistributor
    function setRewardDistributor(address gauge, address rewardDistributor) external onlyGovernanceOrFactory {
        if (gauge == address(0) || rewardDistributor == address(0)) revert ADDRESS_NULL();
        rewardDistributors[gauge] = rewardDistributor;

        /// Approve the rewardDistributor to spend token.
        SafeTransferLib.safeApproveWithRetry(rewardToken, rewardDistributor, type(uint256).max);
    }

    /// @notice Accept Reward Distrbutor Ownership.
    /// @dev Gauge need to call this function to accept ownership of the rewardDistributor because ownership is transfered in two steps.
    /// @param rewardDistributor Address of rewardDistributor.
    function acceptRewardDistributorOwnership(address rewardDistributor) external onlyGovernanceOrFactory {
        if (rewardDistributor == address(0)) revert ADDRESS_NULL();

        (bool success,) = address(rewardDistributor).call(abi.encodeWithSignature("accept_transfer_ownership()"));
        if (!success) revert LOW_LEVEL_CALL_FAILED();
    }

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE STRATEGY SETTERS
    //////////////////////////////////////////////////////

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert GOVERNANCE();

        governance = msg.sender;
        emit GovernanceChanged(msg.sender);
    }

    /// @notice Set Accumulator new address
    /// @param newAccumulator Address of new Accumulator
    function setAccumulator(address newAccumulator) external onlyGovernance {
        if (newAccumulator == address(0)) revert ADDRESS_NULL();
        accumulator = newAccumulator;
    }

    /// @notice Set Factory address.
    /// @param _factory Address of new Accumulator
    function setFactory(address _factory) external onlyGovernance {
        if (_factory == address(0)) revert ADDRESS_NULL();

        /// Remove allocation for the old factory.
        allowed[factory] = false;

        factory = _factory;

        /// Allow the factory to interact with this contract.
        allowed[_factory] = true;
    }

    /// @notice Set new RewardToken FeeDistributor new address
    /// @param newCurveRewardToken Address of new curve reward token
    function setFeeRewardToken(address newCurveRewardToken) external onlyGovernance {
        if (newCurveRewardToken == address(0)) revert ADDRESS_NULL();
        feeRewardToken = newCurveRewardToken;
    }

    /// @notice Set FeeDistributor new address
    /// @param newFeeDistributor Address of new fee distributor
    function setFeeDistributor(address newFeeDistributor) external onlyGovernance {
        if (newFeeDistributor == address(0)) revert ADDRESS_NULL();
        feeDistributor = newFeeDistributor;
    }

    /// @notice Set SdtDistributor new address
    /// @param newSdtDistributor Address of new SdtDistributor
    function setSdtDistributor(address newSdtDistributor) external onlyGovernance {
        if (newSdtDistributor == address(0)) revert ADDRESS_NULL();
        SDTDistributor = newSdtDistributor;
    }

    /// @notice Set FeeReceiver new address.
    /// @param _feeReceiver Address of new FeeReceiver.
    function setFeeReceiver(address _feeReceiver) external onlyGovernance {
        if (_feeReceiver == address(0)) revert ADDRESS_NULL();
        feeReceiver = _feeReceiver;
    }

    /// @notice Update protocol fees.
    /// @param protocolFee New protocol fee.
    function updateProtocolFee(uint256 protocolFee) external onlyGovernance {
        if (claimIncentiveFee + protocolFee > DENOMINATOR) revert FEE_TOO_HIGH();
        protocolFeesPercent = protocolFee;
    }

    /// @notice Update claimIncentive fees.
    /// @param _claimIncentiveFee New Claim Incentive Fees
    function updateClaimIncentiveFee(uint256 _claimIncentiveFee) external onlyGovernance {
        if (protocolFeesPercent + _claimIncentiveFee > DENOMINATOR) revert FEE_TOO_HIGH();
        claimIncentiveFee = _claimIncentiveFee;
    }

    /// @notice Allow a module to interact with the `execute` function.
    /// @dev excodesize can be bypassed but whitelist should go through governance.
    function allowAddress(address _address) external onlyGovernance {
        if (_address == address(0)) revert ADDRESS_NULL();

        /// Check if the address is a contract.
        int256 size;
        assembly {
            size := extcodesize(_address)
        }
        if (size == 0) revert NOT_CONTRACT();

        allowed[_address] = true;
    }

    /// @notice Disallow a module to interact with the `execute` function.
    function disallowAddress(address _address) external onlyGovernance {
        allowed[_address] = false;
    }

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE OR ALLOWED FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Add Extra Reward Token to a Liquidity Gauge.
    /// @dev Allowed contract need to do extra checks for the safety of the token to add.
    /// Eg. Check if the token is a gauge token, or if the token is already added, rebasing, in the gauge controller etc.
    function addRewardToken(address gauge, address extraRewardToken) external onlyGovernanceOrAllowed {
        if (gauge == address(0) || extraRewardToken == address(0)) revert ADDRESS_NULL();

        /// Get the rewardDistributor address to add the reward token to.
        address _rewardDistributor = rewardDistributors[gauge];

        /// Approve the rewardDistributor to spend token.
        SafeTransferLib.safeApproveWithRetry(extraRewardToken, _rewardDistributor, type(uint256).max);

        /// Add it to the Gauge with Distributor as this contract.
        ILiquidityGauge(_rewardDistributor).add_reward(extraRewardToken, address(this));
    }

    /// @notice Execute a function.
    /// @param to Address of the contract to execute.
    /// @param value Value to send to the contract.
    /// @param data Data to send to the contract.
    /// @return success_ Boolean indicating if the execution was successful.
    /// @return result_ Bytes containing the result of the execution.
    function execute(address to, uint256 value, bytes calldata data)
        external
        onlyGovernanceOrAllowed
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }

    /// UUPS Upgradeability.
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    receive() external payable {}
}
