// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ILocker} from "src/interfaces/ILocker.sol";
import {SafeExecute} from "src/libraries/SafeExecute.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {ISdtDistributorV2} from "src/interfaces/ISdtDistributorV2.sol";

/// @title Strategy
/// @author Stake DAO
/// @notice Strategy Proxy Contract to interact with Stake DAO Locker.
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
    //address public accumulator = 0xa44bFD194Fd7185ebecEcE4F7fA87a47DaA01c6A;
    address public accumulator;

    /// @notice Curve DAO token Fee Distributor
    //address public feeDistributor = 0xA464e6DCda8AC41e03616F95f4BC98a13b8922Dc;
    address public feeDistributor;

    /// @notice Reward Token for veCRV holders.
    /// address public feeRewardToken = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public feeRewardToken;

    /// @notice Stake DAO SDT Distributor
    address public SDTDistributor = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C;

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

    /// @notice Error emitted when sum of fees is above 100%
    error FEE_TOO_HIGH();

    /// @notice Error emitted when auth failed
    error GOVERNANCE();

    /// @notice Error emitted when auth failed
    error UNAUTHORIZED();

    /// @notice Error emitted when auth failed
    error GOVERNANCE_OR_FACTORY();

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

    function initialize(
        address owner
    ) external {
        if(governance != address(0)) revert GOVERNANCE();

        governance = owner;
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

    /// @notice Main gateway to deposit LP token into this strategy
    /// @dev Only callable by the `vault` or the governance
    /// @param _token Address of LP token to deposit
    /// @param amount Amount of LP token to deposit
    function deposit(address _token, uint256 amount) external onlyVault {
        // Transfer the token to this contract
        ERC20(_token).safeTransferFrom(msg.sender, address(this), amount);

        // Do the deposit process
        _deposit(_token, amount);
    }

    /// @notice Main gateway to withdraw LP token from this strategy
    /// @dev Only callable by `vault` or governance
    /// @param _token Address of LP token to withdraw
    /// @param amount Amount of LP token to withdraw
    function withdraw(address _token, uint256 amount) external onlyVault {
        // Do the withdraw process
        _withdraw(_token, amount);

        // Transfer the token to the user
        ERC20(_token).safeTransfer(msg.sender, amount);
    }

    //////////////////////////////////////////////////////
    /// --- LOCKER FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Internal gateway to deposit LP token using Stake DAO Liquid Locker
    /// @param _token Address of LP token to deposit
    /// @param gauge Address of Liqudity gauge corresponding to LP token
    /// @param amount Amount of LP token to deposit
    function _depositIntoLocker(address _token, address gauge, uint256 amount) internal virtual {
        ERC20(_token).safeTransfer(address(locker), amount);

        // Locker deposit token
        locker.execute(gauge, 0, abi.encodeWithSignature("deposit(uint256)", amount));
    }

    /// @notice Internal gateway to withdraw LP token from Stake DAO Liquid Locker
    /// @param _asset Address of LP token to withdraw
    /// @param gauge Address of Liqudity gauge corresponding to LP token
    /// @param amount Amount of LP token to withdraw
    function _withdrawFromLocker(address _asset, address gauge, uint256 amount) internal virtual {
        /// Withdraw from the Gauge trough the Locker.
        locker.execute(gauge, 0, abi.encodeWithSignature("withdraw(uint256)", amount));

        /// Transfer the _asset_ from the Locker to this contract.
        _transferFromLocker(_asset, address(this), amount);
    }

    //////////////////////////////////////////////////////
    /// --- CLAIM & DISTRIBUTION LOGIC
    //////////////////////////////////////////////////////

    /// @notice Claim `FeeRewardToken` from the Fee Distributor and send it to the Accumulator contract.
    function claimNativeRewards() external {
        /// Claim from the Fee Distributor.
        _claimNativeRewads();

        /// Check if there is something to send.
        uint256 _claimed = ERC20(feeRewardToken).balanceOf(address(locker));
        if (_claimed == 0) return;

        /// Transfer the rewards to the Accumulator contract.
        _transferFromLocker(feeRewardToken, accumulator, _claimed);
    }

    function harvest(address _asset, bool _distributeSDT, bool _claimExtra) public virtual {
        /// Get the gauge address.
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Cache the rewardDistributor address.
        address rewardDistributor = rewardDistributors[gauge];

        /// 1. Claim `rewardToken` from the Gauge.
        uint256 _claimed = _claimRewardToken(gauge);

        /// 2. Distribute SDT
        // Distribute SDT to the related gauge
        if (_distributeSDT) {
            ISdtDistributorV2(SDTDistributor).distribute(rewardDistributor);
        }

        /// 3. Check for additional rewards from the Locker.
        /// If there's the `rewardToken` as extra reward, we add it to the `_claimed` amount in order to distribute it only
        /// once.
        if (_claimExtra) {
            _claimed += _claimExtraRewards(gauge, rewardDistributor);
        }

        /// 4. Take Fees from _claimed amount.
        _claimed = _chargeProtocolFees(_claimed);

        /// 5. Distribute Claim Incentive
        _claimed = _distributeClaimIncentive(_claimed);

        /// 5. Distribute the rewardToken.
        ILiquidityGauge(rewardDistributor).deposit_reward_token(rewardToken, _claimed);
    }

    //////////////////////////////////////////////////////
    /// --- PROTOCOL FEES ACCOUNTING
    //////////////////////////////////////////////////////

    /// @notice Claim protocol fees and send them to the fee receiver.
    function claimProtocolFees() external {
        if (feesAccrued == 0) return;

        uint256 _feesAccrued = feesAccrued;
        feesAccrued = 0;

        ERC20(rewardToken).safeTransfer(feeReceiver, _feesAccrued);
    }

    /// @notice Internal function to charge protocol fees from `rewardToken` claimed by the locker.
    /// @return _amount Amount left after charging protocol fees.
    function _chargeProtocolFees(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) return 0;
        if (protocolFeesPercent == 0) return _amount;

        uint256 _feeAccrued = _amount.mulDivDown(protocolFeesPercent, DENOMINATOR);
        feesAccrued += _feeAccrued;

        return _amount -= _feeAccrued;
    }

    function _distributeClaimIncentive(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) return 0;
        if (claimIncentiveFee == 0) return _amount;

        uint256 _claimerIncentive = _amount.mulDivDown(claimIncentiveFee, DENOMINATOR);

        ERC20(rewardToken).safeTransfer(msg.sender, _claimerIncentive);

        return _amount - _claimerIncentive;
    }

    //////////////////////////////////////////////////////
    /// --- VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Internal gateway to deposit LP into this strategy
    /// @dev First check the optimal split, then send it to respective recipients
    /// @param _asset Address of LP token to deposit
    /// @param amount Amount of LP token to deposit
    function _deposit(address _asset, uint256 amount) internal virtual {
        // Get the gauge address
        address gauge = gauges[_asset];
        // Revert if the gauge is not set
        if (gauge == address(0)) revert ADDRESS_NULL();

        _depositIntoLocker(_asset, gauge, amount);
    }

    /// @notice Internal gateway to withdraw LP token from this strategy
    /// @dev First check where to remove liquidity, then remove liquidity accordingly
    /// @param _token Address of LP token to withdraw
    /// @param amount Amount of LP token to withdraw
    function _withdraw(address _token, uint256 amount) internal virtual {
        // Get the gauge address
        address gauge = gauges[_token];
        if (gauge == address(0)) revert ADDRESS_NULL();

        _withdrawFromLocker(_token, gauge, amount);
    }

    /// @notice Internal implementation of native reward claim compatible with FeeDistributor.vy like contracts.
    function _claimNativeRewads() internal virtual {
        locker.execute(feeDistributor, 0, abi.encodeWithSignature("claim()"));
    }

    function _claimRewardToken(address _gauge) internal virtual returns (uint256 _claimed) {
        /// Snapshot before claim.
        uint256 _snapshotBalance = ERC20(rewardToken).balanceOf(address(locker));

        /// Claim.
        locker.execute(minter, 0, abi.encodeWithSignature("mint(address)", _gauge));

        /// Snapshot after claim.
        _claimed = ERC20(rewardToken).balanceOf(address(locker)) - _snapshotBalance;

        /// Transfer the claimed amount to this contract.
        _transferFromLocker(rewardToken, address(this), _claimed);
    }

    function _claimExtraRewards(address _gauge, address _rewardDistributor)
        internal
        virtual
        returns (uint256 _rewardTokenClaimed)
    {
        if (lGaugeType[_gauge] > 0) return 0;

        // Cache the reward tokens and their balance before locker
        address[8] memory _extraRewardTokens;
        uint256[8] memory _snapshotLockerRewardBalances;

        uint8 i;
        for (i; i < 8;) {
            // Get reward token
            address _extraRewardToken = ILiquidityGauge(_gauge).reward_tokens(i);
            if (_extraRewardToken == address(0)) break;

            // Add the reward token address on the array
            _extraRewardTokens[i] = _extraRewardToken;
            // Add the reward token balance ot the locker on the array
            _snapshotLockerRewardBalances[i] = ERC20(_extraRewardToken).balanceOf(address(locker));

            unchecked {
                ++i;
            }
        }

        bool isTransferNeeded;
        if (
            !locker.safeExecute(
                _gauge, 0, abi.encodeWithSignature("claim_rewards(address,address)", address(locker), address(this))
            )
        ) {
            ILiquidityGauge(_gauge).claim_rewards(address(locker));
            isTransferNeeded = true;
        }

        for (i = 0; i < 8;) {
            address _extraRewardToken = _extraRewardTokens[i];
            if (_extraRewardToken == address(0)) break;

            // If the reward token is a gauge token (this can happen thanks to new proposal for permissionless gauge token addition),
            // it need to check only the freshly received rewards are considered as rewards!
            uint256 _claimed;
            if (isTransferNeeded) {
                _claimed = ERC20(_extraRewardToken).balanceOf(address(locker)) - _snapshotLockerRewardBalances[i];
                if (_claimed != 0) {
                    // Transfer the freshly rewards from the locker to this contract.
                    _transferFromLocker(_extraRewardToken, address(this), _claimed);
                }
            }

            if (_extraRewardToken == rewardToken) {
                _rewardTokenClaimed += _claimed;
            } else {
                _claimed = ERC20(_extraRewardToken).balanceOf(address(this));
                if (_claimed != 0) {
                    // Distribute the extra reward token.
                    ILiquidityGauge(_rewardDistributor).deposit_reward_token(_extraRewardToken, _claimed);
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

    function balanceOf(address _asset) public view virtual returns (uint256) {
        // Get the gauge address
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        return ILiquidityGauge(gauge).balanceOf(address(locker));
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL HELPER FUNCTIONS
    //////////////////////////////////////////////////////

    function _transferFromLocker(address _asset, address _recipient, uint256 _amount) internal {
        locker.execute(_asset, 0, abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount));
    }

    //////////////////////////////////////////////////////
    /// --- LOCKER HELPER FUNCTIONS
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

    //////////////////////////////////////////////////////
    /// --- MIGRATION LOGIC
    //////////////////////////////////////////////////////

    /// @notice Migrate LP token from the locker to the vault
    /// @dev Only callable by the vault
    /// @param _asset Address of LP token to migrate
    function migrateLP(address _asset) public virtual onlyVault {
        // Get gauge address
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        // Get the amount of LP token staked in the gauge by the locker
        uint256 amount = ERC20(gauge).balanceOf(address(locker));

        // Locker withdraw all from the gauge
        locker.execute(gauge, 0, abi.encodeWithSignature("withdraw(uint256)", amount));

        // Locker transfer the LP token to the vault
        _transferFromLocker(_asset, msg.sender, amount);
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
    function setGauge(address token, address gauge) external onlyGovernanceOrFactory {
        if (token == address(0)) revert ADDRESS_NULL();
        if (gauge == address(0)) revert ADDRESS_NULL();

        gauges[token] = gauge;

        /// Approve trough the locker.
        locker.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, 0));
        locker.execute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, type(uint256).max));
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
        ERC20(rewardToken).safeApprove(rewardDistributor, 0);
        ERC20(rewardToken).safeApprove(rewardDistributor, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE STRATEGY SETTERS
    //////////////////////////////////////////////////////

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
        factory = _factory;
    }

    /// @notice Set new RewardToken FeeDistributor new address
    /// @param newCurveRewardToken Address of new Accumulator
    function setFeeRewardToken(address newCurveRewardToken) external onlyGovernance {
        if (newCurveRewardToken == address(0)) revert ADDRESS_NULL();
        feeRewardToken = newCurveRewardToken;
    }

    /// @notice Set FeeDistributor new address
    /// @param newFeeDistributor Address of new Accumulator
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

    /// @notice Update protocol fees.
    /// @param _protocolFee New protocol fee.
    function updateProtocolFee(uint256 _protocolFee) external onlyGovernance {
        if (claimIncentiveFee + _protocolFee > DENOMINATOR) revert FEE_TOO_HIGH();
        protocolFeesPercent = _protocolFee;
    }

    /// @notice Update claimIncentive fees.
    /// @param _claimIncentiveFee New Claim Incentive Fees
    function updateClaimIncentiveFee(uint256 _claimIncentiveFee) external onlyGovernance {
        if (protocolFeesPercent + _claimIncentiveFee > DENOMINATOR) revert FEE_TOO_HIGH();
        claimIncentiveFee = _claimIncentiveFee;
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
        ERC20(extraRewardToken).safeApprove(_rewardDistributor, type(uint256).max);

        /// Add it to the Gauge with Distributor as this contract.
        ILiquidityGauge(_rewardDistributor).add_reward(extraRewardToken, address(this));
    }

    /// @notice Execute a function
    /// @dev Only callable by the owner
    /// @param to Address of the contract to execute
    /// @param value Value to send to the contract
    /// @param data Data to send to the contract
    /// @return success_ Boolean indicating if the execution was successful
    /// @return result_ Bytes containing the result of the execution
    function execute(address to, uint256 value, bytes calldata data)
        external
        onlyGovernanceOrAllowed
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    receive() external payable {}
}
