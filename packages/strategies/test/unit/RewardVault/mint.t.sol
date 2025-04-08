pragma solidity 0.8.28;

import {RewardVault__deposit} from "test/unit/RewardVault/deposit.t.sol";

contract RewardVault__mint is RewardVault__deposit {
    // Due to the 1:1 relationship of the assets and the shares, the deposit and the mint functions
    // do the same thing. This function is a wrapper that calls the appropriate function based on the context
    // of the test. By inheriting from the `RewardVault__deposit` test, we can use the same logic for both tests.
    function deposit_mint_wrapper(uint256 shares, address receiver) internal override returns (uint256) {
        return cloneRewardVault.mint(shares, receiver);
    }

    function deposit_mint_permissioned_wrapper(address account, uint256 shares) internal override returns (uint256) {
        return cloneRewardVault.mint(account, shares);
    }

    function test_ActsLikeDeposit() external {
        // don't need to test anything, we're using the same logic as the deposit test
        // keep this function for clarity and check using bulloak
    }
}
