// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SafeLibrary} from "test/utils/SafeLibrary.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {CurveFactory} from "src/integrations/curve/CurveFactory.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {CurveStrategy} from "src/integrations/curve/CurveStrategy.sol";
import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {CurveLocker, CurveProtocol} from "address-book/src/CurveEthereum.sol";
import {NewBaseIntegrationTest} from "test/integration/NewBaseIntegrationTest.sol";
import {OnlyBoostAllocator} from "src/integrations/curve/OnlyBoostAllocator.sol";
import {ConvexSidecarFactory} from "src/integrations/curve/ConvexSidecarFactory.sol";

/// @title CurveL2Integration - L2 Curve Integration Test
/// @notice Integration test for Curve protocol on L2 with Convex.
abstract contract CurveL2Integration is NewBaseIntegrationTest {
    /// @notice The configuration for the test.
    struct Config {
        string chain;
        bytes4 protocolId;
        uint256 blockNumber;
        address locker;
        address rewardToken;
        IStrategy.HarvestPolicy harvestPolicy;
        address minter;
        address boostProvider;
        /// Only Boost Config
        bool isOnlyBoost;
        address cvx;
        address convexBoostHolder;
        address booster;
    }

    /// @notice The configuration for the test.
    Config public config;

    constructor(Config memory _config, address[] memory _gauges) NewBaseIntegrationTest(_gauges) {
        config = _config;
    }

    function setUp()
        public
        virtual
        doSetup(
            config.chain,
            config.blockNumber,
            config.rewardToken,
            config.locker,
            config.protocolId,
            config.harvestPolicy
        )
    {
        /// 2. Deploy the Curve Strategy contract.
        strategy = address(
            new CurveStrategy({
                _registry: address(protocolController),
                _locker: config.locker,
                _gateway: address(gateway),
                _minter: config.minter
            })
        );

        /// 3. Check if the strategy is only boost.
        if (config.isOnlyBoost) {
            /// 3a. Deploy the Convex Sidecar implementation.
            sidecarImplementation = address(
                new ConvexSidecar({
                    _accountant: address(accountant),
                    _protocolController: address(protocolController),
                    _cvx: config.cvx,
                    _booster: config.booster
                })
            );

            /// 3b. Deploy the Convex Sidecar factory.
            sidecarFactory = address(
                new ConvexSidecarFactory({
                    _implementation: address(sidecarImplementation),
                    _protocolController: address(protocolController),
                    _booster: config.booster
                })
            );

            /// 3c. Deploy the OnlyBoostAllocator contract.
            allocator = new OnlyBoostAllocator({
                _locker: config.locker,
                _gateway: address(gateway),
                _convexSidecarFactory: sidecarFactory,
                _boostProvider: config.boostProvider,
                _convexBoostHolder: config.convexBoostHolder
            });
        }

        factory = address(
            new CurveFactory({
                protocolController: address(protocolController),
                vaultImplementation: address(rewardVaultImplementation),
                rewardReceiverImplementation: address(rewardReceiverImplementation),
                locker: config.locker,
                gateway: address(gateway),
                convexSidecarFactory: sidecarFactory
            })
        );

        _clearLockerBalances();
    }

    function _clearLockerBalances() internal {
        for (uint256 i = 0; i < gauges.length; i++) {
            uint256 balance = ILiquidityGauge(gauges[i]).balanceOf(config.locker);
            if (balance == 0) continue;

            address lpToken = ILiquidityGauge(gauges[i]).lp_token();
            bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

            // Withdraw from gauge
            bytes memory data = abi.encodeWithSignature("withdraw(uint256)", balance);
            SafeLibrary.execOnLocker(payable(gateway), config.locker, gauges[i], data, signatures);

            // Transfer to burn address
            data = abi.encodeWithSignature("transfer(address,uint256)", burnAddress, balance);
            SafeLibrary.execOnLocker(payable(gateway), config.locker, lpToken, data, signatures);
        }
    }
}

/// Test Contract  TODO: Remove this
contract CurveL2IntegrationTest is CurveL2Integration {
    Config public _config = Config({
        chain: "mainnet",
        blockNumber: 22_316_395,
        rewardToken: CurveProtocol.CRV,
        locker: CurveLocker.LOCKER,
        protocolId: bytes4(keccak256("CURVE")),
        harvestPolicy: IStrategy.HarvestPolicy.CHECKPOINT,
        minter: CurveProtocol.MINTER,
        boostProvider: CurveProtocol.VE_BOOST,
        isOnlyBoost: true,
        cvx: CurveProtocol.CONVEX_TOKEN,
        convexBoostHolder: CurveProtocol.CONVEX_BOOSTER,
        booster: CurveProtocol.CONVEX_BOOSTER
    });

    address[] public _gauges = [0x05255C5BD33672b9FEA4129C13274D1E6193312d];

    constructor() CurveL2Integration(_config, _gauges) {}
}
