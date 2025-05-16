// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Script} from "forge-std/src/Script.sol";
import {ConvexLockerRecipient} from "src/common/fee/ConvexLockerRecipient.sol";
import {StakeDaoLockerRecipient} from "src/common/fee/StakeDaoLockerRecipient.sol";
import {VlCVXDelegatorsRecipient} from "src/common/fee/vlCVXDelegatorsRecipient.sol";
import {Common} from "address-book/src/CommonEthereum.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32, bytes memory) external;
}

contract Deployer is Script {
    ConvexLockerRecipient public convexLockerRecipient;
    VlCVXDelegatorsRecipient public vlCVXDelegatorsRecipient;
    StakeDaoLockerRecipient public stakeDaoLockerRecipient;

    function run() public {
        /*
        bytes32 initCodeHash = hashInitCode(type(StakeDaoLockerRecipient).creationCode, abi.encode(msg.sender));
        console.logBytes32(initCodeHash);
        */
        vm.startBroadcast();

        ImmutableCreate2Factory factory = ImmutableCreate2Factory(Common.CREATE2_FACTORY);

        address payable expectedAddress = payable(0x0000000014814b037cF4a091FE00cbA2DeFc6115); // Modify this
        bytes32 salt = bytes32(0x8898502ba35ab64b3562abc509befb7eb178d4dffc1775429a38950195cfd166); // Modify this

        factory.safeCreate2(salt, abi.encodePacked(type(StakeDaoLockerRecipient).creationCode, abi.encode(msg.sender)));

        StakeDaoLockerRecipient(expectedAddress).allowAddress(DAO.ALL_MIGHT);
        // ConvexLockerRecipient(expectedAddress).transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}
