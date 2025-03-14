pragma solidity 0.8.28;

import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {RewardVault} from "src/RewardVault.sol";
import {Accountant} from "src/Accountant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract RewardVault__withdraw is RewardVaultBaseTest {
    address internal gauge = makeAddr("gauge");
    address internal asset;
    address internal strategyAsset;
    // This implementation is the harnessed version of the reward vault cloned with the variables above
    RewardVaultHarness internal cloneRewardVault;

    // Due to the 1:1 relationship of the assets and the shares, the withdraw and the redeem functions
    // do the same thing. This function is a wrapper that calls the appropriate function based on the context
    // of the test. This is a virtual allowing the redeem test to override it to call `redeem` instead of `withdraw`.
    function withdraw_redeem_wrapper(uint256 assets, address receiver, address owner)
        internal
        virtual
        returns (uint256)
    {
        return cloneRewardVault.withdraw(assets, receiver, owner);
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

    function _mock_test_dependencies()
        internal
        returns (IAllocator.Allocation memory allocation, IStrategy.PendingRewards memory pendingRewards)
    {
        // set the allocation and pending rewards to mock values
        allocation = IAllocator.Allocation({
            gauge: gauge,
            harvested: false,
            targets: new address[](0),
            amounts: new uint256[](0)
        });
        pendingRewards = IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0});

        // mock the allocator returned by the protocol controller
        vm.mockCall(
            address(cloneRewardVault.PROTOCOL_CONTROLLER()),
            abi.encodeWithSelector(IProtocolController.allocator.selector, protocolId),
            abi.encode(address(allocator))
        );

        // mock the withdrawal allocation returned by the allocator
        vm.mockCall(
            address(allocator),
            abi.encodeWithSelector(IAllocator.getWithdrawalAllocation.selector),
            abi.encode(allocation)
        );

        // mock the strategy returned by the protocol controller
        vm.mockCall(
            address(registry), abi.encodeWithSelector(IProtocolController.strategy.selector), abi.encode(strategyAsset)
        );

        // mock the withdraw function of the strategy
        vm.mockCall(
            address(strategyAsset), abi.encodeWithSelector(IStrategy.withdraw.selector), abi.encode(pendingRewards)
        );

        // mock the checkpoint function of the accountant
        vm.mockCall(accountant, abi.encodeWithSelector(IAccountant.checkpoint.selector), abi.encode(true));
    }

    function test_GivenSenderIsNotOwner(address owner, address caller)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it reverts if the allowance is not enough
        // it update the allowance when it is finite

        _assumeUnlabeledAddress(owner);
        _assumeUnlabeledAddress(caller);
        vm.assume(owner != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: owner, newLabel: "owner"});

        uint256 OWNER_BALANCE = 1e18;
        uint256 OWNER_ALLOWED_BALANCE = OWNER_BALANCE / 2;

        // set the owner balance and approve half the balance
        deal(asset, owner, OWNER_BALANCE);
        vm.prank(owner);
        cloneRewardVault.approve(caller, OWNER_ALLOWED_BALANCE);

        // attempt to withdraw the rewards with an allowance that is not enough
        vm.expectRevert(RewardVault.NotApproved.selector);
        vm.prank(caller);
        withdraw_redeem_wrapper(OWNER_BALANCE, address(0), owner);

        // mock the dependencies of the withdraw function
        _mock_test_dependencies();

        // we airdrop enought assets to the reward vault to cover the withdrawal
        deal(address(asset), address(cloneRewardVault), OWNER_BALANCE);

        // make the caller withdraw the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        withdraw_redeem_wrapper(OWNER_ALLOWED_BALANCE - 1, address(0), owner);

        // allowance must be 1, because
        // - the owner allowed the called to spend 1 + OWNER_BALANCE / 2
        // - the caller withdrew OWNER_BALANCE / 2
        assertEq(cloneRewardVault.allowance(owner, caller), 1);
    }

    function test_UpdatesTheRewardForTheOwner(address owner, address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it updates the reward for the owner

        _assumeUnlabeledAddress(owner);
        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(owner != address(0));
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.assume(caller != owner);
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: owner, newLabel: "owner"});
        vm.label({account: receiver, newLabel: "receiver"});

        uint256 OWNER_BALANCE = 1e16;
        uint256 TOTAL_SUPPLY = 1e18;

        // set the owner balance and approve half the balance
        deal(asset, owner, OWNER_BALANCE);
        vm.prank(owner);
        cloneRewardVault.approve(caller, OWNER_BALANCE);

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
            owner,
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
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(cloneRewardVault), owner),
            abi.encode(TOTAL_SUPPLY / 20) // 5% of the total supply
        );

        // mock the dependencies of the withdraw function
        _mock_test_dependencies();

        // we airdrop enought assets to the reward vault to cover the withdrawal
        deal(address(asset), address(cloneRewardVault), OWNER_BALANCE);

        // make the caller withdraw the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        withdraw_redeem_wrapper(OWNER_BALANCE, receiver, owner);

        // assert there are new rewards to claim for the account
        assertNotEq(0, cloneRewardVault.getClaimable(token, owner));
        // assert the reward per token variable in the account is updated with the value of the vault
        assertEq(cloneRewardVault.getRewardPerTokenStored(token), cloneRewardVault.getRewardPerTokenPaid(token, owner));
    }

    function test_TellsTheStrategyToWithdrawTheAssets(address owner, address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it tells the strategy to withdraw the assets

        _assumeUnlabeledAddress(owner);
        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(owner != address(0));
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.assume(caller != owner);
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: owner, newLabel: "owner"});
        vm.label({account: receiver, newLabel: "receiver"});

        uint256 OWNER_BALANCE = 1e18;

        // set the owner balance and approve half the balance
        deal(asset, owner, OWNER_BALANCE);
        vm.prank(owner);
        cloneRewardVault.approve(caller, OWNER_BALANCE);

        // mock the dependencies of the withdraw function and return the allocation and pending rewards used for mocking
        (IAllocator.Allocation memory allocation,) = _mock_test_dependencies();

        // we airdrop enought assets to the reward vault to cover the withdrawal
        deal(address(asset), address(cloneRewardVault), OWNER_BALANCE);

        // vm.mockCall(accountant, abi.encodeWithSelector(IAccountant.checkpoint.selector), abi.encode(true));
        vm.expectCall(address(strategyAsset), abi.encodeWithSelector(IStrategy.withdraw.selector, allocation), 1);

        // make the caller withdraw the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        withdraw_redeem_wrapper(OWNER_BALANCE, receiver, owner);
    }

    function test_TellsTheAccoutantToBurnTheTokens(address owner, address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it tells the accoutant to burn the tokens

        _assumeUnlabeledAddress(owner);
        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(owner != address(0));
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.assume(caller != owner);
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: owner, newLabel: "owner"});
        vm.label({account: receiver, newLabel: "receiver"});

        uint256 OWNER_BALANCE = 1e18;

        // set the owner balance and approve half the balance
        deal(asset, owner, OWNER_BALANCE);
        vm.prank(owner);
        cloneRewardVault.approve(caller, OWNER_BALANCE);

        // mock the dependencies of the withdraw function and return the allocation and pending rewards used for mocking
        (IAllocator.Allocation memory allocation, IStrategy.PendingRewards memory pendingRewards) =
            _mock_test_dependencies();

        // we airdrop enought assets to the reward vault to cover the withdrawal
        deal(address(asset), address(cloneRewardVault), OWNER_BALANCE);

        vm.expectCall(
            address(accountant),
            abi.encodeCall(
                IAccountant.checkpoint,
                (gauge, owner, address(0), uint128(OWNER_BALANCE), pendingRewards, allocation.harvested)
            ),
            1
        );

        // make the caller withdraw the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        withdraw_redeem_wrapper(OWNER_BALANCE, receiver, owner);
    }

    function test_TransfersTheAssetsToTheReceiver(address owner, address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it transfers the assets to the receiver

        _assumeUnlabeledAddress(owner);
        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(owner != address(0));
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.assume(caller != owner);
        vm.assume(receiver != owner);
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: owner, newLabel: "owner"});
        vm.label({account: receiver, newLabel: "receiver"});

        uint256 OWNER_BALANCE = 1e18;

        // set the owner balance and approve half the balance
        deal(asset, owner, OWNER_BALANCE);
        vm.prank(owner);
        cloneRewardVault.approve(caller, OWNER_BALANCE);

        // mock the dependencies of the withdraw function
        _mock_test_dependencies();

        // we airdrop enought assets to the reward vault to cover the withdrawal
        deal(address(asset), address(cloneRewardVault), OWNER_BALANCE);

        // make the caller withdraw the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        withdraw_redeem_wrapper(OWNER_BALANCE, receiver, owner);

        // assert that the receiver received the assets from the reward vault
        assertEq(IERC20(asset).balanceOf(address(cloneRewardVault)), 0);
        assertEq(IERC20(asset).balanceOf(receiver), OWNER_BALANCE);
    }

    function test_EmitsTheEvent(address owner, address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it emits a withdraw event

        _assumeUnlabeledAddress(owner);
        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(owner != address(0));
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.assume(caller != owner);
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: owner, newLabel: "owner"});
        vm.label({account: receiver, newLabel: "receiver"});

        uint256 OWNER_BALANCE = 1e18;

        // set the owner balance and approve half the balance
        deal(asset, owner, OWNER_BALANCE);
        vm.prank(owner);
        cloneRewardVault.approve(caller, OWNER_BALANCE);

        // mock the dependencies of the withdraw function
        _mock_test_dependencies();

        // we airdrop enought assets to the reward vault to cover the withdrawal
        deal(address(asset), address(cloneRewardVault), OWNER_BALANCE);

        // make the caller withdraw the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(caller, receiver, owner, OWNER_BALANCE, OWNER_BALANCE);
        withdraw_redeem_wrapper(OWNER_BALANCE, receiver, owner);
    }

    function test_ReturnsTheAmountOfSharesBurned(address owner, address caller, address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns the amount of shares burned

        _assumeUnlabeledAddress(owner);
        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        vm.assume(owner != address(0));
        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.assume(caller != owner);
        vm.label({account: caller, newLabel: "caller"});
        vm.label({account: owner, newLabel: "owner"});
        vm.label({account: receiver, newLabel: "receiver"});

        uint256 OWNER_BALANCE = 1e18;

        // set the owner balance and approve half the balance
        deal(asset, owner, OWNER_BALANCE);
        vm.prank(owner);
        cloneRewardVault.approve(caller, OWNER_BALANCE);

        // mock the dependencies of the withdraw function
        _mock_test_dependencies();

        // we airdrop enought assets to the reward vault to cover the withdrawal
        deal(address(asset), address(cloneRewardVault), OWNER_BALANCE);

        // make the caller withdraw the rewards. It should succeed because the allowance is enough
        vm.prank(caller);
        uint256 sharesBurned = withdraw_redeem_wrapper(OWNER_BALANCE, receiver, owner);

        // assert that the shares burned are the same as the amount of assets withdrawn
        assertEq(sharesBurned, OWNER_BALANCE);
    }
}
