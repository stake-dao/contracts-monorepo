// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/BaseSetup.sol";

import {Factory} from "src/Factory.sol";

abstract contract NewBaseIntegrationTest is BaseSetup {
    using Math for uint256;

    uint256 public constant MAX_REWARDS = 100_000e18;
    uint256 public constant MAX_ACCOUNT_POSITIONS = 100;

    address public harvester = makeAddr("Harvester");

    struct AccountPosition {
        address account;
        uint256 baseAmount;
        uint256 additionalAmount;
        uint256 gaugeIndex;
    }

    /// @notice Deployed reward vaults for each gauge.
    RewardVault[] public rewardVaults;

    /// @notice Deployed reward receivers for each gauge.
    RewardReceiver[] public rewardReceivers;

    /// @notice Total harvestable rewards.
    uint256 public totalHarvestableRewards;

    /// @notice Gauge address being tested.
    address[] public gauges;

    constructor(address[] memory _gauges) {
        gauges = _gauges;
    }

    function test_complete_protocol_lifecycle() public {
        (AccountPosition[] memory _accountPositions, uint256[] memory _rewards) =
            _generateAccountPositionsAndRewards();

        /// 1. Deploy the RewardVaults.
        (rewardVaults, rewardReceivers) = deployRewardVaults();

        /// 2. Assert that the deployment is valid.
        assertDeploymentValid(rewardVaults, rewardReceivers);

        RewardVault rewardVault;
        RewardReceiver rewardReceiver;
        AccountPosition memory accountPosition;

        address gauge;

        for (uint256 i = 0; i < _accountPositions.length; i++) {
            accountPosition = _accountPositions[i];

            gauge = gauges[accountPosition.gaugeIndex];
            rewardVault = rewardVaults[accountPosition.gaugeIndex];
            rewardReceiver = rewardReceivers[accountPosition.gaugeIndex];

            /// 4. Deposit the amount into the vault.
            deposit(rewardVault, accountPosition.account, accountPosition.baseAmount);

            /// 5. Assertions
            assertEq(
                rewardVault.balanceOf(accountPosition.account),
                accountPosition.baseAmount,
                "Expected account balance to be equal to deposited amount"
            );

            assertGe(
                rewardVault.totalSupply(),
                accountPosition.baseAmount,
                "Expected total supply to be greater than or equal to deposited amount"
            );

            assertEq(
                IStrategy(strategy).balanceOf(gauge),
                rewardVault.totalSupply(),
                "Expected strategy balance to be equal to total supply"
            );

            /// 6. Simulate rewards.
            simulateRewards(rewardVault, _rewards[i]);

            /// 7. Store the harvestable rewards for the vault for future assertions.
            totalHarvestableRewards += _rewards[i];

            /// 8. Skip 1 day.
            skip(1 days);

            /// 9. Additional deposits.
            deposit(rewardVault, accountPosition.account, accountPosition.additionalAmount);

            /// 10. Assertions
            assertEq(
                rewardVault.balanceOf(accountPosition.account),
                accountPosition.baseAmount + accountPosition.additionalAmount,
                "Expected account balance to be equal to base amount plus additional amount"
            );

            assertGe(
                rewardVault.totalSupply(),
                accountPosition.baseAmount + accountPosition.additionalAmount,
                "Expected total supply to be greater than or equal to base amount plus additional amount"
            );

            assertEq(
                IStrategy(strategy).balanceOf(gauge),
                rewardVault.totalSupply(),
                "Expected strategy balance to be equal to total supply after additional deposits"
            );
        }

        /// 10. Assert that the accountant has no rewards before harvest.
        assertEq(
            _balanceOf(rewardToken, address(accountant)), 0, "Expected accountant to have no rewards before harvest"
        );

        /// 11. Assert that the harvester has no rewards before harvest.
        assertEq(_balanceOf(rewardToken, harvester), 0, "Expected harvester to have no rewards before harvest");

        /// 12. Assert that the protocol fees accrued are 0.
        assertEq(accountant.protocolFeesAccrued(), 0, "Expected protocol fees accrued to be 0");

        /// 13. Harvest the rewards.
        harvest();

        uint256 expectedHarvesterBalance = totalHarvestableRewards.mulDiv(accountant.getHarvestFeePercent(), 1e18);
        uint256 expectedProtocolFeesAccrued = totalHarvestableRewards.mulDiv(accountant.getProtocolFeePercent(), 1e18);
        uint256 expectedAccountantBalance = totalHarvestableRewards - expectedHarvesterBalance;

        /// 14. Assert that the accountant has no rewards before harvest.
        assertApproxEqRel(_balanceOf(rewardToken, address(accountant)), expectedAccountantBalance, 0.001e18, "Expected accountant to have rewards after harvest with a 0.1% error");

        /// 15. Assert that the harvester has no rewards before harvest.
        assertApproxEqRel(_balanceOf(rewardToken, harvester), expectedHarvesterBalance, 0.001e18, "Expected harvester to have rewards after harvest with a 0.1% error");

        /// 16. Assert that the protocol fees accrued are greater than 0.
        assertApproxEqRel(accountant.protocolFeesAccrued(), expectedProtocolFeesAccrued, 0.001e18, "Expected protocol fees accrued to be greater than 0 after harvest with a 0.1% error");
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDABLE FUNCTIONS
    //////////////////////////////////////////////////////

    function deployRewardVaults()
        internal
        virtual
        returns (RewardVault[] memory vaults, RewardReceiver[] memory receivers)
    {
        /// Deploy the vaults.
        vaults = new RewardVault[](gauges.length);
        receivers = new RewardReceiver[](gauges.length);

        for (uint256 i = 0; i < gauges.length; i++) {
            address gauge = gauges[i];

            /// Deploy the vault and receiver.
            (address vault, address receiver) = Factory(factory).createVault(gauge);

            vaults[i] = RewardVault(vault);
            receivers[i] = RewardReceiver(receiver);
        }
    }

    /// @notice Simulates rewards for the given vault.
    function simulateRewards(RewardVault vault, uint256 amount) internal virtual {}

    //////////////////////////////////////////////////////
    /// --- TEST HELPERS
    //////////////////////////////////////////////////////

    function deposit(RewardVault rewardVault, address account, uint256 amount) internal {
        /// 1. Get the asset address.
        address asset = rewardVault.asset();

        /// 2. Deal the amount to the account.
        deal(asset, account, amount);

        /// 3. Approve the asset to be spent by the vault.
        vm.startPrank(account);
        IERC20(asset).approve(address(rewardVault), amount);

        /// 4. Deposit
        rewardVault.deposit(amount, account);
        vm.stopPrank();
    }

    function harvest() internal {
        bytes[] memory harvestData = new bytes[](gauges.length);

        vm.prank(harvester);
        accountant.harvest(gauges, harvestData, harvester);

        // /// 2. Track the harvester rewards.
        // uint256 harvesterRewards = _balanceOf(rewardToken, harvester);
    }

    //////////////////////////////////////////////////////
    /// --- VALIDATION HELPERS
    //////////////////////////////////////////////////////

    /// TODO: Implement this.
    function assertDeploymentValid(RewardVault[] memory vaults, RewardReceiver[] memory receivers) internal pure {
        RewardVault vault;
        RewardReceiver receiver;
        for (uint256 i = 0; i < vaults.length; i++) {
            vault = vaults[i];
            receiver = receivers[i];
        }
    }

    //////////////////////////////////////////////////////
    /// --- FUZZING HELPERS
    //////////////////////////////////////////////////////

    function _generateAccountPositionsAndRewards()
        internal
        returns (AccountPosition[] memory, uint256[] memory)
    {
        uint256 length = bound(uint256(keccak256(abi.encode("length"))), 1, MAX_ACCOUNT_POSITIONS);

        uint256[] memory rewards = new uint256[](length);
        AccountPosition[] memory positions = new AccountPosition[](length);

        for (uint256 i = 0; i < length; i++) {
            address gauge = gauges[i % gauges.length];
            uint256 maxAmount = IERC20(gauge).totalSupply() / 2;

            uint256 baseAmount = bound(uint256(keccak256(abi.encode("baseAmount", i))), 1e18, maxAmount);
            uint256 additionalAmount = bound(uint256(keccak256(abi.encode("additionalAmount", i))), 1e18, baseAmount);

            positions[i] = AccountPosition({
                account: makeAddr(string(abi.encodePacked("Account", i))),
                baseAmount: baseAmount,
                additionalAmount: additionalAmount,
                gaugeIndex: i % gauges.length
            });

            rewards[i] = bound(uint256(keccak256(abi.encode("rewards", i))), 1e18, MAX_REWARDS);
        }

        return (positions, rewards);
    }
}