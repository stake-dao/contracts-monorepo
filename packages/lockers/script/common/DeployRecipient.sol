// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/fee/ConvexLockerRecipient.sol";
import {VlCVXDelegatorsRecipient} from "src/common/fee/vlCVXDelegatorsRecipient.sol";
import "src/common/fee/StakeDaoLockerRecipient.sol";
import "forge-std/src/Script.sol";
import "forge-std/src/console.sol";
import "forge-std/src/Script.sol";
import "src/common/fee/ConvexLockerRecipient.sol";
import "src/common/fee/StakeDaoLockerRecipient.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32, bytes memory) external;
}

contract Deployer is Script {
    ConvexLockerRecipient public convexLockerRecipient;
    VlCVXDelegatorsRecipient public vlCVXDelegatorsRecipient;
    StakeDaoLockerRecipient public stakeDaoLockerRecipient;
    address internal constant DEPLOYER = address(0x8898502BA35AB64b3562aBC509Befb7Eb178D4df);
    address internal constant ALL_MIGHT = address(0x0000000a3Fc396B89e4c11841B39D9dff85a5D05);

    function run() public {
        /*
        bytes32 initCodeHash = hashInitCode(type(StakeDaoLockerRecipient).creationCode, abi.encode(DEPLOYER));
        console.logBytes32(initCodeHash);
        */
        vm.startBroadcast(0x8898502BA35AB64b3562aBC509Befb7Eb178D4df);

        ImmutableCreate2Factory factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

        address payable expectedAddress = payable(0x0000000014814b037cF4a091FE00cbA2DeFc6115); // Modify this
        bytes32 salt = bytes32(0x8898502ba35ab64b3562abc509befb7eb178d4dffc1775429a38950195cfd166); // Modify this

        factory.safeCreate2(salt, abi.encodePacked(type(StakeDaoLockerRecipient).creationCode, abi.encode(DEPLOYER)));

        StakeDaoLockerRecipient(expectedAddress).allowAddress(ALL_MIGHT);
        // ConvexLockerRecipient(expectedAddress).transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}
