// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IStrategyVault} from "src/base/interfaces/IStrategyVault.sol";
import {LibClone} from "solady/utils/LibClone.sol";

import {IStrategy} from "src/base/interfaces/IStrategy.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ISDLiquidityGauge} from "src/base/interfaces/ISDLiquidityGauge.sol";

/// @notice Factory built to be compatible with CRV gauges but can be overidden to support other gauges/protocols.
abstract contract PoolFactory {
    using LibClone for address;

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Stake DAO strategy contract address.
    IStrategy public immutable strategy;

    /// @notice Reward token address.
    address public immutable rewardToken;

    /// @notice Staking Deposit implementation address.
    address public immutable vaultImplementation;

    /// @notice Liquidity Gauge implementation address.
    address public immutable liquidityGaugeImplementation;

    /// @notice Stake DAO token address.
    address public constant SDT = 0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F;

    /// @notice Voting Escrow Stake DAO token address.
    address public constant VESDT = 0x0C30476f66034E11782938DF8e4384970B6c9e8a;

    /// @notice SDT VEBoost proxy address.
    address public constant VE_BOOST_PROXY = 0xD67bdBefF01Fc492f1864E61756E5FBB3f173506;

    /// @notice Claim helper contract address for LiquidityGauges.
    address public constant CLAIM_HELPER = 0x633120100e108F03aCe79d6C78Aac9a56db1be0F;

    /// @notice Stake DAO token distributor address.
    address public constant SDT_DISTRIBUTOR = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C;

    /// @notice Throwed if the gauge is not valid candidate.
    error INVALID_GAUGE();

    /// @notice Throwed if the token is not valid.
    error INVALID_TOKEN();

    /// @notice Throwed if the gauge has been already used.
    error GAUGE_ALREADY_USED();

    /// @notice Emitted when a new pool is deployed.
    event PoolDeployed(address vault, address rewardDistributor, address token, address gauge);

    /// @notice Constructor.
    /// @param _strategy Address of the strategy contract. This contract should have the ability to add new reward tokens.
    /// @param _rewardToken Address of the main reward token.
    /// @param _vaultImplementation Address of the staking deposit implementation. Main entry point.
    /// @param _liquidityGaugeImplementation Address of the liquidity gauge implementation.
    constructor(
        address _strategy,
        address _rewardToken,
        address _vaultImplementation,
        address _liquidityGaugeImplementation
    ) {
        rewardToken = _rewardToken;
        strategy = IStrategy(_strategy);
        vaultImplementation = _vaultImplementation;
        liquidityGaugeImplementation = _liquidityGaugeImplementation;
    }

    /// @notice Add new staking gauge to Stake DAO Locker.
    /// @param _gauge Address of the liquidity gauge.
    /// @return vault Address of the staking deposit.
    /// @return rewardDistributor Address of the reward distributor to claim rewards.
    function create(address _gauge) public virtual returns (address vault, address rewardDistributor) {
        /// Perform checks on the gauge to make sure it's valid and can be used.
        if (!_isValidGauge(_gauge)) revert INVALID_GAUGE();

        /// Perform checks on the strategy to make sure it's not already used.
        if (strategy.rewardDistributors(_gauge) != address(0)) revert GAUGE_ALREADY_USED();

        /// Retrieve the staking token.
        address lp = _getGaugeStakingToken(_gauge);

        /// Clone the Reward Distributor.
        rewardDistributor = LibClone.clone(liquidityGaugeImplementation);

        /// We use the LP token and the gauge address as salt to generate the vault address.
        bytes32 salt = keccak256(abi.encodePacked(lp, _gauge));

        /// We use CWIA setup. We encode the LP token, the strategy address and the reward distributor address as data
        /// to be passed as immutable args to the vault.
        bytes memory vaultData = abi.encodePacked(lp, address(strategy), rewardDistributor);

        /// Clone the Vault.
        vault = vaultImplementation.cloneDeterministic(vaultData, salt);

        /// Retrieve the symbol to be used on the reward distributor.
        (, string memory _symbol) = _getNameAndSymbol(lp);

        /// Initialize the Reward Distributor.
        ISDLiquidityGauge(rewardDistributor).initialize(
            vault, address(this), SDT, VESDT, VE_BOOST_PROXY, SDT_DISTRIBUTOR, vault, _symbol
        );

        /// Initialize Vault.
        IStrategyVault(vault).initialize();

        /// Allow the vault to stake the LP token in the locker trough the strategy.
        strategy.toggleVault(vault);

        /// Map in the strategy the staking token to it's corresponding gauge.
        strategy.setGauge(lp, _gauge);

        /// Map the gauge to the reward distributor that should receive the rewards.
        strategy.setRewardDistributor(_gauge, rewardDistributor);

        /// Add the reward token to the reward distributor.
        _addRewardToken(rewardDistributor);

        /// Set ClaimHelper as claimer.
        ISDLiquidityGauge(rewardDistributor).set_claimer(CLAIM_HELPER);

        /// Transfer ownership of the reward distributor to the strategy.
        ISDLiquidityGauge(rewardDistributor).commit_transfer_ownership(address(strategy));

        /// Accept ownership of the reward distributor.
        strategy.acceptRewardDistributorOwnership(rewardDistributor);

        /// Add extra rewards if any.
        _addExtraRewards(_gauge);

        emit PoolDeployed(vault, rewardDistributor, lp, _gauge);
    }

    /// @notice Add the main reward token to the reward distributor.
    /// @param rewardDistributor Address of the reward distributor.
    function _addRewardToken(address rewardDistributor) internal virtual {
        /// The strategy should claim through the locker the reward token,
        /// and distribute it to the reward distributor every harvest.
        ISDLiquidityGauge(rewardDistributor).add_reward(rewardToken, address(strategy));
    }

    /// @notice Add extra reward tokens to the reward distributor.
    /// @param _gauge Address of the liquidity gauge.
    function _addExtraRewards(address _gauge) internal virtual {
        /// Check if the gauge supports extra rewards.
        /// This function is not supported on all gauges, depending on when they were deployed.
        bytes memory data = abi.encodeWithSignature("reward_tokens(uint256)", 0);

        /// Hence the call to the function is wrapped in a try catch.
        (bool success,) = _gauge.call(data);
        if (!success) {
            /// If it fails, we set the LGtype to 1 to indicate that the gauge doesn't support extra rewards.
            /// So the harvest would skip the extra rewards.
            strategy.setLGtype(_gauge, 1);

            return;
        }

        /// Loop through the extra reward tokens.
        /// 8 is the maximum number of extra reward tokens supported by the gauges.
        for (uint8 i = 0; i < 8;) {
            /// Get the extra reward token address.
            address _extraRewardToken = ISDLiquidityGauge(_gauge).reward_tokens(i);

            /// If the address is 0, it means there are no more extra reward tokens.
            if (_extraRewardToken == address(0)) break;

            /// Performs checks on the extra reward token.
            /// Checks like if the token is also an lp token that can be staked in the locker, these tokens are not supported.
            if (_isValidToken(_extraRewardToken)) {
                /// Then we add the extra reward token to the reward distributor through the strategy.
                strategy.addRewardToken(_gauge, _extraRewardToken);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Perform checks on the gauge to make sure it's valid and can be used.
    /// @param _gauge Address of the liquidity gauge.
    function _isValidGauge(address _gauge) internal view virtual returns (bool) {}

    /// @notice Perform checks on the token to make sure it's valid and can be used.
    /// @param _token Address of the token.
    function _isValidToken(address _token) internal view virtual returns (bool) {}

    /// @notice Retrieve the staking token from the gauge.
    /// @param _gauge Address of the liquidity gauge.
    function _getGaugeStakingToken(address _gauge) internal view virtual returns (address lp) {
        lp = ILiquidityGauge(_gauge).lp_token();
    }

    /// @notice Retrieve the name and symbol of the staking token.
    /// @param _lp Address of the staking token.
    function _getNameAndSymbol(address _lp) internal view virtual returns (string memory name, string memory symbol) {
        name = ERC20(_lp).name();
        symbol = ERC20(_lp).symbol();
    }
}
