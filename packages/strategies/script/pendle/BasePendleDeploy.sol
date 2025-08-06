// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "script/BaseDeploy.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {PendleFactory} from "src/integrations/pendle/PendleFactory.sol";
import {PendleStrategy} from "src/integrations/pendle/PendleStrategy.sol";
import {PendleAllocator} from "src/integrations/pendle/PendleAllocator.sol";

/// @title BasePendleDeploy - Base deployment script for Pendle protocol on any chain with Convex.
abstract contract BasePendleDeploy is BaseDeploy {
    bytes4 internal constant PROTOCOL_ID = bytes4(keccak256("PENDLE"));

    /// @notice Base configuration for the test.
    struct BaseConfig {
        string chain;
        address locker;
        address rewardToken;
        IStrategy.HarvestPolicy harvestPolicy;
        address oldStrategy;
        address gaugeController;
    }

    /// @notice Combined configuration for the test.
    struct Config {
        BaseConfig base;
    }

    /// @notice The configuration for the test.
    Config public config;

    constructor(Config memory _config) {
        config = _config;
    }

    function run()
        public
        virtual
        doSetup(config.base.chain, config.base.rewardToken, config.base.locker, PROTOCOL_ID, config.base.harvestPolicy)
    {
        bool isL2 = block.chainid != 1;

        // 1. Deploy the Pendle Strategy contract.
        strategy = address(
            _deployWithCreate3(
                type(PendleStrategy).name,
                abi.encodePacked(
                    type(PendleStrategy).creationCode,
                    abi.encode(address(protocolController), config.base.locker, address(gateway))
                )
            )
        );

        // 2. Deploy the PendleAllocator contract.
        allocator = PendleAllocator(
            _deployWithCreate3(
                type(PendleAllocator).name,
                abi.encodePacked(type(PendleAllocator).creationCode, abi.encode(config.base.locker, address(gateway)))
            )
        );

        // 3. Deploy Reward Receiver Implementation.
        rewardReceiverImplementation = RewardReceiver(
            _deployWithCreate3(type(RewardReceiver).name, abi.encodePacked(type(RewardReceiver).creationCode))
        );

        // 4. Deploy Pendle Factory.
        bytes memory factoryParams = abi.encode(
            config.base.gaugeController,
            config.base.oldStrategy,
            address(protocolController),
            address(rewardVaultImplementation),
            address(rewardReceiverImplementation),
            config.base.locker,
            address(gateway)
        );
        factory = address(
            _deployWithCreate3(
                type(PendleFactory).name, abi.encodePacked(type(PendleFactory).creationCode, factoryParams)
            )
        );

        // 5. Set protocol fee to 17%
        accountant.setProtocolFeePercent(0.17e18);

        // 6. Set harvest fee to 0% on L2
        if (isL2) accountant.setHarvestFeePercent(0);
    }

    /// @notice After setup, create vaults for all gauges.
    function _afterSetup() internal override {
        super._afterSetup();

        address[] memory gauges = getGauges();
        uint256 length = gauges.length;
        for (uint256 i; i < length; i++) {
            PendleFactory(factory).createVault(gauges[i]);
        }
    }

    /// @notice Get the gauges to create vaults for.
    function getGauges() internal virtual returns (address[] memory);
}
