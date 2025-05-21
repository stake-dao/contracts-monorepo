// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {VoterPermissionManager} from "src/voters/utils/VoterPermissionManager.sol";

interface IVoter {
    function voteGauges(address[] calldata _gauges, uint256[] calldata _weights) external;
    function setPermission(address _address, VoterPermissionManager.Permission _permission) external;
    function setPermissions(address[] calldata _addresses, VoterPermissionManager.Permission[] calldata _permissions)
        external;
    function getPermission(address _address) external view returns (VoterPermissionManager.Permission);
    function getPermissionLabel(address _address) external view returns (string memory);
}
