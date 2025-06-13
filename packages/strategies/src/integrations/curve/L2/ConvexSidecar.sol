// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {console} from "forge-std/src/console.sol";

import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {IL2BaseRewardPool} from "@interfaces/convex/IL2BaseRewardPool.sol";
import {IStashTokenWrapper} from "@interfaces/convex/IStashTokenWrapper.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CurveProtocol} from "address-book/src/CurveEthereum.sol";
import {ImmutableArgsParser} from "src/libraries/ImmutableArgsParser.sol";
import {Sidecar} from "src/Sidecar.sol";

/// @notice Sidecar for Convex.
/// @dev For each PID, a minimal proxy is deployed using this contract as implementation.
contract ConvexSidecar is Sidecar {
    using SafeERC20 for IERC20;
    using ImmutableArgsParser for address;

    /// @notice The bytes4 ID of the Curve protocol
    /// @dev Used to identify the Curve protocol in the registry
    bytes4 private constant CURVE_PROTOCOL_ID = bytes4(keccak256("CURVE"));

    //////////////////////////////////////////////////////
    // ---  IMPLEMENTATION CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice Convex Reward Token address.
    IERC20 public immutable CVX;

    /// @notice Convex Booster address.
    address public immutable BOOSTER;

    //////////////////////////////////////////////////////
    // --- ISIDECAR CLONE IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Staking token address.
    function asset() public view override returns (IERC20 _asset) {
        return IERC20(address(this).readAddress(0));
    }

    function rewardReceiver() public view override returns (address _rewardReceiver) {
        return address(this).readAddress(20);
    }

    //////////////////////////////////////////////////////
    // --- CONVEX CLONE IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Staking Convex LP contract address.
    function baseRewardPool() public view returns (IL2BaseRewardPool _baseRewardPool) {
        return IL2BaseRewardPool(address(this).readAddress(40));
    }

    /// @notice Identifier of the pool on Convex.
    function pid() public view returns (uint256 _pid) {
        return address(this).readUint256(60);
    }

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor(address _accountant, address _protocolController, address _cvx, address _booster)
        Sidecar(CURVE_PROTOCOL_ID, _accountant, _protocolController)
    {
        CVX = IERC20(_cvx);
        BOOSTER = _booster;
    }

    //////////////////////////////////////////////////////
    // --- INITIALIZATION
    //////////////////////////////////////////////////////

    /// @notice Initialize the contract by approving the ConvexCurve booster to spend the LP token.
    function _initialize() internal override {
        require(asset().allowance(address(this), address(BOOSTER)) == 0, AlreadyInitialized());

        asset().forceApprove(address(BOOSTER), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    // --- ISIDECAR OPERATIONS OVERRIDE
    //////////////////////////////////////////////////////

    /// @notice Deposit LP token into Convex.
    /// @param amount Amount of LP token to deposit.
    /// @dev The reason there's an empty address parameter is to keep flexibility for future implementations.
    /// Not all fallbacks will be minimal proxies, so we need to keep the same function signature.
    /// Only callable by the strategy.
    function _deposit(uint256 amount) internal override {
        /// Deposit the LP token into Convex.
        IL2Booster(BOOSTER).deposit(pid(), amount);
    }

    /// @notice Withdraw LP token from Convex.
    /// @param amount Amount of LP token to withdraw.
    /// @param receiver Address to receive the LP token.
    function _withdraw(uint256 amount, address receiver) internal override {
        /// Withdraw from Convex gauge without claiming rewards (false).
        baseRewardPool().withdraw(amount, true);

        /// Send the LP token to the receiver.
        asset().safeTransfer(receiver, amount);
    }

    /// @notice Claim rewards from Convex.
    /// @return rewardTokenAmount Amount of reward token claimed.
    function _claim() internal override returns (uint256 rewardTokenAmount) {
        /// Claim rewardToken.
        baseRewardPool().getReward(address(this));

        address[] memory rewardTokens = getRewardTokens();

        for (uint256 i = 0; i < rewardTokens.length;) {
            address rewardToken = rewardTokens[i];
            uint256 _balance = IERC20(rewardToken).balanceOf(address(this));

            if (_balance > 0) {
                if (rewardToken == address(REWARD_TOKEN)) {
                    IERC20(rewardToken).safeTransfer(ACCOUNTANT, _balance);
                } else {
                    /// Send the whole balance to the strategy.
                    IERC20(rewardToken).safeTransfer(rewardReceiver(), _balance);
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get the balance of the LP token on Convex held by this contract.
    function balanceOf() public view override returns (uint256) {
        return baseRewardPool().balanceOf(address(this));
    }

    /// @notice Get the reward tokens from the base reward pool.
    /// @return Array of all extra reward tokens.
    function getRewardTokens() public view override returns (address[] memory) {
        // Check if there is extra rewards
        uint256 extraRewardsLength = baseRewardPool().rewardLength();

        console.log("extraRewardsLength", extraRewardsLength);

        address[] memory tokens = new address[](extraRewardsLength);

        for (uint256 i; i < extraRewardsLength;) {
            IL2BaseRewardPool.RewardType memory reward = baseRewardPool().rewards(i);
            tokens[i] = reward.rewardToken;
            unchecked {
                ++i;
            }
        }

        return tokens;
    }

    /// @notice Get the amount of reward token earned by the strategy.
    /// @return The amount of reward token earned by the strategy.
    function getPendingRewards() public override returns (uint256) {
        return baseRewardPool().earned(address(this)) + REWARD_TOKEN.balanceOf(address(this));
    }
}