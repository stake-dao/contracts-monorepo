/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/extensions/RewardDistributor.sol";

contract Vault is RewardDistributor {
    constructor(address asset) RewardDistributor(asset) {}
}
