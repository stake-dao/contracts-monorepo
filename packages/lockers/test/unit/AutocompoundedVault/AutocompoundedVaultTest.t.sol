// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {AutocompoundedVault} from "src/AutocompoundedVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

///////////////////////////////////////////////////////////////
/// --- SETUP
///////////////////////////////////////////////////////////////

contract AutocompoundedVaultHarness is AutocompoundedVault {
    StakingContract public stakingContract;

    constructor(
        uint128 streamingPeriod,
        IERC20 asset,
        string memory shareName,
        string memory shareSymbol,
        address owner,
        address _manager
    ) AutocompoundedVault(streamingPeriod, asset, shareName, shareSymbol, owner, _manager) {
        stakingContract = new StakingContract(asset);

        asset.approve(address(stakingContract), type(uint256).max);
    }

    function _stake(uint256 assets) internal override {
        stakingContract.deposit(assets);
    }

    function _unstake(uint256 assets) internal override {
        stakingContract.withdraw(assets);
    }

    function _getStakedBalance() internal view override returns (uint256) {
        return stakingContract.balanceOf();
    }

    /// @notice Claims the vault's rewards from the external source
    function claimStakingRewards() external override {}
}

contract StakingContract is Test {
    IERC20 internal asset;

    constructor(IERC20 _asset) {
        asset = _asset;
    }

    function deposit(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) external {
        asset.transfer(msg.sender, amount);
    }

    function balanceOf() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

contract AutocompoundedVaultTest is Test {
    AutocompoundedVaultHarness internal autocompoundedVault;
    address internal owner;
    address internal manager;
    IERC20 internal asset;
    uint128 internal streamingPeriod;
    string internal shareName;
    string internal shareSymbol;

    function setUp() public virtual {
        // Deploy a mock version of the asset
        // asset = new MockERC20();
        MockERC20 mockERC20 = new MockERC20();
        mockERC20.initialize("Stake DAO TOKEN", "sdTOKEN", 18);
        asset = IERC20(address(mockERC20));
        vm.label(address(asset), "asset");

        // Set the owner and manager addresses
        owner = makeAddr("owner");
        manager = makeAddr("manager");

        // Set the streaming period
        streamingPeriod = 7 days;

        // Set the shares metadata
        shareName = "Autocompounded Stake DAO TOKEN";
        shareSymbol = "asdTOKEN";

        // Deploy the Yieldnest Autocompounded Vault
        autocompoundedVault = new AutocompoundedVaultHarness(
            streamingPeriod, IERC20(address(asset)), shareName, shareSymbol, owner, manager
        );
        vm.label(address(autocompoundedVault), "AutocompoundedVault");
        vm.label(address(autocompoundedVault.stakingContract()), "StakingContract");
    }

    /// @notice Utility function to ensure a fuzzed address has not been previously labeled
    function _assumeUnlabeledAddress(address fuzzedAddress) internal view {
        vm.assume(bytes10(bytes(vm.getLabel(fuzzedAddress))) == bytes10(bytes("unlabeled:")));
    }

    function _assumeNotPrecompiledAddress(address fuzzedAddress) internal pure {
        vm.assume(uint160(fuzzedAddress) > 100);
    }

    function _assumeSafeAddress(address fuzzedAddress) internal view {
        _assumeUnlabeledAddress(fuzzedAddress);
        _assumeNotPrecompiledAddress(fuzzedAddress);
    }
}

///////////////////////////////////////////////////////////////
/// --- TEST SCENARIOS
///////////////////////////////////////////////////////////////

contract Constructor is AutocompoundedVaultTest {
    function test_CorrectlySetsTheAsset() external view {
        // it correctly sets the asset

        assertEq(autocompoundedVault.asset(), address(asset));
    }

    function test_CorrectlySetsTheNameOfTheShares() external view {
        // it correctly sets the name of the shares

        assertEq(autocompoundedVault.name(), shareName);
    }

    function test_CorrectlySetsTheSymbolOfTheShares() external view {
        // it correctly sets the symbol of the shares

        assertEq(autocompoundedVault.symbol(), shareSymbol);
    }

    function test_CorrectlySetsTheStreamingPeriod() external view {
        // it correctly sets the streaming period

        assertEq(autocompoundedVault.STREAMING_PERIOD(), streamingPeriod);
    }

    function test_CorrectlySetsTheManager() external view {
        // it correctly sets the manager

        assertEq(autocompoundedVault.manager(), manager);
    }

    function test_CorrectlySetsTheOwner() external view {
        // it correctly sets the owner

        assertEq(autocompoundedVault.owner(), owner);
    }
}

contract Deposit is AutocompoundedVaultTest {
    function testFuzz_DepositsTheAssetsAndMintTheShares(uint256 amount, address caller) external {
        // it deposits the assets and mint the shares

        // bound and airdrop the assets to the caller
        _assumeSafeAddress(caller);
        amount = bound(amount, 1e16, 1e25);
        deal(address(asset), caller, amount);

        // deposit the assets into the vault
        vm.prank(caller);
        asset.approve(address(autocompoundedVault), amount);
        vm.prank(caller);
        uint256 shares = autocompoundedVault.deposit(amount, caller);

        // the caller must have minted the shares token
        assertEq(autocompoundedVault.balanceOf(caller), amount);

        // the deposited assets must be in the staking contract, not in the vault
        assertEq(asset.balanceOf(address(autocompoundedVault)), 0);
        assertEq(asset.balanceOf(address(autocompoundedVault.stakingContract())), amount);

        // the total asset function of the vault must returns the correct staked assets
        assertEq(autocompoundedVault.totalAssets(), amount);

        // the number of shared returned by the deposit function must be equal to the number of assets deposited (1:1)
        assertEq(shares, amount);
    }

    function test_CorrectlyCallsTheStakingContract() external {
        // it correctly calls the staking contract

        uint256 amount = 1e21;
        address caller = makeAddr("caller");
        deal(address(asset), caller, amount);

        vm.prank(caller);
        asset.approve(address(autocompoundedVault), amount);

        vm.expectCall(
            address(autocompoundedVault.stakingContract()),
            abi.encodeCall(autocompoundedVault.stakingContract().deposit, (amount))
        );

        // deposit the assets into the vault
        vm.prank(caller);
        autocompoundedVault.deposit(amount, caller);
    }
}

contract Withdraw is AutocompoundedVaultTest {
    function testFuzz_WithdrawsTheAssetsAndBurnTheShares(uint256 amount, address caller) external {
        // it withdraws the assets and burn the shares

        // prepare the withdraw flow
        amount = _withdrawPreparationSteps(amount, caller);

        // withdraw the assets from the vault and validate the shares are burned
        vm.prank(caller);
        uint256 shares = autocompoundedVault.withdraw(amount, caller, caller);
        assertEq(autocompoundedVault.balanceOf(caller), 0);

        // the shares held by the caller must be burned
        assertEq(autocompoundedVault.balanceOf(caller), 0);

        // the assets must be in the caller's wallet
        assertEq(asset.balanceOf(caller), amount);

        // neither the vault nor the staking contract must hold the assets
        assertEq(asset.balanceOf(address(autocompoundedVault)), 0);
        assertEq(asset.balanceOf(address(autocompoundedVault.stakingContract())), 0);

        // the total asset function of the vault must returns the correct staked assets
        assertEq(autocompoundedVault.totalAssets(), 0);

        // the number of shares returned by the withdraw function must be equal to the number of assets withdrawn (1:1)
        assertEq(shares, amount);
    }

    function test_CorrectlyCallsTheStakingContract() external {
        // it correctly calls the staking contract

        uint256 amount = 1e21;
        address caller = makeAddr("caller");
        deal(address(asset), caller, amount);

        vm.prank(caller);
        asset.approve(address(autocompoundedVault), amount);

        // deposit the assets into the vault
        vm.prank(caller);
        autocompoundedVault.deposit(amount, caller);

        // withdraw the assets from the vault
        vm.expectCall(
            address(autocompoundedVault.stakingContract()),
            abi.encodeCall(autocompoundedVault.stakingContract().withdraw, (amount))
        );

        // withdraw the assets from the vault
        vm.prank(caller);
        autocompoundedVault.withdraw(amount, caller, caller);
    }

    /// forge-config: default.fuzz.runs = 200
    function testFuzz_AccountsTheRewardsFromTheOngoingStream(uint256 amount, address caller) external {
        // it accounts the rewards from the ongoing stream

        // prepare the withdraw flow by depositing the assets and starting a new reward stream
        amount = _withdrawPreparationSteps(amount, caller);
        uint256 rewards = _startNewRewardsStream();

        // warp to half the streaming period
        (,,,, uint128 remainingTime) = autocompoundedVault.getCurrentStream();
        vm.warp(block.timestamp + remainingTime / 2);

        // withdraw the assets from the vault
        uint256 maxWithdraw = autocompoundedVault.maxWithdraw(caller);
        vm.prank(caller);
        autocompoundedVault.withdraw(maxWithdraw, caller, caller);

        // the final balance of the caller must be greater than the initial balance
        assertGt(asset.balanceOf(caller), amount);

        // the caller must have received the rewards he vested (1e15 = 0.1% accepted delta)
        assertApproxEqRel(asset.balanceOf(caller), amount + rewards / 2, 1e15);

        // the unvested part of the rewards must still be held by the staking contract (1e15 = 0.1% accepted delta)
        assertApproxEqRel(asset.balanceOf(address(autocompoundedVault.stakingContract())), rewards / 2, 1e15);
    }

    /// forge-config: default.fuzz.runs = 200
    function testFuzz_AccountsTheRewardsFromTheEndedStream(uint256 amount, address caller) external {
        // it accounts the rewards from the ended stream
        amount = _withdrawPreparationSteps(amount, caller);
        uint256 rewards = _startNewRewardsStream();

        // warp to the end the streaming period
        (,,,, uint128 remainingTime) = autocompoundedVault.getCurrentStream();
        vm.warp(block.timestamp + remainingTime + 1);

        // withdraw the assets from the vault
        uint256 maxWithdraw = autocompoundedVault.maxWithdraw(caller);
        vm.prank(caller);
        autocompoundedVault.withdraw(maxWithdraw, caller, caller);

        // the final balance of the caller must be greater than the initial balance
        assertGt(asset.balanceOf(caller), amount);

        // the caller must have received all the assets vested (1e15 = 0.1% accepted delta)
        assertApproxEqRel(asset.balanceOf(caller), amount + rewards, 1e15);

        // the staking contract must not hold the rewards anymore (1e12 = 0.000001 tokens)
        assertLt(asset.balanceOf(address(autocompoundedVault.stakingContract())), 1e12);
    }

    function testFuzz_AccountsTheRewardsFromTheMultipleStreams(
        uint256 amount1,
        uint256 amount2,
        address caller1,
        address caller2
    ) external {
        // it accounts the rewards from the ended stream
        uint256 shares1 = _withdrawPreparationSteps(amount1, caller1);
        uint256 shares2 = _withdrawPreparationSteps(amount2, caller2);
        uint256 totalShares = shares1 + shares2;
        uint256 rewards = _startNewRewardsStream();

        // warp to the end the streaming period
        (,,,, uint128 remainingTime) = autocompoundedVault.getCurrentStream();
        vm.warp(block.timestamp + remainingTime);

        // withdraw the assets from the vault with caller1
        uint256 maxWithdraw1 = autocompoundedVault.maxWithdraw(caller1);
        vm.prank(caller1);
        autocompoundedVault.withdraw(maxWithdraw1, caller1, caller1);

        // withdraw the assets from the vault with caller2
        uint256 maxWithdraw2 = autocompoundedVault.maxWithdraw(caller2);
        vm.prank(caller2);
        autocompoundedVault.withdraw(maxWithdraw2, caller2, caller2);

        // rewards vested by both callers
        uint256 reward1 = asset.balanceOf(caller1) - shares1;
        uint256 reward2 = asset.balanceOf(caller2) - shares2;

        // the final balance of the callers must be greater than their initial balances
        assertGt(asset.balanceOf(caller1), shares1);
        assertGt(asset.balanceOf(caller2), shares2);

        // the total of rewards withdrawn must be equal to the total of rewards streamed (1e14 = 0.01% accepted delta)
        assertApproxEqRel(reward1 + reward2, rewards, 1e14);

        // the staking contract must not hold the rewards anymore (1e12 = 0.000001 tokens)
        assertLt(asset.balanceOf(address(autocompoundedVault.stakingContract())), 1e12);

        // ensure the proportion of rewards match the proportion of shares (1e14 = 0.01% accepted delta)
        assertApproxEqRel(reward1, (rewards * shares1) / totalShares, 1e14);
        assertApproxEqRel(reward2, (rewards * shares2) / totalShares, 1e14);
    }

    ///////////////////////////////////////////////////////////////
    /// --- HELPER FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @dev Bound the fuzzed values and process the deposit flow
    function _withdrawPreparationSteps(uint256 amount, address caller) internal returns (uint256) {
        // bound and airdrop the assets to the caller
        amount = bound(amount, 1e18, 1e24);
        deal(address(asset), caller, amount);
        _assumeSafeAddress(caller);

        // deposit the assets into the vault
        vm.prank(caller);
        asset.approve(address(autocompoundedVault), amount);
        vm.prank(caller);
        autocompoundedVault.deposit(amount, caller);

        return amount;
    }

    function _startNewRewardsStream() internal returns (uint256 rewards) {
        rewards = 1e24;
        // set a new reward stream
        deal(address(asset), manager, rewards);
        vm.prank(manager);
        IERC20(asset).approve(address(autocompoundedVault), rewards);
        vm.prank(manager);
        autocompoundedVault.setRewardsStream(rewards);
    }
}

contract SetRewardsStream is AutocompoundedVaultTest {
    function testFuzz_RevertsWhenCalledByUnauthorizedAddress(address caller, uint256 amount) external {
        // it reverts when called by unauthorized address

        _assumeSafeAddress(caller);
        vm.assume(caller != manager);

        vm.expectRevert(abi.encodeWithSelector(AutocompoundedVault.InvalidManager.selector));
        vm.prank(caller);
        autocompoundedVault.setRewardsStream(amount);
    }

    function testFuzz_RevertsWhenCallerDoesntHaveEnoughBalance(uint256 balance) external {
        // it reverts when no ERC20 allowance

        balance = bound(balance, 1, 1e30);

        deal(address(asset), manager, balance);

        vm.expectRevert();
        vm.prank(manager);
        autocompoundedVault.setRewardsStream(balance + 1);
    }

    function testFuzz_CreatesANewStreamWithGivenAmount(uint256 _amount) external {
        _amount = bound(_amount, 1, 1e30);

        // 1. Deal the asset to the manager and approve the vault to manage them
        deal(address(asset), manager, _amount);
        vm.prank(manager);
        IERC20(asset).approve(address(autocompoundedVault), _amount);

        // 2. Start a new reward stream
        vm.prank(manager);
        autocompoundedVault.setRewardsStream(_amount);

        // 3. Get the created stream data
        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime) =
            autocompoundedVault.getCurrentStream();

        // 4. Assert the stream
        assertEq(amount, _amount);
        assertEq(remainingToken, _amount); // timestamp didn't change
        assertEq(start, uint128(block.timestamp));
        assertEq(end, uint128(block.timestamp + autocompoundedVault.STREAMING_PERIOD()));
        assertEq(remainingTime, uint128(autocompoundedVault.STREAMING_PERIOD())); // timestamp didn't change

        // 5. Assert the balance of the vault and the manager
        assertEq(asset.balanceOf(address(autocompoundedVault.stakingContract())), _amount);
        assertEq(asset.balanceOf(manager), 0);
    }

    function testFuzz_CreatesANewStreamWithGivenAndUnvestedAmount(uint256 _amountStream1, uint256 _amountStream2)
        external
    {
        // it creates a new stream with given and unvested amount

        _amountStream1 = bound(_amountStream1, 1e12, 1e20);
        _amountStream2 = bound(_amountStream2, 1e12, 1e20);

        // 1. Deal the asset to the manager and approve the vault to manage them
        deal(address(asset), manager, _amountStream1 + _amountStream2);
        vm.prank(manager);
        IERC20(asset).approve(address(autocompoundedVault), _amountStream1);

        // 3. Set the first rewards
        vm.prank(manager);
        autocompoundedVault.setRewardsStream(_amountStream1);

        // 4. warp to half the streaming period
        (,,,, uint128 remainingTime1) = autocompoundedVault.getCurrentStream();
        vm.warp(block.timestamp + remainingTime1 / 2);

        // 5. Approve the asset of the second streamfor the autocompounded vault
        vm.prank(manager);
        IERC20(asset).approve(address(autocompoundedVault), _amountStream2);

        // 6. Set the second rewards
        vm.prank(manager);
        autocompoundedVault.setRewardsStream(_amountStream2);

        // 7. Get the current stream
        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime2) =
            autocompoundedVault.getCurrentStream();

        // 8. Assert the stream included the unvested amount of the unfinised previous stream
        assertEq(amount, _amountStream1 / 2 + _amountStream2);
        assertEq(remainingToken, _amountStream1 / 2 + _amountStream2);
        assertEq(start, uint128(block.timestamp));
        assertEq(end, uint128(block.timestamp + autocompoundedVault.STREAMING_PERIOD()));
        assertEq(remainingTime2, uint128(autocompoundedVault.STREAMING_PERIOD()));
    }

    function test_CorrectlyCallsTheStakingContract() external {
        // it correctly calls the staking contract

        // 1. Deal the asset to the manager
        uint256 amount = 1e28;
        deal(address(asset), manager, amount);

        // 2. Approve the asset for the autocompounded vault
        vm.prank(manager);
        IERC20(asset).approve(address(autocompoundedVault), amount);

        // 3. Set the rewards and assert the flow calls the staking contract deposit function
        vm.expectCall(
            address(autocompoundedVault.stakingContract()),
            abi.encodeCall(autocompoundedVault.stakingContract().deposit, (amount))
        );

        // 4. Set the rewards
        vm.prank(manager);
        autocompoundedVault.setRewardsStream(amount);
    }

    function test_EmitAnEvent() external {
        // it emit an event

        // 1. Deal the asset to the manager
        uint256 amount = 1e28;
        deal(address(asset), manager, amount);

        // 2. Approve the asset for the autocompounded vault
        vm.prank(manager);
        IERC20(asset).approve(address(autocompoundedVault), amount);

        vm.expectEmit(true, true, true, true);
        emit NewStreamRewards(
            manager, amount, uint128(block.timestamp), uint128(block.timestamp + autocompoundedVault.STREAMING_PERIOD())
        );

        // 3. Set the rewards
        vm.prank(manager);
        autocompoundedVault.setRewardsStream(amount);
    }

    /// @notice Event emitted when a new stream is started
    event NewStreamRewards(address indexed caller, uint256 amount, uint128 start, uint128 end);
}

contract GetCurrentStream is AutocompoundedVaultTest {
    function test_ReturnsNoRemainingTokenAndTimeIfNoStreamStarted() external view {
        // it returns no remaining token and time if no stream started

        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime) =
            autocompoundedVault.getCurrentStream();

        assertEq(amount, 0);
        assertEq(remainingToken, 0);
        assertEq(start, 0);
        assertEq(end, 0);
        assertEq(remainingTime, 0);
    }

    function test_ReturnsNoRemainingTokenAndTimeIfTheStreamFinished() external {
        // it returns no remaining token and time if the stream finished

        // set a reward stream
        deal(address(asset), manager, 1e18);
        vm.prank(manager);
        IERC20(asset).approve(address(autocompoundedVault), 1e18);
        vm.prank(manager);
        autocompoundedVault.setRewardsStream(1e18);

        // warp to the end of the streaming period
        vm.warp(block.timestamp + autocompoundedVault.STREAMING_PERIOD());

        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime) =
            autocompoundedVault.getCurrentStream();

        assertEq(amount, 1e18);
        assertEq(remainingToken, 0);
        assertEq(start, block.timestamp - autocompoundedVault.STREAMING_PERIOD());
        assertEq(end, block.timestamp);
        assertEq(remainingTime, 0);
    }

    function test_ReturnsCalculatedValuesIfTheStreamIsOngoing() external {
        // it returns calculated values if the stream is ongoing

        // set a reward stream
        deal(address(asset), manager, 1e20);
        vm.prank(manager);
        IERC20(asset).approve(address(autocompoundedVault), 1e20);
        vm.prank(manager);
        autocompoundedVault.setRewardsStream(1e20);

        // warp 1 day to the futre
        uint256 startTimestamp = block.timestamp;
        vm.warp(startTimestamp + 1 days);

        // fetch and check the current stream
        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime) =
            autocompoundedVault.getCurrentStream();

        assertEq(amount, 1e20);
        assertEq(start, startTimestamp);
        assertEq(end, startTimestamp + autocompoundedVault.STREAMING_PERIOD());
        assertEq(remainingTime, autocompoundedVault.STREAMING_PERIOD() - 1 days);
        assertEq(
            remainingToken,
            (1e20 * (autocompoundedVault.STREAMING_PERIOD() - 1 days)) / autocompoundedVault.STREAMING_PERIOD()
        );
    }
}

contract TotalAssets is AutocompoundedVaultTest {
    function test_ReturnsTheRealBalanceWhenThereIsNoStream(uint256 balance) external {
        // it returns the real balance when there is no stream

        balance = bound(balance, 1e12, 1e30);

        // airdrop some assets to staking contract
        deal(address(asset), address(autocompoundedVault.stakingContract()), balance);

        assertEq(autocompoundedVault.totalAssets(), balance);
    }

    function test_ReturnsTheRealBalanceMinusTheUnvestedStream(uint256 initialBalance, uint256 rewards) external {
        // it returns the real balance minus the unvested portion when there is a stream

        initialBalance = bound(initialBalance, 1e12, 1e18);
        rewards = bound(rewards, 1e12, 1e18);
        uint256 initialTimestamp = block.timestamp;

        // airdrop some assets to the staking contract
        deal(address(asset), address(autocompoundedVault.stakingContract()), initialBalance);

        // start a reward stream
        deal(address(asset), manager, rewards);
        vm.prank(manager);
        IERC20(asset).approve(address(autocompoundedVault), rewards);
        vm.prank(manager);
        autocompoundedVault.setRewardsStream(rewards);

        // warp to a quarter of the streaming period and assert the total assets (+/- 1% due to the precision of the division)
        (,,,, uint128 streamDuration) = autocompoundedVault.getCurrentStream();
        vm.warp(initialTimestamp + streamDuration / 4);
        assertApproxEqRel(autocompoundedVault.totalAssets(), initialBalance + rewards / 4, 1e16);

        // warp to half of the streaming period and assert the total assets (+/- 1% due to the precision of the division)
        vm.warp(initialTimestamp + streamDuration / 2);
        assertApproxEqRel(autocompoundedVault.totalAssets(), initialBalance + rewards / 2, 1e16);

        // // warp to the end of the streaming period and assert the total assets
        vm.warp(initialTimestamp + streamDuration);
        assertEq(autocompoundedVault.totalAssets(), initialBalance + rewards);

        // // warp to a future timestamp and assert the total assets didn't change and is equal to the real balance
        vm.warp(initialTimestamp + streamDuration * 3 / 2);
        assertEq(autocompoundedVault.totalAssets(), initialBalance + rewards);
        assertEq(
            autocompoundedVault.totalAssets(),
            IERC20(autocompoundedVault.asset()).balanceOf(address(autocompoundedVault.stakingContract()))
        );
    }

    function test_DoesntCountTransferredTokens() external {
        // it doesn't count transferred tokens

        // airdrop some playing assets to this contract and ensure the initial total assets is 0
        deal(address(asset), address(this), 1e20);
        assertEq(autocompoundedVault.totalAssets(), 0);

        // send some assets to the vault without calling the deposit function and ensure the total assets is still 0
        asset.transfer(address(autocompoundedVault), 1e5);
        assertEq(autocompoundedVault.totalAssets(), 0);

        // call the deposit function and validate the total assets is equal to the real balance
        asset.approve(address(autocompoundedVault), 1e10);
        autocompoundedVault.deposit(1e5, address(this));
        assertEq(autocompoundedVault.totalAssets(), 1e5);

        // try to send the rest of the tokens while the vault balance is not 0
        // the transfered tokens should not be counted in the total assets
        asset.transfer(address(autocompoundedVault), 1e10);
        assertEq(autocompoundedVault.totalAssets(), 1e5);
    }
}

contract Owner is AutocompoundedVaultTest {
    function testFuzz_RevertsIfTheCallerIsNotTheOwner(address caller) external {
        // it reverts if the caller is not the owner

        vm.assume(caller != owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        autocompoundedVault.transferOwnership(makeAddr("newOwner"));
    }

    function testFuzz_SetsTheNewOwner(address newOwner) external {
        // it sets the new owner

        vm.prank(owner);
        autocompoundedVault.transferOwnership(newOwner);
        vm.prank(newOwner);
        autocompoundedVault.acceptOwnership();

        assertEq(autocompoundedVault.owner(), newOwner);
    }
}

contract Manager is AutocompoundedVaultTest {
    function testFuzz_RevertsIfTheCallerIsNotTheOwner(address caller) external {
        // it reverts if the caller is not the owner

        vm.assume(caller != owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        autocompoundedVault.setManager(makeAddr("newManager"));
    }

    function testFuzz_SetsTheNewManager(address newManager) external {
        // it sets the new manager

        vm.prank(owner);
        autocompoundedVault.setManager(newManager);

        assertEq(autocompoundedVault.manager(), newManager);
    }

    function testFuzz_EmitAnEvent(address newManager) external {
        // it emit an event

        vm.expectEmit(true, true, true, true);
        emit ManagerChanged(newManager);

        vm.prank(owner);
        autocompoundedVault.setManager(newManager);
    }

    /// @notice Event emitted when a new manager is set
    event ManagerChanged(address indexed newManager);
}
