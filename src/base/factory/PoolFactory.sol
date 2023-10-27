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
    function create(address _gauge) public virtual returns (address vault, address rewardDistributor) {
        // check if the gauge is valid
        if (!_isValidGauge(_gauge)) revert INVALID_GAUGE();
        // check if the lp has been already used to clone a vault
        if (strategy.rewardDistributors(_gauge) != address(0)) revert GAUGE_ALREADY_USED();

        address lp = _getGaugeStakingToken(_gauge);

        /// Clone the liquidity gauge.
        rewardDistributor = LibClone.clone(liquidityGaugeImplementation);

        /// Clone the vault.
        bytes32 salt = keccak256(abi.encodePacked(lp, _gauge));
        bytes memory vaultData = abi.encodePacked(lp, address(strategy), rewardDistributor);

        vault = vaultImplementation.cloneDeterministic(vaultData, salt);

        /// Initialize RewardDistributor.
        (, string memory _symbol) = _getNameAndSymbol(lp);
        ISDLiquidityGauge(rewardDistributor).initialize(
            vault, address(this), SDT, VESDT, VE_BOOST_PROXY, SDT_DISTRIBUTOR, vault, _symbol
        );

        /// Initialize Vault.
        IStrategyVault(vault).initialize();

        /// Initialize vault and reward distributor in strategy.
        strategy.toggleVault(vault);
        strategy.setGauge(lp, _gauge);
        strategy.setRewardDistributor(_gauge, rewardDistributor);

        /// We first add the reward token.
        _addRewardToken(rewardDistributor);

        /// Set ClaimHelper as claimer.
        ISDLiquidityGauge(rewardDistributor).set_claimer(CLAIM_HELPER);

        /// Transfer ownership of the reward distributor to the strategy.
        ISDLiquidityGauge(rewardDistributor).commit_transfer_ownership(address(strategy));

        /// Accept ownership of the reward distributor.
        strategy.acceptRewardDistributorOwnership(rewardDistributor);

        /// Add extra rewards.
        _addExtraRewards(_gauge);

        emit PoolDeployed(vault, rewardDistributor, lp, _gauge);
    }

    function _addRewardToken(address rewardDistributor) internal virtual {
        ISDLiquidityGauge(rewardDistributor).add_reward(rewardToken, address(strategy));
    }

    function _addExtraRewards(address _gauge) internal virtual {
        // view function called only to recognize the gauge type
        bytes memory data = abi.encodeWithSignature("reward_tokens(uint256)", 0);
        (bool success,) = _gauge.call(data);
        if (!success) {
            /// Means that the gauge doesn't support extra rewards.
            strategy.setLGtype(_gauge, 1);

            return;
        }

        for (uint8 i = 0; i < 8;) {
            // Get reward token
            address _extraRewardToken = ISDLiquidityGauge(_gauge).reward_tokens(i);
            if (_extraRewardToken == address(0)) break;

            if (_isValidToken(_extraRewardToken)) {
                strategy.addRewardToken(_gauge, _extraRewardToken);
            }

            unchecked {
                ++i;
            }
        }
    }

    function _isValidGauge(address _gauge) internal view virtual returns (bool) {}

    function _isValidToken(address _token) internal view virtual returns (bool) {}

    function _getGaugeStakingToken(address _gauge) internal view virtual returns (address lp) {
        lp = ILiquidityGauge(_gauge).lp_token();
    }

    function _getNameAndSymbol(address _lp) internal view virtual returns (string memory name, string memory symbol) {
        name = ERC20(_lp).name();
        symbol = ERC20(_lp).symbol();
    }
}
