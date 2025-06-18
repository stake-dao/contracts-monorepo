// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {CurveFactory} from "src/integrations/curve/L2/CurveFactory.sol";
import {CurveStrategy} from "src/integrations/curve/L2/CurveStrategy.sol";
import {ConvexSidecar} from "src/integrations/curve/L2/ConvexSidecar.sol";
import {OnlyBoostAllocator} from "src/integrations/curve/OnlyBoostAllocator.sol";
import {ConvexSidecarFactory} from "src/integrations/curve/L2/ConvexSidecarFactory.sol";

import "script/BaseDeploy.sol";

/// @title BaseCurveDeploy - Base deployment script for Curve protocol on L2 with Convex.
/// @dev TODO: Make it chain agnostic.
abstract contract BaseCurveDeploy is BaseDeploy {
    bytes4 internal constant PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice Base configuration for the test.
    struct BaseConfig {
        string chain;
        address locker;
        address rewardToken;
        IStrategy.HarvestPolicy harvestPolicy;
        address minter;
        address boostProvider;
        address oldStrategy;
        address gaugeController;
    }

    /// @notice Convex-specific configuration.
    struct ConvexConfig {
        bool isOnlyBoost;
        address cvx;
        address convexBoostHolder;
        address booster;
    }

    /// @notice Combined configuration for the test.
    struct Config {
        BaseConfig base;
        ConvexConfig convex;
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
        /// 2. Deploy the Curve Strategy contract.
        strategy = address(
            _deployWithCreate3(
                type(CurveStrategy).name,
                abi.encodePacked(
                    type(CurveStrategy).creationCode,
                    abi.encode(address(protocolController), config.base.locker, address(gateway))
                )
            )
        );

        /// 3. Check if the strategy is only boost.
        if (config.convex.isOnlyBoost) {
            /// 3a. Deploy the Convex Sidecar implementation.
            sidecarImplementation = address(
                _deployWithCreate3(
                    type(ConvexSidecar).name,
                    abi.encodePacked(
                        type(ConvexSidecar).creationCode,
                        abi.encode(
                            address(accountant), address(protocolController), config.convex.cvx, config.convex.booster
                        )
                    )
                )
            );

            /// 3b. Deploy the Convex Sidecar factory.
            sidecarFactory = address(
                _deployWithCreate3(
                    type(ConvexSidecarFactory).name,
                    abi.encodePacked(
                        type(ConvexSidecarFactory).creationCode,
                        abi.encode(address(sidecarImplementation), address(protocolController), config.convex.booster)
                    )
                )
            );

            /// 3c. Deploy the OnlyBoostAllocator contract.
            allocator = OnlyBoostAllocator(
                _deployWithCreate3(
                    type(OnlyBoostAllocator).name,
                    abi.encodePacked(
                        type(OnlyBoostAllocator).creationCode,
                        abi.encode(
                            config.base.locker,
                            address(gateway),
                            sidecarFactory,
                            config.base.boostProvider,
                            config.convex.convexBoostHolder
                        )
                    )
                )
            );
        }

        factory = address(
            _deployWithCreate3(
                type(CurveFactory).name,
                abi.encodePacked(
                    type(CurveFactory).creationCode,
                    abi.encode(
                        admin,
                        address(protocolController),
                        address(rewardVaultImplementation),
                        address(rewardReceiverImplementation),
                        config.base.locker,
                        address(gateway),
                        config.convex.booster,
                        sidecarFactory
                    )
                )
            )
        );

        /// 4. Set the harvest fee to 0 for non-mainnet chains.
        if (block.chainid != 1) {
            accountant.setHarvestFeePercent(0);
        }
    }
}
