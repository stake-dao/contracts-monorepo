pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Accountant} from "src/Accountant.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {RewardVault} from "src/RewardVault.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";

contract RewardVault__deposit is RewardVaultBaseTest {
    address internal gauge = makeAddr("gauge");
    address internal asset;
    address internal strategyAsset;

    address internal TARGET_INHOUSE_STRATEGY = makeAddr("TARGET_INHOUSE_STRATEGY");
    address internal TARGET_EXTERNAL_STRATEGY = makeAddr("TARGET_EXTERNAL_STRATEGY");

    enum Allocation {
        MIXED,
        STAKEDAO,
        CONVEX
    }

    // This implementation is the harnessed version of the reward vault cloned with the variables above
    RewardVaultHarness internal cloneRewardVault;

    // Due to the 1:1 relationship of the assets and the shares, the deposit and the  functions
    // do the same thing. This function is a wrapper that calls the appropriate function based on the context
    // of the test. This is a virtual allowing the mint test to override it to call `mint` instead of `deposit`.
    function deposit_mint_wrapper(uint256 assets, address receiver) internal virtual returns (uint256) {
        return cloneRewardVault.deposit(assets, receiver);
    }

    function setUp() public virtual override {
        // we're deploying and setting up the reward vault as it would be in a real deployment
        super.setUp();

        // the implementation of reward vault is replaced with the harness variant for testing purposes
        _replaceRewardVaultWithRewardVaultHarness(address(rewardVault));

        // deploy asset mock
        asset = address(new ERC20Mock("Asset", "ASSET", 18));
        vm.label({account: asset, newLabel: "asset"});

        // deploying a fake ERC20 token that serves as strategy's asset
        strategyAsset = address(new ERC20Mock("Strategy Asset", "STRAT", 18));
        vm.label({account: strategyAsset, newLabel: "strategyAsset"});

        // The gauge() function reads from offset 20, so we need to ensure gauge is at that position
        // The asset() function reads from offset 40, so we need to ensure asset is at that position
        // We use abi.encodePacked to ensure proper byte alignment
        bytes memory encodedData = abi.encodePacked(gauge, asset);

        // clone the harnessed reward vault with the immutable variables
        cloneRewardVault = RewardVaultHarness(Clones.cloneWithImmutableArgs(address(rewardVaultHarness), encodedData));
        vm.label({account: address(cloneRewardVault), newLabel: "cloneRewardVault"});
    }

    function _mixedAllocation(uint256 accountBalance)
        private
        view
        returns (uint256[] memory amounts, address[] memory targets)
    {
        amounts = new uint256[](2);
        amounts[0] = accountBalance / 3;
        amounts[1] = accountBalance / 3 * 2;

        targets = new address[](2);
        targets[0] = TARGET_INHOUSE_STRATEGY;
        targets[1] = TARGET_EXTERNAL_STRATEGY;

        return (amounts, targets);
    }

    function _stakedaoAllocation(uint256 accountBalance)
        private
        view
        returns (uint256[] memory amounts, address[] memory targets)
    {
        amounts = new uint256[](1);
        amounts[0] = accountBalance;

        targets = new address[](1);
        targets[0] = TARGET_INHOUSE_STRATEGY;

        return (amounts, targets);
    }

    function _convexAllocation(uint256 accountBalance)
        private
        view
        returns (uint256[] memory amounts, address[] memory targets)
    {
        amounts = new uint256[](1);
        amounts[0] = accountBalance;

        targets = new address[](1);
        targets[0] = TARGET_EXTERNAL_STRATEGY;

        return (amounts, targets);
    }

    function _mock_test_dependencies(uint256 accountBalance, Allocation allocationType)
        internal
        returns (IAllocator.Allocation memory allocation, IStrategy.PendingRewards memory pendingRewards)
    {
        uint256[] memory amounts;
        address[] memory targets;

        if (allocationType == Allocation.MIXED) {
            (amounts, targets) = _mixedAllocation(accountBalance);
        } else if (allocationType == Allocation.STAKEDAO) {
            (amounts, targets) = _stakedaoAllocation(accountBalance);
        } else if (allocationType == Allocation.CONVEX) {
            (amounts, targets) = _convexAllocation(accountBalance);
        }

        // set the allocation and pending rewards to mock values
        allocation = IAllocator.Allocation({gauge: gauge, targets: targets, amounts: amounts});
        pendingRewards = IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0});

        // mock the allocator returned by the protocol controller
        vm.mockCall(
            address(cloneRewardVault.PROTOCOL_CONTROLLER()),
            abi.encodeWithSelector(IProtocolController.allocator.selector, protocolId),
            abi.encode(address(allocator))
        );

        // mock the withdrawal allocation returned by the allocator
        vm.mockCall(
            address(allocator), abi.encodeWithSelector(IAllocator.getDepositAllocation.selector), abi.encode(allocation)
        );

        // mock the strategy returned by the protocol controller
        vm.mockCall(
            address(registry), abi.encodeWithSelector(IProtocolController.strategy.selector), abi.encode(strategyAsset)
        );

        // mock the deposit function of the strategy
        vm.mockCall(
            address(strategyAsset), abi.encodeWithSelector(IStrategy.deposit.selector), abi.encode(pendingRewards)
        );

        // mock the checkpoint function of the accountant
        vm.mockCall(accountant, abi.encodeWithSelector(IAccountant.checkpoint.selector), abi.encode(true));
    }

    function test_UpdatesTheRewardForTheReceiver(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it updates the reward for the receiver

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 TOTAL_SUPPLY = 1e20;
        uint256 OWNER_BALANCE = TOTAL_SUPPLY / 20;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // generate plausible fake reward data for a vault
        address token = makeAddr("THIS_IS_A_TOKEN");
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        cloneRewardVault._cheat_override_reward_tokens(tokens);

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            rewardsDuration: 10 days,
            lastUpdateTime: uint32(block.timestamp), // current timestamp before wrapping
            periodFinish: uint32(block.timestamp + 10 days),
            // number of rewards distributed per second
            rewardRate: 1e10,
            // total rewards accumulated per token since the last update, used as a baseline for calculating new rewards.
            rewardPerTokenStored: uint128(TOTAL_SUPPLY / 5)
        });
        cloneRewardVault._cheat_override_reward_data(token, rewardData);
        // Put the account in a state with no rewards paid out and no rewards available to claim
        cloneRewardVault._cheat_override_account_data(
            receiver,
            tokens[0],
            RewardVault.AccountData({
                // Total rewards paid out to the account since the last update.
                rewardPerTokenPaid: 0,
                // Total rewards currently available for the account to claim,
                // based on the difference between rewardPerToken and rewardPerTokenPaid.
                claimable: 0
            })
        );

        // mock the total supply to return the expected value(calling the accountant.totalSupply() function)
        vm.mockCall(
            address(accountant), abi.encodeWithSelector(Accountant.totalSupply.selector), abi.encode(TOTAL_SUPPLY)
        );
        // mock the balance of the account to return 5% of the total supply
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(cloneRewardVault), receiver),
            abi.encode(OWNER_BALANCE)
        );

        _mock_test_dependencies(OWNER_BALANCE, Allocation.MIXED);

        // make the caller deposit the rewards
        vm.prank(caller);
        deposit_mint_wrapper(OWNER_BALANCE, receiver);

        // assert there are new rewards to claim for the account
        assertNotEq(0, cloneRewardVault.getClaimable(token, receiver));
        // assert the reward per token variable in the account is updated with the value of the vault
        assertEq(
            cloneRewardVault.getRewardPerTokenStored(token), cloneRewardVault.getRewardPerTokenPaid(token, receiver)
        );
    }

    function test_WhenTheAllocatorAllocatesAllTheFundsToTheLocker(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it transfer all the ERC20 tokens to the locker

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies of the deposit function
        (IAllocator.Allocation memory allocation,) = _mock_test_dependencies(OWNER_BALANCE, Allocation.STAKEDAO);

        // - assert there is only one target
        // - it has no balance prior to the deposit
        // - it is the expected external strategy
        assertEq(allocation.targets.length, 1);
        assertEq(IERC20(asset).balanceOf(allocation.targets[0]), 0);
        assertEq(allocation.targets[0], TARGET_INHOUSE_STRATEGY);

        // make the caller deposit the rewards
        vm.prank(caller);
        deposit_mint_wrapper(OWNER_BALANCE, address(0));

        // assert the target has the expected balance
        assertEq(IERC20(asset).balanceOf(allocation.targets[0]), OWNER_BALANCE);
    }

    function test_WhenTheAllocatorAllocatesAllTheFundsToConvex(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it transfer all the ERC20 tokens to convex

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies of the deposit function
        (IAllocator.Allocation memory allocation,) = _mock_test_dependencies(OWNER_BALANCE, Allocation.CONVEX);

        // - assert there is only one target
        // - it has no balance prior to the deposit
        // - it is the expected external strategy
        assertEq(allocation.targets.length, 1);
        assertEq(IERC20(asset).balanceOf(allocation.targets[0]), 0);
        assertEq(allocation.targets[0], TARGET_EXTERNAL_STRATEGY);

        // make the caller deposit the rewards
        vm.prank(caller);
        deposit_mint_wrapper(OWNER_BALANCE, address(0));

        // assert the target has the expected balance
        assertEq(IERC20(asset).balanceOf(allocation.targets[0]), OWNER_BALANCE);
    }

    function test_WhenTheAllocatorMixesTheAllocation(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it transfer the tokens based on the returned allocation repartition

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies of the deposit function
        (IAllocator.Allocation memory allocation,) = _mock_test_dependencies(OWNER_BALANCE, Allocation.MIXED);

        // assert that the targets have no balance
        for (uint256 i; i < allocation.targets.length; i++) {
            assertEq(IERC20(asset).balanceOf(allocation.targets[i]), 0);
        }

        // make the caller deposit the rewards
        vm.prank(caller);
        deposit_mint_wrapper(OWNER_BALANCE, address(0));

        // assert that the targets have the correct balance
        for (uint256 i; i < allocation.targets.length; i++) {
            assertEq(IERC20(asset).balanceOf(allocation.targets[i]), allocation.amounts[i]);
        }
    }

    function test_DepositTheFullAllocationToTheStrategy(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it deposit the full allocation to the strategy

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies of the deposit function
        (IAllocator.Allocation memory allocation,) = _mock_test_dependencies(OWNER_BALANCE, Allocation.MIXED);

        // expect the strategy to be called with the allocation
        vm.expectCall(address(strategyAsset), abi.encodeCall(IStrategy.deposit, (allocation, false)), 1);

        // make the caller deposit the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        deposit_mint_wrapper(OWNER_BALANCE, receiver);
    }

    function test_GivenZeroAddressReceiver(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it mints the shares to the sender

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies of the deposit function
        (, IStrategy.PendingRewards memory pendingRewards) = _mock_test_dependencies(OWNER_BALANCE, Allocation.MIXED);

        // expect the checkpoint to be called with the receiver as the recipient
        vm.expectCall(
            address(accountant),
            abi.encodeCall(
                IAccountant.checkpoint,
                (
                    gauge,
                    address(0),
                    caller, // this is what we are testing
                    uint128(OWNER_BALANCE),
                    pendingRewards,
                    false
                )
            ),
            1
        );

        // make the caller deposit the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        deposit_mint_wrapper(OWNER_BALANCE, address(0));
    }

    function test_GivenAnAddressReceiver(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it mints the shares to the receiver

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);
        // uint256 beforeReceiverBalance = IERC20(asset).balanceOf(receiver);

        // mock the dependencies of the withdraw function
        (, IStrategy.PendingRewards memory pendingRewards) = _mock_test_dependencies(OWNER_BALANCE, Allocation.MIXED);

        // expect the checkpoint to be called with the receiver as the recipient
        vm.expectCall(
            address(accountant),
            abi.encodeCall(
                IAccountant.checkpoint,
                (
                    gauge,
                    address(0),
                    receiver, // this is what we are testing
                    uint128(OWNER_BALANCE),
                    pendingRewards,
                    false
                )
            ),
            1
        );

        // make the caller deposit the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        deposit_mint_wrapper(OWNER_BALANCE, receiver);
    }

    function test_RevertsIfCallingAccountantCheckpointReverts(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it reverts if calling accountant checkpoint reverts

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies of the withdraw function
        (, IStrategy.PendingRewards memory pendingRewards) = _mock_test_dependencies(OWNER_BALANCE, Allocation.MIXED);

        // force the deposit to the strategyto revert
        vm.mockCallRevert(
            address(accountant),
            abi.encodeWithSelector(
                IAccountant.checkpoint.selector,
                gauge,
                address(0),
                receiver,
                uint128(OWNER_BALANCE),
                pendingRewards,
                false
            ),
            abi.encode("UNEXPECTED_ERROR")
        );
        vm.expectRevert(abi.encode("UNEXPECTED_ERROR"));

        // make the caller deposit the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        deposit_mint_wrapper(OWNER_BALANCE, receiver);
    }

    function test_RevertsIfTheDepositToTheStrategyReverts(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it reverts if the deposit to the strategy reverts

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies of the withdraw function
        (IAllocator.Allocation memory allocation,) = _mock_test_dependencies(OWNER_BALANCE, Allocation.MIXED);

        // force the deposit to the strategyto revert
        vm.mockCallRevert(
            address(strategyAsset),
            abi.encodeWithSelector(IStrategy.deposit.selector, allocation, false),
            abi.encode("UNEXPECTED_ERROR")
        );
        vm.expectRevert(abi.encode("UNEXPECTED_ERROR"));

        // make the caller deposit the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        deposit_mint_wrapper(OWNER_BALANCE, receiver);
    }

    function test_RevertsIfOneOfTheERC20TransferReverts(address caller, address receiver, uint256 strategyCoinFlip)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it reverts if one of the ERC20 transfer reverts

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies of the withdraw function
        _mock_test_dependencies(OWNER_BALANCE, Allocation.MIXED);

        // force one of the transfer to revert
        uint256[2] memory amounts = [OWNER_BALANCE / 3, OWNER_BALANCE / 3 * 2];
        address[2] memory targets = [TARGET_INHOUSE_STRATEGY, TARGET_EXTERNAL_STRATEGY];
        uint256 index = strategyCoinFlip % 2; // 0 or 1
        vm.mockCallRevert(
            address(asset),
            abi.encodeWithSelector(IERC20.transferFrom.selector, caller, targets[index], amounts[index]),
            abi.encode("UNEXPECTED_ERROR")
        );
        vm.expectRevert(abi.encode("UNEXPECTED_ERROR"));

        // make the caller deposit the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        deposit_mint_wrapper(OWNER_BALANCE, receiver);
    }

    function test_EmitsTheDepositEvent(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it emits a deposit event

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies of the withdraw function
        _mock_test_dependencies(OWNER_BALANCE, Allocation.MIXED);

        // make the caller deposit the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(caller, receiver, OWNER_BALANCE, OWNER_BALANCE);
        deposit_mint_wrapper(OWNER_BALANCE, receiver);
    }

    function test_ReturnsTheAmountOfAssetsDeposited(address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns the amount of assets deposited

        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: receiver, newLabel: "receiver"});

        // set the owner balance and approve half the balance
        uint256 OWNER_BALANCE = 1e18;
        deal(asset, caller, OWNER_BALANCE);
        vm.prank(caller);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies of the withdraw function
        _mock_test_dependencies(OWNER_BALANCE, Allocation.MIXED);

        // make the caller deposit the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        uint256 shares = deposit_mint_wrapper(OWNER_BALANCE, receiver);
        assertEq(shares, OWNER_BALANCE);
    }
}
