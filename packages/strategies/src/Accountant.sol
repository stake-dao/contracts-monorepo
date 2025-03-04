/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IHarvester} from "src/interfaces/IHarvester.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Accountant - Reward Distribution and Accounting System
/// @notice A comprehensive system for managing reward distribution and accounting across vaults and users.
/// @dev Implements a gas-optimized packed storage system for efficient reward tracking and distribution.
///      Key responsibilities:
///      - Tracks user balances and rewards across vaults.
///      - Manages protocol fees and dynamic harvest fees.
///      - Handles reward distribution and claiming.
///      - Maintains integral calculations for reward accrual.
contract Accountant is ReentrancyGuardTransient, Ownable2Step, IAccountant {
    using Math for uint256;
    using Math for uint128;
    using SafeCast for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- STORAGE STRUCTURES
    //////////////////////////////////////////////////////

    /// @notice Vault data structure.
    struct VaultData {
        uint256 integral;
        uint128 supply;
        uint128 feeSubjectAmount;
        uint128 totalAmount;
    }

    /// @notice Account data structure for a specific Vault
    struct AccountData {
        uint128 balance;
        uint256 integral;
        uint256 pendingRewards;
    }

    /// @notice Struct that defines the fees parameters.
    struct FeesParams {
        uint128 protocolFeePercent;
        uint128 harvestFeePercent;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice RAY scaling factor used for fixed-point arithmetic precision.
    uint128 public constant SCALING_FACTOR = 1e27;

    /// @notice The maximum fee percent (40%).
    uint128 public constant MAX_FEE_PERCENT = 0.4e18;

    /// @notice The minimum amount of rewards to be added to the vault.
    uint128 public constant MIN_MEANINGFUL_REWARDS = 1e18;

    /// @notice The registry of addresses.
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    /// @notice The reward token.
    address public immutable REWARD_TOKEN;

    /// @notice The protocol ID.
    bytes4 public immutable PROTOCOL_ID;

    /// @notice The default protocol fee.
    /// @dev The validity of this value is not checked. It must always be valid
    uint128 internal constant DEFAULT_PROTOCOL_FEE = 0.15e18;

    /// @notice The default harvest fee.
    /// @dev The validity of this value is not checked. It must always be valid
    uint128 internal constant DEFAULT_HARVEST_FEE = 0.005e18;

    //////////////////////////////////////////////////////
    /// --- STATE VARIABLES
    //////////////////////////////////////////////////////

    /// @notice The feesParams struct.
    FeesParams public feesParams;

    /// @notice The balance threshold for harvest fee calculation.
    /// @dev If set to 0, maximum harvest fee always applies.
    uint256 public HARVEST_URGENCY_THRESHOLD;

    /// @notice The total protocol fees collected but not yet claimed.
    uint256 public protocolFeesAccrued;

    /// @notice Supply of vaults.
    /// @dev Vault address -> VaultData.
    mapping(address vault => VaultData vaultData) internal vaults;

    /// @notice Balances of accounts per vault.
    /// @dev Vault address -> Account address -> AccountData.
    mapping(address vault => mapping(address account => AccountData accountData)) internal accounts;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the caller is not a vault.
    error OnlyVault();

    /// @notice Error thrown when the caller is not allowed.
    error OnlyAllowed();

    /// @notice Error thrown when the harvester is not set.
    error NoHarvester();

    /// @notice Error thrown when the fee receiver is not set.
    error NoFeeReceiver();

    /// @notice Error thrown when there are no pending rewards.
    error NoPendingRewards();

    /// @notice Error thrown when a fee exceeds the maximum allowed
    error FeeExceedsMaximum();

    /// @notice Error thrown when harvest data length doesn't match vaults length
    error InvalidHarvestDataLength();

    /// @notice Error thrown when the protocol controller is invalid
    error InvalidProtocolController();

    /// @notice Error thrown when the reward token is invalid
    error InvalidRewardToken();

    /// @notice Error thrown when the protocol ID is invalid
    error InvalidProtocolId();

    /// @notice Error thrown when the harvester has not transferred the correct amount of tokens to the Accountant contract
    error HarvestTokenNotReceived();

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////

    /// @notice Emitted when protocol fees are claimed.
    event ProtocolFeesClaimed(uint256 amount);

    /// @notice Emitted when a vault harvests rewards.
    event Harvest(address indexed vault, uint256 amount);

    /// @notice Emitted when the protocol fee percent is updated.
    event ProtocolFeePercentSet(uint128 oldProtocolFeePercent, uint128 newProtocolFeePercent);

    /// @notice Emitted when the balance threshold is updated.
    event HarvestUrgencyThresholdSet(uint256 oldThreshold, uint256 newThreshold);

    /// @notice Emitted when the harvest fee percent is updated.
    event HarvestFeePercentSet(uint128 oldHarvestFeePercent, uint128 newHarvestFeePercent);

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    modifier onlyAllowed() {
        require(PROTOCOL_CONTROLLER.allowed(address(this), msg.sender, msg.sig), OnlyAllowed());
        _;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the Accountant contract with owner, registry, and reward token.
    /// @param _owner The address of the contract owner.
    /// @param _registry The address of the registry contract.
    /// @param _rewardToken The address of the reward token.
    /// @param _protocolId The bytes4 ID of the protocol
    /// @custom:throws OwnableInvalidOwner If the owner is the zero address.
    /// @custom:throws InvalidProtocolController If the protocol controller is the zero address.
    /// @custom:throws InvalidRewardToken If the reward token is the zero address.
    constructor(address _owner, address _registry, address _rewardToken, bytes4 _protocolId) Ownable(_owner) {
        require(_registry != address(0), InvalidProtocolController());
        require(_rewardToken != address(0), InvalidRewardToken());
        require(_protocolId != bytes4(0), InvalidProtocolId());

        /// set the immutable variables
        PROTOCOL_CONTROLLER = IProtocolController(_registry);
        REWARD_TOKEN = _rewardToken;
        PROTOCOL_ID = _protocolId;

        /// set the initial fees to the default values, and emit the update events
        feesParams = FeesParams({protocolFeePercent: DEFAULT_PROTOCOL_FEE, harvestFeePercent: DEFAULT_HARVEST_FEE});
        emit HarvestFeePercentSet(0, DEFAULT_HARVEST_FEE);
        emit ProtocolFeePercentSet(0, DEFAULT_PROTOCOL_FEE);
    }

    //////////////////////////////////////////////////////
    /// --- CHECKPOINT OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Checkpoints the state of the vault on every account action.
    /// @dev Handles four types of operations:
    ///      1. Minting (from = address(0)): Creates new tokens.
    ///      2. Burning (to = address(0)): Destroys tokens.
    ///      3. Transfers: Updates balances and rewards for both sender and receiver.
    ///      4. Reward Distribution: Processes pending rewards if any exist.
    /// @param gauge The underlying gauge address of the vault.
    /// @param from The source address (address(0) for minting).
    /// @param to The destination address (address(0) for burning).
    /// @param amount The amount of tokens being transferred/minted/burned.
    /// @param pendingRewards New rewards to be distributed to the vault.
    /// @param harvested Whether these rewards were already harvested by the vault and sent to the contract.
    /// @custom:throws OnlyVault If caller is not the registered vault for the gauge.
    function checkpoint(
        address gauge,
        address from,
        address to,
        uint128 amount,
        IStrategy.PendingRewards calldata pendingRewards,
        bool harvested
    ) external nonReentrant {
        require(PROTOCOL_CONTROLLER.vaults(gauge) == msg.sender, OnlyVault());

        VaultData storage _vault = vaults[msg.sender];
        uint128 supply = _vault.supply;
        uint256 integral = _vault.integral;

        // Process any pending rewards if they exist and there is supply
        if (pendingRewards.totalAmount > 0 && supply > 0) {
            // Calculate the new rewards to be added to the vault.
            uint128 newRewards = pendingRewards.totalAmount - _vault.totalAmount;
            uint128 newFeeSubjectAmount = pendingRewards.feeSubjectAmount - _vault.feeSubjectAmount;

            uint128 totalFees;
            if (harvested && newRewards > 0) {
                // Calculate total fees in one operation
                // We charge only protocol fee on the harvested rewards.
                if (newFeeSubjectAmount > 0) {
                    totalFees = newFeeSubjectAmount.mulDiv(getProtocolFeePercent(), 1e18).toUint128();
                    // Update protocol fees accrued.
                    protocolFeesAccrued += totalFees;
                }

                // Update integral with new rewards per token
                integral += (newRewards - totalFees).mulDiv(SCALING_FACTOR, supply);
            }
            // If the new rewards are above the minimum meaningful rewards,
            // we update the integral and pending rewards.
            // Otherwise, we don't update the integral to avoid precision loss. It won't be lost, just delayed.
            else if (newRewards >= MIN_MEANINGFUL_REWARDS) {
                // Calculate total fees in one operation
                // We charge protocol and harvest fees on the unclaimed rewards.
                if (newFeeSubjectAmount > 0) {
                    totalFees = newFeeSubjectAmount.mulDiv(getProtocolFeePercent(), 1e18).toUint128();
                }

                // Get harvest fee for the unclaimed rewards.
                totalFees += newRewards.mulDiv(getHarvestFeePercent(), 1e18).toUint128();

                // Update integral with new rewards per token
                integral += (newRewards - totalFees).mulDiv(SCALING_FACTOR, supply);

                // Update the total amount and the fee subject amount of the Vault
                _vault.totalAmount = pendingRewards.totalAmount;
                _vault.feeSubjectAmount = pendingRewards.feeSubjectAmount;
            }
        }

        // Handle token operations
        if (from == address(0)) {
            // Minting operation
            supply += amount;
        } else {
            // Update sender's balance and rewards
            _updateAccountState({
                vault: msg.sender,
                account: from,
                amount: amount,
                currentIntegral: integral,
                isDecrease: true
            });
        }

        if (to == address(0)) {
            // Burning operation
            supply -= amount;
        } else {
            // Update receiver's balance and rewards
            _updateAccountState({
                vault: msg.sender,
                account: to,
                amount: amount,
                currentIntegral: integral,
                isDecrease: false
            });
        }

        // Update vault data with new supply and integral
        _vault.integral = integral;
        _vault.supply = supply;
    }

    /// @dev Updates account state during operations.
    /// @param vault The vault address.
    /// @param account The account to update.
    /// @param amount The amount to add/subtract.
    /// @param isDecrease Whether to decrease (true) or increase (false) the balance.
    /// @param currentIntegral The current reward integral to checkpoint against.
    function _updateAccountState(
        address vault,
        address account,
        uint128 amount,
        bool isDecrease,
        uint256 currentIntegral
    ) private {
        AccountData storage accountData = accounts[vault][account];
        // cache the balance in the stack for gas optimization
        uint128 accountBalance = accountData.balance;

        // Update pending rewards based on the integral difference.
        accountData.pendingRewards +=
            (currentIntegral - accountData.integral).mulDiv(uint256(accountBalance), SCALING_FACTOR);
        accountData.balance = isDecrease ? accountBalance - amount : accountBalance + amount;
        accountData.integral = currentIntegral;
    }

    /// @notice Returns the total supply of tokens in a vault.
    /// @param vault The vault address to query.
    /// @return _ The total supply of tokens in the vault.
    function totalSupply(address vault) external view returns (uint128) {
        return vaults[vault].supply;
    }

    /// @notice Returns the token balance of an account in a vault.
    /// @param vault The vault address to query.
    /// @param account The account address to check.
    /// @return _ The account's token balance in the vault.
    function balanceOf(address vault, address account) external view returns (uint128) {
        return accounts[vault][account].balance;
    }

    /// @notice Returns the pending rewards for an account in a vault.
    /// @param vault The vault address to query.
    /// @param account The account address to check.
    /// @return _ The pending rewards for the account in the vault.
    function getPendingRewards(address vault, address account) external view returns (uint256) {
        return accounts[vault][account].pendingRewards;
    }

    /// @notice Returns the pending rewards for a vault.
    /// @param vault The vault address to query.
    /// @return The pending rewards for the vault.
    function getPendingRewards(address vault) external view returns (uint128) {
        return vaults[vault].totalAmount;
    }

    //////////////////////////////////////////////////////
    /// --- HARVEST OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Harvests rewards from multiple vaults.
    /// @param _vaults Array of vault addresses to harvest from.
    /// @param _harvestData Array of harvest data for each vault.
    /// @custom:throws NoHarvester If the harvester is not set.
    function harvest(address[] calldata _vaults, bytes[] calldata _harvestData) external {
        require(_vaults.length == _harvestData.length, InvalidHarvestDataLength());
        _batchHarvest({_vaults: _vaults, harvestData: _harvestData, receiver: msg.sender});
    }

    /// @dev Internal implementation of batch harvesting.
    /// @param _vaults Array of vault addresses to harvest from.
    /// @param harvestData Harvest data for each vault.
    function _batchHarvest(address[] calldata _vaults, bytes[] calldata harvestData, address receiver)
        internal
        nonReentrant
    {
        // Cache registry to avoid multiple SLOADs
        address harvester = PROTOCOL_CONTROLLER.harvester(PROTOCOL_ID);
        require(harvester != address(0), NoHarvester());

        uint256 totalHarvesterFee;

        for (uint256 i; i < _vaults.length; i++) {
            /// Harvest the vault and increment total harvester fee.
            totalHarvesterFee += _harvest({
                vault: _vaults[i],
                harvestData: harvestData[i],
                harvester: harvester,
                registry: address(PROTOCOL_CONTROLLER)
            });
        }

        // Transfer total harvester fee if any
        if (totalHarvesterFee > 0) {
            IERC20(REWARD_TOKEN).safeTransfer(receiver, totalHarvesterFee);
        }
    }

    /// @dev Internal implementation of single vault harvesting.
    /// @return harvesterFee The harvester fee for this harvest operation.
    function _harvest(address vault, bytes calldata harvestData, address harvester, address registry)
        private
        returns (uint256 harvesterFee)
    {
        // Fees should be calculated before the harvest.
        uint256 currentHarvestFee = getCurrentHarvestFee();

        // Fetch the balance of the Accountant contract before harvesting
        uint256 balanceBefore = IERC20(REWARD_TOKEN).balanceOf(address(this));

        // Harvest the asset
        (uint256 feeSubjectAmount, uint256 totalAmount) = abi.decode(
            harvester.functionDelegateCall(
                abi.encodeWithSelector(
                    IHarvester.harvest.selector, IProtocolController(registry).assets(vault), harvestData
                )
            ),
            (uint256, uint256)
        );
        if (totalAmount == 0) return 0;

        // Check that the harvester has transferred the correct amount of reward tokens to this contract
        require(IERC20(REWARD_TOKEN).balanceOf(address(this)) >= balanceBefore + totalAmount, HarvestTokenNotReceived());

        // We charge protocol fee on the feeable amount and update the accrued fees.
        protocolFeesAccrued += feeSubjectAmount.mulDiv(feesParams.protocolFeePercent, 1e18);

        // We charge harvester fee on the total amount.
        harvesterFee = totalAmount.mulDiv(currentHarvestFee, 1e18);

        VaultData storage _vault = vaults[vault];
        uint256 pendingRewards = _vault.totalAmount;

        // Refund the excess harvest fee taken at the checkpoint.
        uint128 currentHarvestFeePercent = feesParams.harvestFeePercent;
        if (pendingRewards > 0 && currentHarvestFee < currentHarvestFeePercent) {
            totalAmount += pendingRewards.mulDiv(currentHarvestFeePercent - currentHarvestFee, 1e18);
        }

        // Update vault state
        _updateVaultState({vault: _vault, pendingRewards: pendingRewards, amount: totalAmount});

        // Always clear pending rewards after harvesting.
        _vault.feeSubjectAmount = 0;
        _vault.totalAmount = 0;

        emit Harvest(vault, totalAmount);
    }

    /// @dev Updates vault state during harvest.
    /// @param vault The vault address to update.
    /// @param pendingRewards Previous pending rewards to be cleared
    /// @param amount The total reward amount.
    function _updateVaultState(VaultData storage vault, uint256 pendingRewards, uint256 amount) private {
        // Early return if no state changes needed
        if (pendingRewards == 0 || amount == pendingRewards) return;

        // netDelta is defined as newRewards + refund - totalFees.
        // Since amount = newRewards + pendingRewards + refund,
        // netDelta = amount - pendingRewards.
        uint256 netDelta = amount - pendingRewards;

        // Update the integral
        vault.integral += netDelta.mulDiv(SCALING_FACTOR, vault.supply);
    }

    /// @notice Returns the current harvest fee based on contract balance
    /// @return _ The current harvest fee percentage
    function getCurrentHarvestFee() public view returns (uint256) {
        uint256 harvestTreshold = HARVEST_URGENCY_THRESHOLD;
        uint128 currentHarvestFeePercent = feesParams.harvestFeePercent;

        // If threshold is 0, always return max harvest fee
        if (harvestTreshold == 0) return currentHarvestFeePercent;

        // If threshold is not set, return the current harvest fee based on balance
        uint256 balance = IERC20(REWARD_TOKEN).balanceOf(address(this));
        return balance >= harvestTreshold ? 0 : currentHarvestFeePercent * (harvestTreshold - balance) / harvestTreshold;
    }

    /// @notice Returns the current harvest fee percentage.
    /// @return _ The harvest fee percentage.
    function getHarvestFeePercent() public view returns (uint128) {
        return feesParams.harvestFeePercent;
    }

    /// @notice Updates the harvest fee percentage.
    /// @param newHarvestFeePercent New harvest fee percentage (scaled by 1e18).
    /// @custom:throws FeeExceedsMaximum If fee would exceed maximum.
    function setHarvestFeePercent(uint128 newHarvestFeePercent) external onlyOwner {
        FeesParams storage currentFees = feesParams;

        // check that the new total fee (protocol + harvest) is valid
        uint256 totalFee = uint256(currentFees.protocolFeePercent) + uint256(newHarvestFeePercent);
        require(totalFee <= MAX_FEE_PERCENT, FeeExceedsMaximum());

        // emit the harvest event before updating the storage pointer
        emit HarvestFeePercentSet(currentFees.harvestFeePercent, newHarvestFeePercent);

        // set the new protocol fee percent
        feesParams.harvestFeePercent = newHarvestFeePercent;
    }

    /// @notice Updates the balance threshold for harvest fee calculation
    /// @param _threshold New balance threshold. Set to 0 to always apply maximum harvest fee.
    function setHarvestUrgencyThreshold(uint256 _threshold) external onlyOwner {
        // emit the update event before updating the stored value
        emit HarvestUrgencyThresholdSet(HARVEST_URGENCY_THRESHOLD, _threshold);

        HARVEST_URGENCY_THRESHOLD = _threshold;
    }

    //////////////////////////////////////////////////////
    /// --- CLAIM OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Claims multiple vault rewards for yourself.
    /// @param _vaults Array of vault addresses to claim rewards from.
    /// @param harvestData Optional harvest data for each vault. Empty bytes for vaults that don't need harvesting.
    /// @custom:throws NoPendingRewards If there are no rewards to claim.
    function claim(address[] calldata _vaults, bytes[] calldata harvestData) external {
        claim(_vaults, harvestData, msg.sender);
    }

    /// @notice Claims multiple vault rewards for yourself and sends them to a specific address.
    /// @param _vaults Array of vault addresses to claim rewards from.
    /// @param harvestData Optional harvest data for each vault. Empty bytes for vaults that don't need harvesting.
    /// @param receiver Address that will receive the claimed rewards.
    /// @custom:throws NoPendingRewards If there are no rewards to claim.
    function claim(address[] calldata _vaults, bytes[] calldata harvestData, address receiver) public {
        require(harvestData.length == 0 || harvestData.length == _vaults.length, InvalidHarvestDataLength());

        if (harvestData.length != 0) {
            _batchHarvest({_vaults: _vaults, harvestData: harvestData, receiver: receiver});
        }

        _claim({_vaults: _vaults, accountAddress: msg.sender, receiver: receiver});
    }

    /// @notice Claims multiple vault rewards on behalf of an account.
    /// @param _vaults Array of vault addresses to claim rewards from.
    /// @param account Address to claim rewards for.
    /// @param harvestData Optional harvest data for each vault. Empty bytes for vaults that don't need harvesting.
    /// @dev expected to be called by authorized accounts only
    /// @custom:throws OnlyAllowed If caller is not allowed to claim on behalf of others.
    /// @custom:throws NoPendingRewards If there are no rewards to claim.
    function claim(address[] calldata _vaults, address account, bytes[] calldata harvestData) external {
        claim(_vaults, account, harvestData, account);
    }

    /// @notice Claims multiple vault rewards on behalf of an account and sends them to a specific address.
    /// @param _vaults Array of vault addresses to claim rewards from.
    /// @param account Address to claim rewards for.
    /// @param harvestData Optional harvest data for each vault. Empty bytes for vaults that don't need harvesting.
    /// @param receiver Address that will receive the claimed rewards.
    /// @dev expected to be called by authorized accounts only
    /// @custom:throws OnlyAllowed If caller is not allowed to claim on behalf of others.
    /// @custom:throws NoPendingRewards If there are no rewards to claim.
    function claim(address[] calldata _vaults, address account, bytes[] calldata harvestData, address receiver)
        public
        onlyAllowed
    {
        require(harvestData.length == 0 || harvestData.length == _vaults.length, InvalidHarvestDataLength());

        if (harvestData.length != 0) {
            _batchHarvest({_vaults: _vaults, harvestData: harvestData, receiver: receiver});
        }

        _claim({_vaults: _vaults, accountAddress: account, receiver: receiver});
    }

    /// @dev Internal implementation of claim functionality.
    /// @param _vaults Array of vault addresses to claim rewards from.
    /// @param accountAddress Address to claim rewards for.
    /// @param receiver Address that will receive the claimed rewards.
    /// @custom:throws NoPendingRewards If the total claimed amount is zero.
    function _claim(address[] calldata _vaults, address accountAddress, address receiver) internal nonReentrant {
        uint256 totalAmount;

        // For each vault, check if the account has any rewards to claim
        for (uint256 i; i < _vaults.length; i++) {
            // Get the account data for this vault
            AccountData storage account = accounts[_vaults[i]][accountAddress];

            // Get the current balance for this vault
            uint128 balance = account.balance;

            // If account has any rewards to claim for this vault, calculate the amount. Otherwise, skip.
            if (balance != 0 || account.pendingRewards != 0) {
                // Get vault's and account's integral
                uint256 accountIntegral = account.integral;
                uint256 vaultIntegral = vaults[_vaults[i]].integral;

                // If vault's integral is higher than account's integral, calculate the rewards and update the total.
                // TODO: muldiv
                if (vaultIntegral > accountIntegral) {
                    totalAmount += (vaultIntegral - accountIntegral) * balance / SCALING_FACTOR;
                }

                // In any case, add the pending rewards to the total amount
                totalAmount += account.pendingRewards;

                // Update account's integral with the current value of Vault's integral
                account.integral = vaultIntegral;

                // reset the stored pending rewards for this vault
                account.pendingRewards = 0;
            }
        }

        // If there is no amount to claim for any vault, revert.
        require(totalAmount != 0, NoPendingRewards());

        // Transfer accumulated rewards to the receiver
        IERC20(REWARD_TOKEN).safeTransfer(receiver, totalAmount);
    }

    //////////////////////////////////////////////////////
    /// --- FEE MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Returns the current protocol fee percentage.
    /// @return _ The protocol fee percentage.
    function getProtocolFeePercent() public view returns (uint128) {
        return feesParams.protocolFeePercent;
    }

    /// @notice Updates the protocol fee percentage.
    /// @param newProtocolFeePercent New protocol fee percentage (scaled by 1e18).
    /// @custom:throws FeeExceedsMaximum If fee would exceed maximum.
    function setProtocolFeePercent(uint128 newProtocolFeePercent) external onlyOwner {
        // check that the provided protocol fee is valid
        require(newProtocolFeePercent <= MAX_FEE_PERCENT, FeeExceedsMaximum());

        FeesParams storage currentFees = feesParams;

        // check that the total fee (protocol + harvest) is valid
        uint128 totalFee = newProtocolFeePercent + currentFees.harvestFeePercent;
        require(totalFee <= MAX_FEE_PERCENT, FeeExceedsMaximum());

        // emit the update event
        emit ProtocolFeePercentSet(currentFees.protocolFeePercent, newProtocolFeePercent);

        // set the new protocol fee percent
        currentFees.protocolFeePercent = newProtocolFeePercent;
    }

    /// @notice Claims accumulated protocol fees.
    /// @dev Transfers fees to the configured fee receiver.
    /// @custom:throws NoFeeReceiver If the fee receiver is not set.
    function claimProtocolFees() external nonReentrant {
        // get the fee receiver from the protocol controller and check that it is valid
        address feeReceiver = PROTOCOL_CONTROLLER.feeReceiver(PROTOCOL_ID);
        require(feeReceiver != address(0), NoFeeReceiver());

        // get the protocol fees accrued until now and reset the stored value
        uint256 currentAccruedProtocolFees = protocolFeesAccrued;
        protocolFeesAccrued = 0;

        // transfer the accrued protocol fees to the fee receiver and emit the claim event
        IERC20(REWARD_TOKEN).transfer(feeReceiver, currentAccruedProtocolFees);
        emit ProtocolFeesClaimed(currentAccruedProtocolFees);
    }

    /// @notice Returns the total fee percentage (protocol + harvest).
    /// @return _ The total fee percentage.
    function getTotalFeePercent() external view returns (uint128) {
        return feesParams.protocolFeePercent + feesParams.harvestFeePercent;
    }
}
