// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {console} from "forge-std/src/console.sol";
import {BaseForkTest} from "test/BaseFork.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeLibrary} from "test/utils/SafeLibrary.sol";
import {RewardVault} from "src/RewardVault.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {Accountant} from "src/Accountant.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {Strategy} from "src/Strategy.sol";
import {Allocator} from "src/Allocator.sol";
import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {Enum} from "@safe/contracts/common/Enum.sol";

/// @title BaseIntegrationTest - Protocol-Agnostic Integration Test Framework
/// @notice Abstract base test contract that captures universal DeFi reward distribution invariants.
/// @dev Provides a common testing framework for all protocol integrations.
///      Key features:
///      - Standardized deposit/withdraw/claim cycles.
///      - Multi-user and multi-gauge testing support.
///      - Comprehensive reward distribution validation.
///      - Protocol-agnostic test structure.
abstract contract BaseIntegrationTest is BaseForkTest {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice Number of test accounts to simulate.
    uint256 public constant NUM_ACCOUNTS = 3;

    //////////////////////////////////////////////////////
    /// --- TEST INFRASTRUCTURE
    //////////////////////////////////////////////////////

    /// @notice Test accounts array.
    address[] public accounts;

    /// @notice Harvester address for reward collection.
    address public harvester = makeAddr("Harvester");

    /// @notice Deployed reward vaults for each gauge.
    RewardVault[] public rewardVaults;

    /// @notice Deployed reward receivers for each gauge.
    RewardReceiver[] public rewardReceivers;

    //////////////////////////////////////////////////////
    /// --- PROTOCOL COMPONENTS
    //////////////////////////////////////////////////////

    /// @notice Deposit tokens for each gauge.
    address[] public depositTokens;

    /// @notice Reward tokens supported by the protocol.
    address[] public rewardTokens;

    /// @notice Gauge addresses being tested.
    address[] public gauges;

    /// @notice Vault implementation address for cloning.
    address public vaultImplementation;

    //////////////////////////////////////////////////////
    /// --- TEST PARAMETERS
    //////////////////////////////////////////////////////

    /// @notice Test parameters structure to avoid stack depth issues.
    struct TestParams {
        uint256[] baseAmounts;
        uint256[] totalDeposited;
        uint256[][] depositAmounts;
        uint256[][] remainingShares;
        uint256[] totalExpectedRewards;
        uint256[] totalClaimedRewards;
        uint256[] totalWithdrawn;
        uint256[] expectedRewards1;
        uint256[] expectedRewards2;
        uint256[] expectedRewards3;
        uint256 harvestRewards;
        uint256 accountantRewards;
        uint256 harvestRewards2;
        uint256 totalClaimedRewards2;
        uint256 accountantRewards2;
        address transferReceiver;
    }

    //////////////////////////////////////////////////////
    /// --- ABSTRACT METHODS
    //////////////////////////////////////////////////////

    /// @notice Returns the protocol identifier.
    /// @return Protocol ID.
    function _getProtocolId() internal pure virtual returns (bytes4);

    /// @notice Initializes protocol-specific components.
    /// @dev Must set up gauges, tokens, and protocol contracts.
    function _initializeProtocol() internal virtual;

    /// @notice Deploys vault for a specific gauge.
    /// @param gaugeAddress Address of the gauge.
    /// @return vault Deployed reward vault.
    /// @return receiver Deployed reward receiver.
    function _deployVault(address gaugeAddress) internal virtual returns (RewardVault vault, RewardReceiver receiver);

    /// @notice Inflates rewards for testing.
    /// @param gaugeIndex Index of the gauge.
    /// @param amount Amount to inflate.
    /// @return Expected rewards.
    function _inflateRewards(uint256 gaugeIndex, uint256 amount) internal virtual returns (uint256);

    /// @notice Gets pending rewards from protocol.
    /// @param gaugeIndex Index of the gauge.
    /// @return Pending rewards amount.
    function _getPendingRewards(uint256 gaugeIndex) internal view virtual returns (uint256);

    /// @notice Sets up additional reward tokens.
    /// @param gaugeAddress Address of the gauge.
    function _setupAdditionalRewards(address gaugeAddress) internal virtual;

    /// @notice Returns the main reward token address.
    /// @return Main reward token.
    function _getMainRewardToken() internal view virtual returns (address);

    /// @notice Gets strategy balance for a gauge.
    /// @param gaugeIndex Index of the gauge.
    /// @return Strategy balance.
    function _getStrategyBalance(uint256 gaugeIndex) internal view virtual returns (uint256);

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////

    /// @notice Sets up the test environment.
    /// @dev Initializes accounts, protocol components, and vaults.
    function setUp() public virtual {
        // Initialize test accounts
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            accounts.push(makeAddr(string(abi.encodePacked("Account", i))));
        }
    }

    //////////////////////////////////////////////////////
    /// --- COMMON SETUP HELPERS
    //////////////////////////////////////////////////////

    /// @notice Performs common setup after protocol initialization.
    /// @dev Deploys implementations, sets strategy/allocator, enables modules.
    function _performCommonSetup() internal virtual {
        // Empty by default - implementations should override this method
        // to perform protocol-specific setup like deploying strategies,
        // allocators, and setting up registrars
    }

    /// @notice Sets up test accounts with tokens and approvals.
    function _setupAccountsWithTokens() internal {
        for (uint256 gaugeIdx = 0; gaugeIdx < gauges.length; gaugeIdx++) {
            address depositToken = depositTokens[gaugeIdx];
            uint256 totalSupply = IERC20(depositToken).totalSupply();

            for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
                uint256 amount = totalSupply / NUM_ACCOUNTS;
                deal(depositToken, accounts[i], amount);

                vm.prank(accounts[i]);
                IERC20(depositToken).approve(address(rewardVaults[gaugeIdx]), amount);
            }
        }
    }

    //////////////////////////////////////////////////////
    /// --- MAIN TEST FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Tests sequential deposits and withdrawals with multiple users.
    /// @param _baseAmount Base amount for first gauge.
    /// @param _baseAmount2 Base amount for second gauge.
    /// @dev Main integration test exercising full deposit/withdraw/claim cycles.
    function test_deposit_withdraw_sequentially(uint256 _baseAmount, uint256 _baseAmount2) public virtual {
        require(gauges.length >= 2, "Need at least 2 gauges");

        // Create base amounts array
        uint256[] memory _baseAmounts = new uint256[](gauges.length);
        _baseAmounts[0] = _baseAmount;
        if (gauges.length > 1) _baseAmounts[1] = _baseAmount2;

        // Fill remaining with proportional amounts
        for (uint256 i = 2; i < gauges.length; i++) {
            _baseAmounts[i] = _baseAmount;
        }

        // Validate base amounts
        for (uint256 i = 0; i < _baseAmounts.length; i++) {
            vm.assume(_baseAmounts[i] > 1e18);
            uint256 maxAmount = IERC20(depositTokens[i]).totalSupply() / NUM_ACCOUNTS / 10;
            vm.assume(_baseAmounts[i] < maxAmount);
        }

        // Initialize test parameters
        TestParams memory params = _initializeTestParams(_baseAmounts);

        // Execute test phases
        _handleDeposits(params);
        _verifyInitialDeposits(params);

        _handleFirstRewards(params);
        _handleAdditionalDeposits(params);
        _verifySecondDeposits(params);

        _handleFirstHarvestAndClaims(params);
        _handlePartialWithdrawals(params);
        _verifyPartialWithdrawals(params);

        _handleSecondHarvestAndClaims(params);
        _handleFinalWithdrawals(params);
        _verifyFinalState(params);
    }

    /// @notice Tests integral increases with decreasing rewards.
    /// @param _baseAmount Base amount for first gauge.
    /// @param _baseAmount2 Base amount for second gauge.
    /// @dev Regression test for issue #111.
    function test_netCredited_DecreasingRewards(uint256 _baseAmount, uint256 _baseAmount2) public virtual {
        require(gauges.length >= 2, "Need at least 2 gauges");

        // Create base amounts array
        uint256[] memory _baseAmounts = new uint256[](gauges.length);
        _baseAmounts[0] = _baseAmount;
        if (gauges.length > 1) _baseAmounts[1] = _baseAmount2;

        // Fill remaining with proportional amounts
        for (uint256 i = 2; i < gauges.length; i++) {
            _baseAmounts[i] = _baseAmount;
        }

        // Validate base amounts
        for (uint256 i = 0; i < _baseAmounts.length; i++) {
            vm.assume(_baseAmounts[i] > 1e18);
            uint256 maxAmount = IERC20(depositTokens[i]).totalSupply() / NUM_ACCOUNTS / 10;
            vm.assume(_baseAmounts[i] < maxAmount);
        }

        // Initialize and handle deposits
        TestParams memory params = _initializeTestParams(_baseAmounts);
        _handleDeposits(params);

        // Test with first gauge
        address vault = protocolController.vaults(gauges[0]);

        // Get initial integral
        uint256 integralBefore = accountant.getVaultIntegral(vault);

        // Generate large rewards
        uint256 largeReward = 1000e18;
        _inflateRewards(0, largeReward);
        skip(1 hours);

        // Harvest large rewards
        address[] memory gaugesToHarvest = new address[](1);
        gaugesToHarvest[0] = gauges[0];
        bytes[] memory harvestData = new bytes[](1);

        vm.prank(harvester);
        accountant.harvest(gaugesToHarvest, harvestData, harvester);

        uint256 integralAfterFirst = accountant.getVaultIntegral(vault);
        assertGt(integralAfterFirst, integralBefore, "Integral should increase after first harvest");

        // Generate smaller rewards
        uint256 smallReward = 30e18;
        _inflateRewards(0, smallReward);
        skip(1 hours);

        uint256 integralBeforeSecond = accountant.getVaultIntegral(vault);

        // Harvest smaller rewards
        vm.prank(harvester);
        accountant.harvest(gaugesToHarvest, harvestData, harvester);

        uint256 integralAfterSecond = accountant.getVaultIntegral(vault);
        assertGt(
            integralAfterSecond, integralBeforeSecond, "Integral should still increase after harvesting smaller rewards"
        );
    }

    //////////////////////////////////////////////////////
    /// --- TEST PHASE HANDLERS
    //////////////////////////////////////////////////////

    /// @notice Initializes test parameters.
    /// @param _baseAmounts Base deposit amounts.
    /// @return params Initialized test parameters.
    function _initializeTestParams(uint256[] memory _baseAmounts) internal returns (TestParams memory) {
        TestParams memory params;
        params.transferReceiver = makeAddr("Transfer Receiver");
        params.baseAmounts = _baseAmounts;

        // Initialize arrays
        uint256 numGauges = gauges.length;
        params.totalDeposited = new uint256[](numGauges);
        params.depositAmounts = new uint256[][](numGauges);
        params.remainingShares = new uint256[][](numGauges);
        params.totalExpectedRewards = new uint256[](numGauges);
        params.totalClaimedRewards = new uint256[](numGauges);
        params.totalWithdrawn = new uint256[](numGauges);
        params.expectedRewards1 = new uint256[](numGauges);
        params.expectedRewards2 = new uint256[](numGauges);
        params.expectedRewards3 = new uint256[](numGauges);

        for (uint256 i = 0; i < numGauges; i++) {
            params.depositAmounts[i] = new uint256[](NUM_ACCOUNTS);
            params.remainingShares[i] = new uint256[](NUM_ACCOUNTS);
        }

        return params;
    }

    /// @notice Handles initial deposits.
    /// @param params Test parameters.
    function _handleDeposits(TestParams memory params) internal {
        for (uint256 gaugeIdx = 0; gaugeIdx < gauges.length; gaugeIdx++) {
            for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
                uint256 accountAmount = params.baseAmounts[gaugeIdx] * (i + 1);
                params.depositAmounts[gaugeIdx][i] = accountAmount;
                params.totalDeposited[gaugeIdx] += accountAmount;

                vm.prank(accounts[i]);
                rewardVaults[gaugeIdx].deposit(accountAmount, accounts[i]);
            }
        }
    }

    /// @notice Verifies initial deposits.
    /// @param params Test parameters.
    function _verifyInitialDeposits(TestParams memory params) internal view {
        for (uint256 i = 0; i < gauges.length; i++) {
            uint256 strategyBalance = _getStrategyBalance(i);
            uint256 expectedBalance = params.totalDeposited[i];

            assertEq(
                strategyBalance,
                expectedBalance,
                string(abi.encodePacked("Initial deposit mismatch for gauge ", vm.toString(i)))
            );
        }
    }

    /// @notice Handles first reward round.
    /// @param params Test parameters.
    function _handleFirstRewards(TestParams memory params) internal {
        uint256[] memory rewardAmounts = _getFirstRewardAmounts();

        for (uint256 i = 0; i < gauges.length; i++) {
            params.expectedRewards1[i] = _inflateRewards(i, rewardAmounts[i]);
        }

        skip(1 hours);

        // Check pending rewards
        for (uint256 i = 0; i < gauges.length; i++) {
            uint256 pendingRewards = _getPendingRewards(i);
            params.totalExpectedRewards[i] += params.expectedRewards1[i] + pendingRewards;
        }
    }

    /// @notice Returns first round reward amounts.
    /// @return amounts Reward amounts array.
    function _getFirstRewardAmounts() internal virtual returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](gauges.length);
        for (uint256 i = 0; i < gauges.length; i++) {
            amounts[i] = 1000e18 * (i + 1);
        }
        return amounts;
    }

    /// @notice Handles additional deposits.
    /// @param params Test parameters.
    function _handleAdditionalDeposits(TestParams memory params) internal {
        for (uint256 gaugeIdx = 0; gaugeIdx < gauges.length; gaugeIdx++) {
            for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
                uint256 accountAmount = params.baseAmounts[gaugeIdx] * (i + 1) / 2;
                params.depositAmounts[gaugeIdx][i] += accountAmount;
                params.totalDeposited[gaugeIdx] += accountAmount;

                address depositToken = depositTokens[gaugeIdx];
                deal(depositToken, accounts[i], accountAmount);

                vm.prank(accounts[i]);
                IERC20(depositToken).approve(address(rewardVaults[gaugeIdx]), accountAmount);

                vm.prank(accounts[i]);
                rewardVaults[gaugeIdx].deposit(accountAmount, accounts[i]);
            }
        }

        // Second round of rewards
        uint256[] memory rewardAmounts = _getSecondRewardAmounts();
        for (uint256 i = 0; i < gauges.length; i++) {
            params.expectedRewards2[i] = _inflateRewards(i, rewardAmounts[i]);
        }

        skip(1 hours);

        // Update expected rewards
        for (uint256 i = 0; i < gauges.length; i++) {
            uint256 pendingRewards = _getPendingRewards(i);
            params.totalExpectedRewards[i] = params.expectedRewards2[i] + pendingRewards;
        }
    }

    /// @notice Returns second round reward amounts.
    /// @return amounts Reward amounts array.
    function _getSecondRewardAmounts() internal virtual returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](gauges.length);
        for (uint256 i = 0; i < gauges.length; i++) {
            amounts[i] = 1200e18 * (i + 1);
        }
        return amounts;
    }

    /// @notice Verifies second deposits.
    /// @param params Test parameters.
    function _verifySecondDeposits(TestParams memory params) internal view {
        for (uint256 i = 0; i < gauges.length; i++) {
            assertEq(
                _getStrategyBalance(i),
                params.totalDeposited[i],
                string(abi.encodePacked("Second deposit mismatch for gauge ", vm.toString(i)))
            );
        }
    }

    /// @notice Handles first harvest and claims.
    /// @param params Test parameters.
    function _handleFirstHarvestAndClaims(TestParams memory params) internal {
        // Harvest all gauges
        bytes[] memory harvestData = new bytes[](gauges.length);

        vm.prank(harvester);
        accountant.harvest(gauges, harvestData, harvester);

        // Track harvester rewards
        params.harvestRewards = _balanceOf(_getMainRewardToken(), harvester);

        // Clear harvest data for claims
        harvestData = new bytes[](0);

        // Each account claims
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 beforeClaim = _balanceOf(_getMainRewardToken(), accounts[i]);

            vm.prank(accounts[i]);
            accountant.claim(gauges, harvestData);

            uint256 afterClaim = _balanceOf(_getMainRewardToken(), accounts[i]);
            uint256 claimed = afterClaim - beforeClaim;

            for (uint256 j = 0; j < gauges.length; j++) {
                params.totalClaimedRewards[j] += claimed / gauges.length;
            }

            assertGt(claimed, 0, "Account should receive rewards");
        }

        // Track accountant rewards
        params.accountantRewards = _balanceOf(_getMainRewardToken(), address(accountant));

        // Verify total distribution
        uint256 totalExpected = 0;
        for (uint256 i = 0; i < gauges.length; i++) {
            totalExpected += params.totalExpectedRewards[i];
        }

        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < gauges.length; i++) {
            totalClaimed += params.totalClaimedRewards[i];
        }

        uint256 actualTotal = params.harvestRewards + totalClaimed + params.accountantRewards;
        assertApproxEqRel(actualTotal, totalExpected, 0.01e18, "Total rewards mismatch");
    }

    /// @notice Handles partial withdrawals.
    /// @param params Test parameters.
    function _handlePartialWithdrawals(TestParams memory params) internal {
        for (uint256 gaugeIdx = 0; gaugeIdx < gauges.length; gaugeIdx++) {
            for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
                uint256 withdrawAmount = params.depositAmounts[gaugeIdx][i] / 2;
                params.totalWithdrawn[gaugeIdx] += withdrawAmount;

                uint256 beforeWithdraw = _balanceOf(depositTokens[gaugeIdx], accounts[i]);

                vm.prank(accounts[i]);
                rewardVaults[gaugeIdx].withdraw(withdrawAmount, accounts[i], accounts[i]);

                uint256 afterWithdraw = _balanceOf(depositTokens[gaugeIdx], accounts[i]);
                params.remainingShares[gaugeIdx][i] = rewardVaults[gaugeIdx].balanceOf(accounts[i]);

                assertEq(
                    afterWithdraw - beforeWithdraw,
                    withdrawAmount,
                    string(abi.encodePacked("Partial withdrawal mismatch for gauge ", vm.toString(gaugeIdx)))
                );
            }
        }
    }

    /// @notice Verifies partial withdrawals.
    /// @param params Test parameters.
    function _verifyPartialWithdrawals(TestParams memory params) internal view {
        for (uint256 i = 0; i < gauges.length; i++) {
            assertEq(
                _getStrategyBalance(i),
                params.totalDeposited[i] - params.totalWithdrawn[i],
                string(abi.encodePacked("Balance after partial withdrawal mismatch for gauge ", vm.toString(i)))
            );
        }
    }

    /// @notice Handles second harvest and claims.
    /// @param params Test parameters.
    function _handleSecondHarvestAndClaims(TestParams memory params) internal {
        // Third round of rewards
        uint256[] memory rewardAmounts = _getThirdRewardAmounts();
        for (uint256 i = 0; i < gauges.length; i++) {
            params.expectedRewards3[i] = _inflateRewards(i, rewardAmounts[i]);
        }

        skip(1 hours);

        // Transfer shares before harvest
        for (uint256 gaugeIdx = 0; gaugeIdx < gauges.length; gaugeIdx++) {
            for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
                vm.prank(accounts[i]);
                rewardVaults[gaugeIdx].transfer(params.transferReceiver, params.remainingShares[gaugeIdx][i]);
            }
        }

        // Harvest
        bytes[] memory harvestData = new bytes[](gauges.length);
        vm.prank(harvester);
        accountant.harvest(gauges, harvestData, harvester);

        params.harvestRewards2 = _balanceOf(_getMainRewardToken(), harvester) - params.harvestRewards;

        // Claims and transfer back
        harvestData = new bytes[](0);
        uint256 totalClaimed2 = 0;

        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 beforeClaim = _balanceOf(_getMainRewardToken(), accounts[i]);

            vm.prank(accounts[i]);
            accountant.claim(gauges, harvestData);

            uint256 afterClaim = _balanceOf(_getMainRewardToken(), accounts[i]);
            totalClaimed2 += afterClaim - beforeClaim;

            // Transfer shares back
            for (uint256 gaugeIdx = 0; gaugeIdx < gauges.length; gaugeIdx++) {
                vm.prank(params.transferReceiver);
                rewardVaults[gaugeIdx].transfer(accounts[i], params.remainingShares[gaugeIdx][i]);
            }
        }

        params.totalClaimedRewards2 = totalClaimed2;
        params.accountantRewards2 = _balanceOf(_getMainRewardToken(), address(accountant)) - params.accountantRewards;

        // Verify second round distribution
        uint256 totalNewRewards = 0;
        for (uint256 i = 0; i < gauges.length; i++) {
            totalNewRewards += params.expectedRewards3[i] + _getPendingRewards(i);
        }

        uint256 actualTotal2 = params.harvestRewards2 + params.totalClaimedRewards2 + params.accountantRewards2;
        assertApproxEqRel(actualTotal2, totalNewRewards, 0.05e18, "Second round rewards mismatch");
    }

    /// @notice Returns third round reward amounts.
    /// @return amounts Reward amounts array.
    function _getThirdRewardAmounts() internal virtual returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](gauges.length);
        for (uint256 i = 0; i < gauges.length; i++) {
            amounts[i] = 1500e18 * (i + 1);
        }
        return amounts;
    }

    /// @notice Handles final withdrawals.
    /// @param params Test parameters.
    function _handleFinalWithdrawals(TestParams memory params) internal virtual {
        for (uint256 gaugeIdx = 0; gaugeIdx < gauges.length; gaugeIdx++) {
            for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
                uint256 remainingAmount = params.remainingShares[gaugeIdx][i];
                uint256 beforeWithdraw = _balanceOf(depositTokens[gaugeIdx], accounts[i]);

                vm.prank(accounts[i]);
                rewardVaults[gaugeIdx].withdraw(remainingAmount, accounts[i], accounts[i]);

                uint256 afterWithdraw = _balanceOf(depositTokens[gaugeIdx], accounts[i]);

                assertEq(
                    afterWithdraw - beforeWithdraw,
                    remainingAmount,
                    string(abi.encodePacked("Final withdrawal mismatch for gauge ", vm.toString(gaugeIdx)))
                );

                assertEq(
                    afterWithdraw,
                    params.depositAmounts[gaugeIdx][i],
                    string(abi.encodePacked("Total returned != deposited for gauge ", vm.toString(gaugeIdx)))
                );
            }
        }
    }

    /// @notice Verifies final state.
    function _verifyFinalState(TestParams memory) internal view {
        for (uint256 i = 0; i < gauges.length; i++) {
            assertEq(
                _getStrategyBalance(i),
                0,
                string(abi.encodePacked("Strategy should be empty for gauge ", vm.toString(i)))
            );
        }
    }
}
