pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {RewardVault} from "src/RewardVault.sol";
import {stdStorage, StdStorage} from "forge-std/src/Test.sol";

// Exposes the useful internal functions of the RewardVault contract for testing purposes
contract RewardVaultHarness is RewardVault, Test {
    // using stdStorage for StdStorage;

    constructor(bytes4 protocolId, address protocolController, address accountant)
        RewardVault(protocolId, protocolController, accountant)
    {}

    // utility function to override the protocolFeesAccrued storage slot by hand
    // (keep the test unitarian and avoid calling the flow to set it as expected by code)
    function _cheat_override_reward_tokens(address[] calldata tokens) external {
        for (uint256 i; i < tokens.length; i++) {
            rewardTokens.push(tokens[i]);
            isRewardToken[tokens[i]] = true;
        }
    }

    function _cheat_override_reward_data(address rewardToken, RewardVault.RewardData calldata _rewardData) external {
        rewardData[rewardToken] = _rewardData;
    }

    function _cheat_override_account_data(
        address account,
        address rewardToken,
        RewardVault.AccountData calldata _accountData
    ) external {
        accountData[account][rewardToken] = _accountData;
    }

    function _expose_MAX_REWARD_TOKEN_COUNT() external view returns (uint256) {
        return MAX_REWARD_TOKEN_COUNT;
    }
}
