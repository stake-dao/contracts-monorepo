// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.sol";
import {SafeLibrary} from "test/utils/SafeLibrary.sol";
import {RewardVault} from "src/RewardVault.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {Allocator} from "src/Allocator.sol";
import {CurveAllocator} from "src/integrations/curve/CurveAllocator.sol";
import {CurveFactory} from "src/integrations/curve/CurveFactory.sol";
import {CurveStrategy, IMinter} from "src/integrations/curve/CurveStrategy.sol";
import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {ConvexSidecarFactory, IBooster} from "src/integrations/curve/ConvexSidecarFactory.sol";
import {CurveLocker, CurveProtocol} from "address-book/src/CurveEthereum.sol";
import {Common} from "address-book/src/CommonEthereum.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {Enum} from "@safe/contracts/common/Enum.sol";

/// @title CurveMainnetIntegration - Mainnet Curve Integration Test
/// @notice Integration test for Curve protocol on Ethereum mainnet with Convex.
abstract contract CurveMainnetIntegration is BaseIntegrationTest {
    //////////////////////////////////////////////////////
    /// --- MAINNET CONFIGURATION
    //////////////////////////////////////////////////////

    // Mainnet addresses
    address constant CRV = CurveProtocol.CRV;
    address constant MINTER = CurveProtocol.MINTER;
    address constant LOCKER = CurveLocker.LOCKER;
    address constant OLD_STRATEGY = CurveLocker.STRATEGY;
    address constant WBTC = Common.WBTC;
    address constant CVX = CurveProtocol.CONVEX_TOKEN;
    address constant CONVEX_BOOSTER = CurveProtocol.CONVEX_BOOSTER;
    address constant CURVE_ADMIN = 0x40907540d8a6C65c637785e8f8B742ae6b0b9968;

    //////////////////////////////////////////////////////
    /// --- STATE VARIABLES
    //////////////////////////////////////////////////////

    address public convexSidecarFactory;
    mapping(address => ConvexSidecar) public gaugeToSidecar;

    uint256 public immutable convexPoolId1;
    uint256 public immutable convexPoolId2;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor(uint256 _convexPoolId1, uint256 _convexPoolId2) {
        convexPoolId1 = _convexPoolId1;
        convexPoolId2 = _convexPoolId2;
    }

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////

    function setUp() public virtual override {
        // Fork mainnet
        vm.createSelectFork("mainnet", 22_316_395);

        // Initialize core protocol
        _beforeSetup({
            _rewardToken: CRV,
            _locker: LOCKER,
            _protocolId: bytes4(keccak256("CURVE")),
            _harvestPolicy: IStrategy.HarvestPolicy.CHECKPOINT
        });

        // Initialize accounts
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            accounts.push(makeAddr(string(abi.encodePacked("Account", i))));
        }

        // Deploy Curve strategy
        strategy = address(new CurveStrategy(address(protocolController), LOCKER, address(gateway), MINTER));

        // Deploy sidecar implementation and factory
        address sidecarImplementation = address(new ConvexSidecar(address(accountant), address(protocolController)));
        convexSidecarFactory = address(new ConvexSidecarFactory(sidecarImplementation, address(protocolController)));

        // Deploy Curve factory with Convex support
        factory = address(
            new CurveFactory(
                address(protocolController),
                address(rewardVaultImplementation),
                address(rewardReceiverImplementation),
                LOCKER,
                address(gateway),
                convexSidecarFactory
            )
        );

        // Deploy and set allocator
        allocator = new CurveAllocator({
            _locker: LOCKER,
            _gateway: address(gateway),
            _convexSidecarFactory: address(convexSidecarFactory),
            _boostDelegationV3: CurveProtocol.VE_BOOST,
            _convexBoostHolder: CurveProtocol.CONVEX_PROXY
        });

        _afterSetup();
    }

    function _afterSetup() internal override {
        super._afterSetup();

        /// Enable sidecar factory as registrar.
        protocolController.setRegistrar(convexSidecarFactory, true);

        /// Enable sidecar factory as module.
        _enableModule(convexSidecarFactory);

        /// Allow minting of the reward token.
        _allowMint(strategy);

        // Setup gauges from Convex pool IDs
        _setupGaugesFromPids();

        // Deploy vaults for each gauge
        for (uint256 i = 0; i < gauges.length; i++) {
            _deployVault(gauges[i]);
            _setupAdditionalRewards(gauges[i]);
        }

        // Setup accounts with tokens (moved after vault deployment)
        _setupAccountsWithTokens();

        // Clear existing gauge balances
        _clearLockerBalances();
    }

    //////////////////////////////////////////////////////
    /// --- PROTOCOL IMPLEMENTATION
    //////////////////////////////////////////////////////

    function _getProtocolId() internal pure override returns (bytes4) {
        return bytes4(keccak256("CURVE"));
    }

    function _deployVault(address gaugeAddress)
        internal
        override
        returns (RewardVault vault, RewardReceiver receiver)
    {
        // Find Convex pool ID
        uint256 poolId = _findConvexPoolIdForGauge(gaugeAddress);

        // Deploy with sidecar
        (address vaultAddr, address receiverAddr, address sidecarAddr) = CurveFactory(factory).create(poolId);

        vault = RewardVault(vaultAddr);
        receiver = RewardReceiver(receiverAddr);
        gaugeToSidecar[gaugeAddress] = ConvexSidecar(sidecarAddr);

        rewardVaults.push(vault);
        rewardReceivers.push(receiver);
    }

    function _inflateRewards(uint256 gaugeIndex, uint256 amount) internal override returns (uint256) {
        address gauge = gauges[gaugeIndex];
        uint256 currentMinted = IMinter(MINTER).minted(LOCKER, gauge);
        uint256 targetIntegrateFraction = currentMinted + amount;

        vm.mockCall(
            gauge,
            abi.encodeWithSelector(ILiquidityGauge.integrate_fraction.selector, LOCKER),
            abi.encode(targetIntegrateFraction)
        );

        return amount;
    }

    function _getPendingRewards(uint256 gaugeIndex) internal view override returns (uint256) {
        ConvexSidecar sidecar = gaugeToSidecar[gauges[gaugeIndex]];
        if (address(sidecar) != address(0)) {
            return sidecar.getPendingRewards();
        }
        return 0;
    }

    function _setupAdditionalRewards(address gaugeAddress) internal override {
        // Add WBTC as extra reward
        vm.prank(CURVE_ADMIN);
        ILiquidityGauge(gaugeAddress).add_reward(WBTC, address(this));

        // Mock reward data
        vm.mockCall(
            gaugeAddress,
            abi.encodeWithSelector(ILiquidityGauge.reward_data.selector),
            abi.encode(WBTC, address(this), block.timestamp + 1 days, 0, block.timestamp, 0)
        );

        // Sync rewards
        CurveFactory(factory).syncRewardTokens(gaugeAddress);
    }

    function _getMainRewardToken() internal pure override returns (address) {
        return CRV;
    }

    function _getStrategyBalance(uint256 gaugeIndex) internal view override returns (uint256) {
        return IStrategy(strategy).balanceOf(gauges[gaugeIndex]);
    }

    //////////////////////////////////////////////////////
    /// --- CURVE SPECIFIC SETUP
    //////////////////////////////////////////////////////

    function _setupGaugesFromPids() internal {
        IBooster booster = IBooster(CONVEX_BOOSTER);
        uint256[] memory pids = new uint256[](2);
        pids[0] = convexPoolId1;
        pids[1] = convexPoolId2;

        for (uint256 i = 0; i < pids.length; i++) {
            (address lpToken,, address gauge,,,) = booster.poolInfo(pids[i]);
            gauges.push(gauge);
            depositTokens.push(lpToken);

            // Setup gauge
            _setupGauge(gauge);
        }

        // Setup reward tokens
        rewardTokens.push(CRV);
        rewardTokens.push(CVX);
        rewardTokens.push(WBTC);
    }

    function _setupGauge(address gauge) internal {
        // Mark as shutdown in old strategy
        vm.mockCall(
            OLD_STRATEGY, abi.encodeWithSelector(bytes4(keccak256("isShutdown(address)")), gauge), abi.encode(true)
        );

        // Mock reward distributor as zero
        vm.mockCall(
            OLD_STRATEGY,
            abi.encodeWithSelector(bytes4(keccak256("rewardDistributors(address)")), gauge),
            abi.encode(address(0))
        );
    }

    function _clearLockerBalances() internal {
        for (uint256 i = 0; i < gauges.length; i++) {
            uint256 balance = ILiquidityGauge(gauges[i]).balanceOf(LOCKER);
            if (balance == 0) continue;

            address burnAddress = makeAddr("Burn");
            address lpToken = ILiquidityGauge(gauges[i]).lp_token();
            bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

            // Withdraw from gauge
            bytes memory withdrawData = abi.encodeWithSignature("withdraw(uint256)", balance);
            bytes memory withdrawExecute =
                abi.encodeWithSignature("execute(address,uint256,bytes)", gauges[i], 0, withdrawData);

            gateway.execTransaction(
                LOCKER, 0, withdrawExecute, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), signatures
            );

            // Transfer to burn address
            bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", burnAddress, balance);
            bytes memory transferExecute =
                abi.encodeWithSignature("execute(address,uint256,bytes)", lpToken, 0, transferData);

            gateway.execTransaction(
                LOCKER, 0, transferExecute, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), signatures
            );
        }
    }

    function _allowMint(address minterAddress) internal {
        /// Build signatures
        bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

        /// Build data
        bytes memory data = abi.encodeWithSignature("toggle_approve_mint(address)", minterAddress);
        data = abi.encodeWithSignature("execute(address,uint256,bytes)", MINTER, 0, data);

        /// Execute transaction
        SafeLibrary.simpleExec({_safe: payable(gateway), _target: LOCKER, _data: data, _signatures: signatures});
    }

    function _findConvexPoolIdForGauge(address gauge) internal view returns (uint256) {
        IBooster booster = IBooster(CONVEX_BOOSTER);
        uint256 poolCount = booster.poolLength();

        for (uint256 i = 0; i < poolCount; i++) {
            (,, address poolGauge,,,) = booster.poolInfo(i);
            if (poolGauge == gauge) {
                return i;
            }
        }
        return type(uint256).max;
    }

    //////////////////////////////////////////////////////
    /// --- EXTRA REWARDS HANDLING
    //////////////////////////////////////////////////////

    function _handleFinalWithdrawals(TestParams memory params) internal override {
        // Handle CVX/extra rewards before withdrawals
        _handleCVXRewards();

        // Wait for rewards vesting
        skip(1 weeks);

        // Execute base withdrawals
        super._handleFinalWithdrawals(params);

        // Process extra reward claims
        _processExtraRewardClaims();
    }

    function _handleCVXRewards() internal {
        uint256 totalCVX = 1_000_000e18;
        uint256 totalWBTC = 1e18;

        for (uint256 i = 0; i < rewardReceivers.length; i++) {
            address receiver = address(rewardReceivers[i]);
            ConvexSidecar sidecar = gaugeToSidecar[rewardVaults[i].gauge()];

            if (address(sidecar) == address(0)) continue;

            // Distribute rewards
            deal(CVX, receiver, totalCVX / rewardReceivers.length);
            deal(WBTC, receiver, totalWBTC / rewardReceivers.length);

            // Claim from sidecar
            sidecar.claimExtraRewards();

            // Distribute to vault
            rewardReceivers[i].distributeRewards();
        }
    }

    function _processExtraRewardClaims() internal {
        uint256 totalCVXClaimed = 0;
        uint256 totalWBTCClaimed = 0;

        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 beforeClaimCVX = IERC20(CVX).balanceOf(accounts[i]);
            uint256 beforeClaimWBTC = IERC20(WBTC).balanceOf(accounts[i]);

            // Claim from all vaults
            for (uint256 j = 0; j < rewardVaults.length; j++) {
                address[] memory tokens = rewardVaults[j].getRewardTokens();
                vm.prank(accounts[i]);
                rewardVaults[j].claim(tokens, accounts[i]);
            }

            uint256 afterClaimCVX = IERC20(CVX).balanceOf(accounts[i]);
            uint256 afterClaimWBTC = IERC20(WBTC).balanceOf(accounts[i]);

            uint256 claimedCVX = afterClaimCVX - beforeClaimCVX;
            uint256 claimedWBTC = afterClaimWBTC - beforeClaimWBTC;

            totalCVXClaimed += claimedCVX;
            totalWBTCClaimed += claimedWBTC;

            // Verify rewards received
            assertGt(claimedCVX, 0, "Account should receive CVX rewards");
            assertGt(claimedWBTC, 0, "Account should receive WBTC rewards");

            // Verify claimable amounts are zero
            for (uint256 j = 0; j < rewardVaults.length; j++) {
                assertEq(rewardVaults[j].getClaimable(CVX, accounts[i]), 0, "CVX claimable should be 0");
                assertEq(rewardVaults[j].getClaimable(WBTC, accounts[i]), 0, "WBTC claimable should be 0");
            }
        }

        // Verify total distribution
        assertApproxEqRel(totalCVXClaimed, 1_000_000e18, 0.05e18, "Total CVX claimed should match distributed");
        assertApproxEqRel(totalWBTCClaimed, 1e18, 0.05e18, "Total WBTC claimed should match distributed");
    }
}

// Concrete test instances
contract CurveMainnet437Test is CurveMainnetIntegration(437, 436) {}

contract CurveMainnet435Test is CurveMainnetIntegration(435, 434) {}

contract CurveMainnet433Test is CurveMainnetIntegration(433, 432) {}

contract CurveMainnet431Test is CurveMainnetIntegration(431, 430) {}
