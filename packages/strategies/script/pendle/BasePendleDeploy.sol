// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "script/BaseDeploy.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";

// import {CurveFactoryL2} from "src/integrations/curve/L2/CurveFactoryL2.sol";
// import {CurveStrategyL2} from "src/integrations/curve/L2/CurveStrategyL2.sol";

// import {RewardReceiverL2} from "src/RewardReceiverL2.sol";
// import {ConvexSidecarL2} from "src/integrations/curve/L2/ConvexSidecarL2.sol";
// import {ConvexSidecarFactoryL2} from "src/integrations/curve/L2/ConvexSidecarFactoryL2.sol";

// import {CurveFactory} from "src/integrations/curve/CurveFactory.sol";
// import {CurveStrategy} from "src/integrations/curve/CurveStrategy.sol";
// import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
// import {ConvexSidecarFactory} from "src/integrations/curve/ConvexSidecarFactory.sol";

import {RewardReceiver} from "src/RewardReceiver.sol";
import {RewardReceiverL2} from "src/RewardReceiverL2.sol";

import {PendleFactory} from "src/integrations/pendle/PendleFactory.sol";
import {PendleStrategy} from "src/integrations/pendle/PendleStrategy.sol";
import {PendleAllocator} from "src/integrations/pendle/PendleAllocator.sol";

// TODO: Check if L2 contracts are needed
contract PendleFactoryL2 is PendleFactory {}

// TODO: Check if L2 contracts are needed
contract PendleStrategyL2 is PendleStrategy {}

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

        /// 2. Deploy the Pendle Strategy contract.
        strategy = address(
            _deployWithCreate3(
                isL2 ? type(PendleStrategyL2).name : type(PendleStrategy).name,
                abi.encodePacked(
                    isL2 ? type(PendleStrategyL2).creationCode : type(PendleStrategy).creationCode,
                    abi.encode(address(protocolController), config.base.locker, address(gateway))
                )
            )
        );

        /// 3. Check if the strategy is only boost.
        // if (config.convex.isOnlyBoost) {
        //     /// 3a. Deploy the Convex Sidecar implementation.
        //     sidecarImplementation = address(
        //         _deployWithCreate3(
        //             isL2 ? type(ConvexSidecarL2).name : type(ConvexSidecar).name,
        //             abi.encodePacked(
        //                 isL2 ? type(ConvexSidecarL2).creationCode : type(ConvexSidecar).creationCode,
        //                 abi.encode(
        //                     address(accountant), address(protocolController), config.convex.cvx, config.convex.booster
        //                 )
        //             )
        //         )
        //     );

        //     /// 3b. Deploy the Convex Sidecar factory.
        //     sidecarFactory = address(
        //         _deployWithCreate3(
        //             isL2 ? type(ConvexSidecarFactoryL2).name : type(ConvexSidecarFactory).name,
        //             abi.encodePacked(
        //                 isL2 ? type(ConvexSidecarFactoryL2).creationCode : type(ConvexSidecarFactory).creationCode,
        //                 abi.encode(address(sidecarImplementation), address(protocolController), config.convex.booster)
        //             )
        //         )
        //     );
        // }

        /// 3c. Deploy the PendleAllocator contract.
        allocator = PendleAllocator(
            _deployWithCreate3(
                type(PendleAllocator).name,
                abi.encodePacked(type(PendleAllocator).creationCode, abi.encode(config.base.locker, address(gateway)))
            )
        );

        /// 5. Deploy Reward Receiver Implementation.
        isL2
            ? rewardReceiverImplementation = RewardReceiver(
                _deployWithCreate3(type(RewardReceiverL2).name, abi.encodePacked(type(RewardReceiverL2).creationCode))
            )
            : rewardReceiverImplementation = RewardReceiver(
                _deployWithCreate3(type(RewardReceiver).name, abi.encodePacked(type(RewardReceiver).creationCode))
            );

        bytes memory factoryParams = isL2
            ? abi.encode(
                admin,
                config.base.gaugeController,
                config.base.oldStrategy,
                address(protocolController),
                address(rewardVaultImplementation),
                address(rewardReceiverImplementation),
                config.base.locker,
                address(gateway)
            )
            : abi.encode(
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
                isL2 ? type(PendleFactoryL2).name : type(PendleFactory).name,
                abi.encodePacked(
                    isL2 ? type(PendleFactoryL2).creationCode : type(PendleFactory).creationCode, factoryParams
                )
            )
        );

        /// 17%
        accountant.setProtocolFeePercent(0.17e18);

        if (isL2) {
            accountant.setHarvestFeePercent(0);
        }
    }

    function _afterSetup() internal override {
        super._afterSetup();

        address[] memory gauges = getGauges();
        uint256 length = gauges.length;
        for (uint256 i; i < length; i++) {
            PendleFactory(factory).createVault(gauges[i]);
        }
    }

    function getGauges() internal virtual returns (address[] memory);
}
