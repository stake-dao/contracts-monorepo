// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// From @interfaces package.
import {IBooster} from "@interfaces/convex/IBooster.sol";
import {IBaseRewardPool} from "@interfaces/convex/IBaseRewardPool.sol";
import {IStashTokenWrapper} from "@interfaces/convex/IStashTokenWrapper.sol";

/// From @openzeppelin/contracts.
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// From src/interfaces.
import {ISidecarFactory} from "src/interfaces/ISidecarFactory.sol";

/// @notice Sidecar for Convex.
/// @dev For each PID, a minimal proxy is deployed using this contract as implementation.
contract ConvexSidecar {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice The protocol ID.
    bytes4 public constant PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice Error emitted when contract is not initialized
    error FACTORY();

    /// @notice Error emitted when caller is not strategy
    error STRATEGY();

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Address of the Minimal Proxy Factory.
    /// @dev The protocol fee value is stored in the factory in order to easily update it for all the pools.
    function factory() public view returns (ISidecarFactory _factory) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        address factoryAddress;
        assembly {
            factoryAddress := mload(add(args, 20))
        }
        return ISidecarFactory(factoryAddress);
    }

    /// @notice Staking token address.
    function token() public view returns (IERC20 _token) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _token := mload(add(args, 40))
        }
    }

    /// @notice Reward token address.
    function rewardToken() public view returns (IERC20 _rewardToken) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _rewardToken := mload(add(args, 60))
        }
    }

    /// @notice Convex Reward Token address.
    function secondaryRewardToken() public view returns (IERC20 _fallbackRewardToken) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _fallbackRewardToken := mload(add(args, 80))
        }
    }

    /// @notice Strategy address.
    function strategy() public view returns (address _strategy) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _strategy := mload(add(args, 100))
        }
    }

    /// @notice Convex Entry point contract.
    function booster() public view returns (IBooster _booster) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        address boosterAddress;
        assembly {
            boosterAddress := mload(add(args, 120))
        }
        return IBooster(boosterAddress);
    }

    /// @notice Staking Convex LP contract address.
    function baseRewardPool() public view returns (IBaseRewardPool _baseRewardPool) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        address baseRewardPoolAddress;
        assembly {
            baseRewardPoolAddress := mload(add(args, 140))
        }
        return IBaseRewardPool(baseRewardPoolAddress);
    }

    /// @notice Identifier of the pool on Convex.
    function pid() public view returns (uint256 _pid) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _pid := mload(add(args, 160))
        }
    }

    //////////////////////////////////////////////////////
    /// --- MODIFIERS & INITIALIZATION
    //////////////////////////////////////////////////////

    modifier onlyStrategy() {
        if (msg.sender != strategy()) revert STRATEGY();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != address(factory())) revert FACTORY();
        _;
    }

    /// @notice Initialize the contract by approving the ConvexCurve booster to spend the LP token.
    function initialize() external onlyFactory {
        token().safeIncreaseAllowance(address(booster()), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- DEPOSIT/WITHDRAW/CLAIM
    //////////////////////////////////////////////////////

    /// @notice Deposit LP token into Convex.
    /// @param amount Amount of LP token to deposit.
    /// @dev The reason there's an empty address parameter is to keep flexibility for future implementations.
    /// Not all fallbacks will be minimal proxies, so we need to keep the same function signature.
    /// Only callable by the strategy.
    function deposit(address, uint256 amount) external onlyStrategy {
        /// Deposit the LP token into Convex and stake it (true) to receive rewards.
        booster().deposit(pid(), amount, true);
    }

    /// @notice Withdraw LP token from Convex.
    /// @param amount Amount of LP token to withdraw.
    /// Only callable by the strategy.
    function withdraw(address, uint256 amount) external onlyStrategy {
        /// Withdraw from Convex gauge without claiming rewards (false).
        baseRewardPool().withdrawAndUnwrap(amount, false);

        /// Send the LP token to the strategy.
        token().safeTransfer(msg.sender, amount);
    }

    /// @notice Claim rewards from Convex.
    /// @param _claimExtraRewards If true, claim extra rewards.
    /// @return rewardTokenAmount Amount of reward token claimed.
    function claim(bool _claimExtraRewards) external onlyStrategy returns (uint256 rewardTokenAmount) {
        address[] memory extraRewardTokens;

        /// We can save gas by not claiming extra rewards if we don't need them, there's no extra rewards, or not enough rewards worth to claim.
        if (_claimExtraRewards) {
            extraRewardTokens = getRewardTokens();
        }

        /// Claim rewardToken, secondaryRewardToken and _extraRewardTokens if _claimExtraRewards is true.
        baseRewardPool().getReward(address(this), _claimExtraRewards);

        rewardTokenAmount = rewardToken().balanceOf(address(this));

        /// Send the reward token to the strategy.
        rewardToken().safeTransfer(msg.sender, rewardTokenAmount);

        /// TODO: Send to Reward Receiver or Treasury.
        /// secondaryRewardToken().safeTransfer(msg.sender, fallbackRewardTokenAmount);

        /// Handle the extra reward tokens.
        for (uint256 i = 0; i < extraRewardTokens.length;) {
            uint256 _balance = IERC20(extraRewardTokens[i]).balanceOf(address(this));
            if (_balance > 0) {
                /// Send the whole balance to the strategy.
                IERC20(extraRewardTokens[i]).safeTransfer(msg.sender, _balance);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get the reward tokens from the base reward pool.
    /// @return Array of all extra reward tokens.
    function getRewardTokens() public view returns (address[] memory) {
        // Check if there is extra rewards
        uint256 extraRewardsLength = baseRewardPool().extraRewardsLength();

        address[] memory tokens = new address[](extraRewardsLength);

        address _token;
        for (uint256 i; i < extraRewardsLength;) {
            /// Get the address of the virtual balance pool.
            _token = baseRewardPool().extraRewards(i);

            /// For PIDs greater than 150, the virtual balance pool also has a wrapper.
            /// So we need to get the token from the wrapper.
            /// More: https://docs.convexfinance.com/convexfinanceintegration/baserewardpool
            if (pid() >= 151) {
                address wrapper = IBaseRewardPool(_token).rewardToken();
                tokens[i] = IStashTokenWrapper(wrapper).token();
            } else {
                tokens[i] = IBaseRewardPool(_token).rewardToken();
            }

            unchecked {
                ++i;
            }
        }

        return tokens;
    }

    /// @notice Get the balance of the LP token on Convex held by this contract.
    function balanceOf() public view returns (uint256) {
        return baseRewardPool().balanceOf(address(this));
    }
}
