// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YieldnestLocker} from "@address-book/src/YieldnestEthereum.sol";
import {AutocompoundedVault} from "src/AutocompoundedVault.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {SafeModule} from "@shared/safe/SafeModule.sol";

/// @title Yieldnest Autocompounded Vault
/// @notice
///   This contract is a specialized ERC4626 vault for the Yieldnest protocol, designed to maximize yield for sdYND token holders.
///   - User deposits are automatically staked into the Yieldnest liquidity gauge to earn additional rewards.
///   - All staking rewards are periodically collected by the contract owner, swapped to sdYND, and streamed to vault users over a
///     fixed 7-day period.
///   - The vault issues asdYND shares, representing a claim on both the staked principal and the vested portion of streaming rewards.
///   - The contract is non-custodial: users can deposit and withdraw at any time, and their share of rewards is determined
///     transparently by the vault's logic.
/// @dev
///   - This implementation is opinionated for the Yieldnest protocol: it uses sdYND as the asset, a 7-day streaming period, and
///     integrates directly with a specified gauge for staking.
///   - The owner is responsible for claiming rewards from the gauge, swapping them to sdYND, and initiating new reward streams for
///     users.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract YieldnestAutocompoundedVault is AutocompoundedVault, SafeModule {
    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice The liquidity gauge where the assets are staked on deposit
    ILiquidityGauge public immutable LIQUIDITY_GAUGE;

    /// @notice The locker contract where the assets are staked
    address public immutable LOCKER;

    /// @notice The amount of staked assets
    uint256 public staked;

    ////////////////////////////////////////////////////////////////
    /// --- ERRORS / EVENTS
    ///////////////////////////////////////////////////////////////
    /// @notice Emitted when a user migrates gauge tokens into the vault
    /// @param user The address that migrated the gauge tokens
    /// @param shares The amount of asdYND shares minted for the user
    event GaugeTokenMigrated(address indexed user, uint256 assets, uint256 shares);

    /// @notice Error thrown when the owner tries to recover sdYND that is not lost
    error NothingToRecover();

    /// @notice Error thrown when the owner tries to recover more sdYND than the amount lost
    error NotEnoughAssetToRecover();

    /// @notice Emitted when the owner recovers sdYND
    /// @param to The address that received the recovered sdYND
    /// @param amount The amount of sdYND recovered
    event LostAssetsRecovered(address indexed to, uint256 amount);

    /// @notice Initialize the the streaming period, the asset and the shares token
    /// @dev sdYND is the asset contract while asdYND is the shares token
<<<<<<< HEAD
    /// @param _owner The owner of the vault
    constructor(address _owner)
        AutocompoundedVault(7 days, IERC20(YieldnestLocker.SDYND), "Autocompounded Stake DAO YND", "asdYND", _owner)
    {}
=======
    /// @param _owner The owner of the vault and the rewards receiver of the gauge
    /// @param _gauge The liquidity gauge where the assets will be deposited
    /// @param _manager The manager of the vault, responsible of managing the stream of rewards
    /// @param _gateway The gateway contract address
    constructor(address _owner, address _gauge, address _manager, address _gateway, address _locker)
        AutocompoundedVault(
            7 days,
            IERC20(YieldnestProtocol.SDYND),
            "Autocompounded Stake DAO YND",
            "asdYND",
            _owner,
            _manager
        )
        SafeModule(_gateway)
    {
        LIQUIDITY_GAUGE = ILiquidityGauge(_gauge);
        LOCKER = _locker;
    }

    ////////////////////////////////////////////////////////////////
    /// --- MIGRATION FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Allows migration of existing gauge tokens into the vault in exchange for asdYND shares.
    /// @dev This function is intended for migration scenarios. It:
    ///      - Transfer the caller's gauge tokens to the gauge contract
    ///      - Mint shares for the caller
    ///
    ///     This function bypasses by design the `maxDeposit` check. Do not use this logic when overriding `maxDeposit`.
    ///     This function assumes that the gauge is always 1:1 with the asset token. Do not use this logic with non-1:1 gauges.
    ///     The caller receives shares proportional to the vested portion of the assets.
    /// @return shares The amount of asdYND shares minted for the receiver
    /// @custom:throws ERC20InvalidReceiver when the receiver is the zero address
    function depositFromGauge() external returns (uint256 shares) {
        return depositFromGauge(msg.sender);
    }

    /// @notice Allows migration of existing gauge tokens into the vault in exchange for asdYND shares.
    /// @dev This function is intended for migration scenarios. It:
    ///      - Transfer the caller's gauge tokens to the gauge contract
    ///      - Mint shares for the given receiver
    ///
    ///     This function bypasses by design the `maxDeposit` check. Do not use this logic when overriding `maxDeposit`.
    ///     This function assumes that the gauge is always 1:1 with the asset token. Do not use this logic with non-1:1 gauges.
    ///     The receiver receives shares proportional to the vested portion of the assets.
    /// @param receiver The address to receive the asdYND shares
    /// @return shares The amount of asdYND shares minted for the receiver
    /// @custom:throws ERC20InvalidReceiver when the receiver is the zero address
    function depositFromGauge(address receiver) public returns (uint256 shares) {
        // Fetch the gauge tokens balance of the caller
        uint256 assets = LIQUIDITY_GAUGE.balanceOf(msg.sender);
        shares = previewDeposit(assets);

        // Transfer the gauge tokens from the caller to the locker contract
        LIQUIDITY_GAUGE.transferFrom(msg.sender, _getLocker(), assets);

        // Mint the asdYND shares for the receiver (1:1 ratio with the gauge tokens)
        _mint(receiver, shares);

        // Increase the internal accounting of the staked assets
        staked += assets;

        // this event is required for the 4626-compatibility
        emit Deposit(msg.sender, receiver, assets, shares);
        emit GaugeTokenMigrated(receiver, assets, shares);
    }

    ////////////////////////////////////////////////////////////////
    /// --- OVERRIDED VAULT FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Stake the deposit assets to the gauge
    /// @dev The internal accounting
    function _stake(uint256 assets) internal override {
        // Transfer the assets from this contract to the locker contract
        IERC20(asset()).transfer(_getLocker(), assets);

        // Deposit the assets in the gauge via the locker
        bytes memory data = abi.encodeWithSignature("deposit(uint256)", assets);
        _executeTransaction(address(LIQUIDITY_GAUGE), data);

        // Increase the internal accounting of the staked assets
        staked += assets;
    }

    /// @notice Unstake the assets from the gauge before the withdrawal
    function _unstake(uint256 assets) internal override {
        // Decrease the internal accounting of the staked assets
        staked -= assets;

        // Withdraw the assets from the gauge via the locker
        bytes memory data = abi.encodeWithSignature("withdraw(uint256,bool)", assets, false);
        _executeTransaction(address(LIQUIDITY_GAUGE), data);

        // Transfer the assets from the locker contract to this contract
        data = abi.encodeWithSignature("transfer(address,uint256)", address(this), assets);
        _executeTransaction(asset(), data);
    }

    /// @notice Get the current staked balance of this contract
    /// @return The staked balance of this contract
    function _getStakedBalance() internal view override returns (uint256) {
        return staked;
    }

    /// @notice Claim the staking rewards from the gauge
    /// @dev This function is virtual to allow overriding for the YieldnestVotemarket contract
    function claimStakingRewards() external pure override {
        revert("CLAIM THE REWARDS FROM THE LOCKER DIRECTLY");
    }

    ////////////////////////////////////////////////////////////////
    /// --- HELPERS FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Allows the owner to recover sdYND tokens sent directly to this contract (not staked in the gauge)
    /// @dev    The assets are staked in the gauge as soon as they are deposited by the user or the stream creator.
    ///         No sdYND should be lost in the vault unless made a mistake by sending sdYND directly to the vault.
    /// @param to The address to send the recovered tokens to
    /// @param amount The amount of sdYND to recover. Can be 0 to recover all the lost sdYND.
    function recoverLostAssets(address to, uint256 amount) external onlyOwner {
        uint256 lost = IERC20(asset()).balanceOf(address(this));
        require(lost != 0, NothingToRecover());

        uint256 recover = amount == 0 ? lost : amount;
        require(recover <= lost, NotEnoughAssetToRecover());
        IERC20(asset()).transfer(to, recover);

        emit LostAssetsRecovered(to, recover);
    }

    /// @notice Get the locker contract address
    /// @return The locker contract address
    function _getLocker() internal view override returns (address) {
        return LOCKER;
    }

    /// @notice Get the version of the contract
    /// @custom:previous-version 0x3610A0f4a36513d27128e110dB999D6e1e6105D5
    function version() external pure override returns (string memory) {
        return "2.1.0";
    }
>>>>>>> effd608d (feat(strategy): yield for asd vault)
}
