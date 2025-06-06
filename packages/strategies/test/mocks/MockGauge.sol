// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "./ERC20Mock.sol";
// IERC20 is already imported by ERC20Mock, so no need to import it again.

/// @title GaugeMock
/// @notice Mock gauge contract for testing vault integrations. Supports staking, unstaking, and reward claiming.
/// @dev This is a dummy implementation for testing purposes. Only use it in unit tests for integration purposes.
contract MockGauge is ERC20Mock {
    /// @notice The token that is staked into the gauge
    address public stakingToken;
    /// @notice The reward token distributed by the gauge
    address public rewardToken;
    /// @notice Mapping of claimable rewards per user
    mapping(address => uint256) public claimableRewards;
    /// @notice Mapping of claimable rewards per user
    mapping(address => address) public rewards_receiver;

    /// @param name_ ERC20 name
    /// @param symbol_ ERC20 symbol
    /// @param decimals_ ERC20 decimals
    /// @param stakingToken_ The token to be staked in the gauge
    constructor(string memory name_, string memory symbol_, uint8 decimals_, address stakingToken_)
        ERC20Mock(name_, symbol_, decimals_)
    {
        stakingToken = stakingToken_;
    }

    /// @notice Stake tokens in the gauge
    /// @dev Transfers stakingToken from msg.sender and mints gauge shares to 'addr'.
    function deposit(uint256 amount, address addr, bool /*claim_rewards*/ ) external {
        IERC20(stakingToken).transferFrom(msg.sender, address(this), amount);
        _mint(addr, amount); // Mint gauge shares (ERC20)
    }

    /// @notice Unstake tokens from the gauge
    /// @dev Burns gauge shares from msg.sender and transfers stakingToken back to msg.sender.
    function withdraw(uint256 amount, bool /*claim_rewards*/ ) external {
        require(ERC20Mock(address(this)).balanceOf(msg.sender) >= amount, "Not enough staked");
        _burn(msg.sender, amount); // Burn gauge shares (ERC20)
        IERC20(stakingToken).transfer(msg.sender, amount);
    }

    /// @notice Claim rewards for a user, sending them to the receiver
    function claim_rewards(address addr, address receiver) external {
        address to =
            receiver == address(0) ? rewards_receiver[addr] == address(0) ? addr : rewards_receiver[addr] : receiver;
        uint256 amount = claimableRewards[addr];
        require(amount > 0, "No rewards");
        claimableRewards[addr] = 0;
        ERC20Mock(rewardToken).mint(to, amount);
    }

    /// @notice Set the rewards receiver
    function set_rewards_receiver(address _receiver) external {
        rewards_receiver[msg.sender] = _receiver;
    }

    /// @notice [TEST ONLY] Set the reward token address
    function cheat_setRewardToken(address _rewardToken) external {
        rewardToken = _rewardToken;
    }

    /// @notice [TEST ONLY] Mint rewards to a user (for testing)
    function cheat_mintRewards(address user, uint256 amount) external {
        claimableRewards[user] += amount;
    }
}
