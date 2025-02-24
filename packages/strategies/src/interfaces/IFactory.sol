/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IProtocolController {
    function vaults(address) external view returns (address);
}
