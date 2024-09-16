// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {IUrdFactory} from "src/interfaces/morpho/IUrdFactory.sol";
import {IUniversalRewardsDistributor} from "src/interfaces/morpho/IUniversalRewardsDistributor.sol";

import {EventsLib} from "src/utils/EventsLib.sol";

import {UniversalRewardsDistributor} from "src/distributors/UniversalRewardDistributor.sol";

/// @title Universal Rewards Distributor Factory
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice This contract allows to create UniversalRewardsDistributor (URD) contracts, and to index them easily.
contract UrdFactory is IUrdFactory {
    /* STORAGE */

    mapping(address => bool) public isUrd;

    /* EXTERNAL */

    /// @inheritdoc IUrdFactory
    function createUrd(
        address initialOwner,
        uint256 initialTimelock,
        bytes32 initialRoot,
        bytes32 initialIpfsHash,
        bytes32 salt
    ) public returns (IUniversalRewardsDistributor urd) {
        urd = IUniversalRewardsDistributor(
            address(
                new UniversalRewardsDistributor{salt: salt}(initialOwner, initialTimelock, initialRoot, initialIpfsHash)
            )
        );

        isUrd[address(urd)] = true;

        emit EventsLib.UrdCreated(
            address(urd), msg.sender, initialOwner, initialTimelock, initialRoot, initialIpfsHash, salt
        );
    }
}
