// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IBooster} from "@interfaces/convex/IBooster.sol";
import {IBaseRewardPool} from "@interfaces/convex/IBaseRewardPool.sol";
import {IStashTokenWrapper} from "@interfaces/convex/IStashTokenWrapper.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "src/interfaces/ISidecar.sol";

/// @notice Sidecar for Convex.
/// @dev For each PID, a minimal proxy is deployed using this contract as implementation.
contract ConvexSidecar is ISidecar {
    using Math for uint256;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice The protocol ID.
    bytes4 public constant PROTOCOL_ID = bytes4(keccak256("CURVE"));

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error emitted when caller is not strategy
    error OnlyStrategy();

    /// @notice Error emitted when caller is not accountant
    error OnlyAccountant();

    /// @notice Error emitted when contract is not initialized
    error AlreadyInitialized();

    //////////////////////////////////////////////////////
    /// --- ISIDECAR IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Address of the Minimal Proxy Factory.
    function factory() public view returns (ISidecarFactory _factory) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        address factoryAddress;
        assembly {
            factoryAddress := mload(add(args, 20))
        }
        return ISidecarFactory(factoryAddress);
    }

    /// @notice Protocol controller address.
    function protocolController() public view returns (IProtocolController _protocolController) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _protocolController := mload(add(args, 40))
        }
    }

    function accountant() public view returns (address _accountant) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _accountant := mload(add(args, 80))
        }
    }

    /// @notice Staking token address.
    function asset() public view returns (IERC20 _asset) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _asset := mload(add(args, 60))
        }
    }

    /// @notice Reward token address.
    function rewardToken() public view returns (IERC20 _rewardToken) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _rewardToken := mload(add(args, 80))
        }
    }

    function rewardReceiver() public view returns (address _rewardReceiver) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _rewardReceiver := mload(add(args, 100))
        }
    }

    //////////////////////////////////////////////////////
    /// --- CONVEX IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Convex Reward Token address.
    function CVX() public view returns (IERC20 _cvx) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _cvx := mload(add(args, 100))
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
        require(msg.sender == protocolController().strategy(PROTOCOL_ID), OnlyStrategy());
        _;
    }

    modifier onlyAccountant() {
        require(msg.sender == accountant(), OnlyAccountant());
        _;
    }

    /// @notice Initialize the contract by approving the ConvexCurve booster to spend the LP token.
    function initialize() external {
        require(asset().allowance(address(this), address(booster())) == 0, AlreadyInitialized());

        asset().safeIncreaseAllowance(address(booster()), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- ISIDECAR OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Deposit LP token into Convex.
    /// @param amount Amount of LP token to deposit.
    /// @dev The reason there's an empty address parameter is to keep flexibility for future implementations.
    /// Not all fallbacks will be minimal proxies, so we need to keep the same function signature.
    /// Only callable by the strategy.
    function deposit(uint256 amount) external onlyStrategy {
        /// Deposit the LP token into Convex and stake it (true) to receive rewards.
        booster().deposit(pid(), amount, true);
    }

    /// @notice Withdraw LP token from Convex.
    /// @param amount Amount of LP token to withdraw.
    /// @param receiver Address to receive the LP token.
    /// Only callable by the strategy.
    function withdraw(uint256 amount, address receiver) external onlyStrategy {
        /// Withdraw from Convex gauge without claiming rewards (false).
        baseRewardPool().withdrawAndUnwrap(amount, false);

        /// Send the LP token to the receiver.
        asset().safeTransfer(receiver, amount);
    }

    /// @notice Claim rewards from Convex.
    /// @return rewardTokenAmount Amount of reward token claimed.
    function claim() external onlyAccountant returns (uint256 rewardTokenAmount) {
        /// Claim rewardToken.
        baseRewardPool().getReward(address(this), false);

        rewardTokenAmount = rewardToken().balanceOf(address(this));

        /// Send the reward token to the accountant.
        rewardToken().safeTransfer(msg.sender, rewardTokenAmount);
    }

    /// @notice Get the balance of the LP token on Convex held by this contract.
    function balanceOf() public view returns (uint256) {
        return baseRewardPool().balanceOf(address(this));
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

    /// @notice Get the amount of reward token earned by the strategy.
    /// @return The amount of reward token earned by the strategy.
    function getPendingRewards() public view returns (uint256) {
        return baseRewardPool().earned(address(this)) + rewardToken().balanceOf(address(this));
    }

    //////////////////////////////////////////////////////
    /// --- CONVEX OPERATIONS
    //////////////////////////////////////////////////////

    function claimExtraRewards() external {
        address[] memory extraRewardTokens = getRewardTokens();

        /// We can save gas by not claiming extra rewards if we don't need them, there's no extra rewards, or not enough rewards worth to claim.
        if (extraRewardTokens.length > 0) {
            baseRewardPool().getReward(address(this), true);
        }

        /// It'll claim rewardToken but we'll leave it here for clarity until the claim() function is called by the strategy.
        baseRewardPool().getReward(address(this), true);

        /// Send the reward token to the reward receiver.
        CVX().safeTransfer(rewardReceiver(), CVX().balanceOf(address(this)));

        /// Handle the extra reward tokens.
        for (uint256 i = 0; i < extraRewardTokens.length;) {
            uint256 _balance = IERC20(extraRewardTokens[i]).balanceOf(address(this));
            if (_balance > 0) {
                /// Send the whole balance to the strategy.
                IERC20(extraRewardTokens[i]).safeTransfer(rewardReceiver(), _balance);
            }

            unchecked {
                ++i;
            }
        }
    }
}
