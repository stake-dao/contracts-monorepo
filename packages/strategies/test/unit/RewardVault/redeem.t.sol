pragma solidity 0.8.28;

import {RewardVault__withdraw} from "test/unit/RewardVault/withdraw.t.sol";

contract RewardVault__redeem is RewardVault__withdraw {
    // Due to the 1:1 relationship of the assets and the shares, the withdraw and the redeem functions
    // do the same thing. This function is a wrapper that calls the appropriate function based on the context
    // of the test. By inheriting from the `RewardVault__withdraw` test, we can use the same logic for both tests.
    function withdraw_redeem_wrapper(uint256 shares, address receiver, address owner)
        internal
        override
        returns (uint256)
    {
        return cloneRewardVault.redeem(shares, receiver, owner);
    }

    function test_ActsLikeWithdraw() external {
        // don't need to test anything, we're using the same logic as the withdraw test
        // keep this function for clarity and check using bulloak
    }
}
