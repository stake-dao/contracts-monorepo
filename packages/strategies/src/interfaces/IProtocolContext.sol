// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IProtocolController} from "src/interfaces/IProtocolController.sol";

interface IProtocolContext {
    function PROTOCOL_ID() external view returns (bytes4);
    function LOCKER() external view returns (address);
    function GATEWAY() external view returns (address);
    function ACCOUNTANT() external view returns (address);
    function REWARD_TOKEN() external view returns (address);
    function PROTOCOL_CONTROLLER() external view returns (IProtocolController);
}
