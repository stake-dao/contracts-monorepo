// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {ConvexSidecarFactory} from "src/integrations/curve/ConvexSidecarFactory.sol";
import {Factory} from "src/integrations/curve/CurveFactory.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {RewardVault} from "src/RewardVault.sol";
import {BaseCurveTest} from "test/integration/curve/BaseCurveTest.sol";

abstract contract CurveFactoryTest is BaseCurveTest {
    constructor(uint256 _pid) BaseCurveTest(_pid) {}

    function test_RevertWhenGaugeIsShutdownOnOldStrategy() public whenGaugeIsNotShutdownOnOldStrategy {
        /// 1. Revert by creating a single vault.
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidDeployment.selector));
        curveFactory.createVault(address(gauge));

        /// 2. Revert by creating using pid.
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidDeployment.selector));
        curveFactory.create(pid);
    }

    function test_RevertWhenGaugeIsInvalid() public {
        address invalidGauge = makeAddr("Invalid Gauge");

        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidGauge.selector));
        curveFactory.createVault(invalidGauge);
    }

    function test_RevertWhenGaugeIsAlreadyDeployed() public {
        address nonNullAddress = makeAddr("Non Null Address");

        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.vaults.selector, gauge),
            abi.encode(nonNullAddress)
        );

        vm.expectRevert(abi.encodeWithSelector(Factory.AlreadyDeployed.selector));
        curveFactory.createVault(address(gauge));
    }

    function test_RevertCreateSidecarWhenVaultIsNotDeployed() public {
        vm.expectRevert(abi.encodeWithSelector(ConvexSidecarFactory.VaultNotDeployed.selector));
        convexSidecarFactory.create(address(gauge), pid);
    }

    function test_createVault() public {
        (address vault, address rewardReceiver) = curveFactory.createVault(address(gauge));

        RewardVault vaultContract = RewardVault(vault);
        RewardReceiver rewardReceiverContract = RewardReceiver(rewardReceiver);

        /// 1. Check all the immutable clones args are correct.
        assertEq(vaultContract.gauge(), address(gauge));
        assertEq(vaultContract.asset(), address(lpToken));

        /// 2. Check the reward receiver is correctly set with the vault.
        assertEq(address(rewardReceiverContract.rewardVault()), vault);

        /// 3. Check the vault is correctly initialized.
        uint256 allowance = IERC20(address(lpToken)).allowance(address(LOCKER), address(gauge));
        assertEq(allowance, type(uint256).max);

        /// 4. Check that the vault is registered in the protocol controller.
        (address _vault, address _asset, address _rewardReceiver, bytes4 _protocolId, bool _isShutdown) =
            protocolController.gauge(address(gauge));

        assertEq(_vault, vault);
        assertEq(_asset, address(lpToken));
        assertEq(_rewardReceiver, rewardReceiver);
        assertEq(_protocolId, bytes4(keccak256("CURVE")));
        assertEq(_isShutdown, false);

        if (_checkExtraRewards(address(gauge))) {
            address gaugeRewardReceiver = ILiquidityGauge(address(gauge)).rewards_receiver(LOCKER);

            uint256 rewardCount = ILiquidityGauge(address(gauge)).reward_count();
            uint256 finalCount;

            for (uint256 i; i < rewardCount; i++) {
                address rewardToken = ILiquidityGauge(address(gauge)).reward_tokens(i);
                (,, uint256 periodFinish,,,) = ILiquidityGauge(address(gauge)).reward_data(rewardToken);
                if (periodFinish > block.timestamp) {
                    finalCount++;
                }
            }

            address[] memory rewardTokens = vaultContract.getRewardTokens();

            /// We take into account CVX.
            assertEq(rewardTokens.length, finalCount + 1);
            assertEq(gaugeRewardReceiver, rewardReceiver);
        }
    }

    function test_CreateSidecarFromSidecarFactory() public {
        (, address rewardReceiver) = curveFactory.createVault(address(gauge));

        ConvexSidecar sidecar = ConvexSidecar(address(convexSidecarFactory.create(address(gauge), pid)));

        (,,, address _baseRewardPool,,) = BOOSTER.poolInfo(pid);

        /// 1.  Check all the immutable clones args are correct
        assertEq(address(sidecar.asset()), address(lpToken));
        assertEq(sidecar.rewardReceiver(), rewardReceiver);
        assertEq(address(sidecar.baseRewardPool()), _baseRewardPool);
        assertEq(sidecar.pid(), pid);

        /// 2. Check the sidecar is correctly initialized.
        uint256 allowance = IERC20(address(lpToken)).allowance(address(sidecar), address(BOOSTER));
        assertEq(allowance, type(uint256).max);
    }

    function test_CreateVaultAndSidecar() public {
        (,, address sidecar) = curveFactory.create(pid);
        assertEq(convexSidecarFactory.sidecar(address(gauge)), sidecar);
    }

    /// @notice Check if the gauge has extra rewards or supports extra rewards.
    function _checkExtraRewards(address gauge) internal returns (bool success) {
        bytes memory data = abi.encodeWithSignature("reward_tokens(uint256)", 0);

        (success,) = gauge.call(data);
    }
}

uint256 constant CONVEX_POOL_437_PID = 437;

uint256 constant CONVEX_POOL_436_PID = 436;

uint256 constant CONVEX_POOL_435_PID = 435;

uint256 constant CONVEX_POOL_434_PID = 434;

uint256 constant CONVEX_POOL_433_PID = 433;

uint256 constant CONVEX_POOL_432_PID = 432;

uint256 constant CONVEX_POOL_431_PID = 431;

uint256 constant CONVEX_POOL_430_PID = 430;

contract CONVEX_POOL_437_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_437_PID) {}

contract CONVEX_POOL_436_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_436_PID) {}

contract CONVEX_POOL_435_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_435_PID) {}

contract CONVEX_POOL_434_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_434_PID) {}

contract CONVEX_POOL_433_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_433_PID) {}

contract CONVEX_POOL_432_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_432_PID) {}

contract CONVEX_POOL_431_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_431_PID) {}

contract CONVEX_POOL_430_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_430_PID) {}
