// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {StrategyWrapper} from "src/wrappers/StrategyWrapper.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title Stake DAO Restricted Strategy Wrapper
/// @notice Variant of the StrategyWrapper that only allows the admin to transfer the wrapped tokens.
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
/// @custom:github https://github.com/stake-dao/contracts-monorepo
contract RestrictedStrategyWrapper is StrategyWrapper {
    ///////////////////////////////////////////////////////////////
    // --- STATE
    ///////////////////////////////////////////////////////////////

    /// @notice The sole address that can transfer the wrapped tokens
    address public admin;

    /// @dev Thrown when non-admin tries to transfer wrapped tokens
    error OnlyAdmin();

    /// @param rewardVault The reward vault contract
    /// @param _admin The address of the admin
    /// @custom:reverts ZeroAddress if the reward vault or _admin address is the zero address
    constructor(IRewardVault rewardVault, address _admin) StrategyWrapper(rewardVault) {
        require(_admin != address(0), ZeroAddress());

        admin = _admin;
    }

    ///////////////////////////////////////////////////////////////
    // --- ADMIN FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Sets the admin address
    /// @param newAdmin The new admin address
    /// @custom:reverts ZeroAddress if the new admin address is the zero address
    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), ZeroAddress());
        admin = newAdmin;
    }

    ///////////////////////////////////////////////////////////////
    // --- ERC-20 OVERRIDEN FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @dev Only admin can transfer the wrapped tokens. The token isn't liquid.
    /// @param to The address to transfer the tokens to
    /// @param amount The amount of tokens to transfer
    /// @return True if the transfer is successful
    /// @custom:reverts OnlyAdmin if the sender is not admin
    function transfer(address to, uint256 amount) public virtual override(IERC20, ERC20) returns (bool) {
        require(msg.sender == admin, OnlyAdmin());
        return super.transfer(to, amount);
    }

    /// @dev Only admin can transfer the wrapped tokens. The token isn't liquid.
    /// @param from The address to transfer the tokens from
    /// @param to The address to transfer the tokens to
    /// @param amount The amount of tokens to transfer
    /// @return True if the transfer is successful
    /// @custom:reverts OnlyAdmin if the sender is not admin
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override(IERC20, ERC20)
        returns (bool)
    {
        require(msg.sender == admin, OnlyAdmin());
        return super.transferFrom(from, to, amount);
    }
}
