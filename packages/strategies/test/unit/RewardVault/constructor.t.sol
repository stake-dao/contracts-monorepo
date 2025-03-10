pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__constructor is RewardVaultBaseTest {
    function test_RevertIfAccountantIsZeroAddress() external {
        // it revert if accountant is zero address
    }

    function test_RevertIfProtocolControllerIsZeroAddress() external {
        // it revert if protocolController is zero address
    }

    function test_SetProtocolId() external {
        // it set protocolId
    }

    function test_SetAccountant() external {
        // it set accountant
    }

    function test_SetProtocolController() external {
        // it set protocolController
    }

    function test_Mint0SharesToItself() external {
        // it mint 0 shares to itself
    }

    function test_SetERC20Metadata() external {
        // it set ERC20 metadata
    }
}
