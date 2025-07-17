// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseTest} from "test/BaseTest.t.sol";

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ResolvProtocol} from "@address-book/src/ResolvEthereum.sol";

import {DepositorPreLaunch} from "src/DepositorPreLaunch.sol";
import {ILiquidityGaugeV4} from "src/interfaces/ILiquidityGaugeV4.sol";

import {ISdToken} from "src/interfaces/ISdToken.sol";
import {LockerPreLaunch} from "src/LockerPreLaunch.sol";
import {PreLaunchDeploy} from "script/common/PreLaunch/01_deploy.s.sol";

contract PreLaunchLockerTest is BaseTest, PreLaunchDeploy {
    IERC20 internal constant RESOLV = IERC20(ResolvProtocol.RESOLV);
    LockerPreLaunch internal PRELAUNCH_LOCKER;
    ISdToken internal SD_TOKEN;
    ILiquidityGaugeV4 internal GAUGE;
    address internal LOCKER;

    address internal postPreLaunchLocker;
    address internal depositor;

    function setUp() public virtual {
        vm.createSelectFork("mainnet");

        // fetch the gauge implementation address from the gauge proxy
        address gaugeImplementation = address(
            uint160(uint256(vm.load(address(GAUGE), bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1))))
        );

        // Call the deployment script's _run function
        (address sdToken, address gauge, address preLaunchLocker, address locker) =
            _run(address(RESOLV), "Stake DAO Resolv", "sdRESOLV", 0);

        SD_TOKEN = ISdToken(sdToken);
        GAUGE = ILiquidityGaugeV4(gauge);
        PRELAUNCH_LOCKER = LockerPreLaunch(preLaunchLocker);
        LOCKER = locker;

        // label the important addresses for the tests
        vm.label(address(PRELAUNCH_LOCKER), "LockerPreLaunch");
        vm.label(address(RESOLV), "RESOLV");
        vm.label(address(SD_TOKEN), "SD_TOKEN");
        vm.label(address(DAO.GOVERNANCE), "GOVERNANCE");
        vm.label(address(DAO.SDT), "SDT");
        vm.label(address(DAO.VESDT), "VESDT");
        vm.label(address(DAO.VESDT_BOOST_PROXY), "VESDT_BOOST_PROXY");
        vm.label(address(GAUGE), "GAUGE_PROXY");
        vm.label(gaugeImplementation, "GAUGE_IMPLEMENTATION");
    }

    function test_PreLaunchLockerState() external view {
        assertEq(address(PRELAUNCH_LOCKER.token()), address(RESOLV));
        assertEq(address(PRELAUNCH_LOCKER.sdToken()), address(SD_TOKEN));
        assertEq(address(PRELAUNCH_LOCKER.gauge()), address(GAUGE));
    }

    function test_GaugeState() external view {
        assertEq(GAUGE.staking_token(), address(SD_TOKEN));
        assertEq(GAUGE.admin(), LOCKER);
        assertEq(GAUGE.SDT(), DAO.SDT);
        assertEq(GAUGE.voting_escrow(), DAO.VESDT);
        assertEq(GAUGE.veBoost_proxy(), DAO.VESDT_BOOST_PROXY);
    }

    ////////////////////////////////////////////////////////////////
    /// --- Cancel Locker
    ///////////////////////////////////////////////////////////////

    function test_SetsTheStateToCANCELED() external {
        // it sets the state to CANCELED

        vm.prank(PRELAUNCH_LOCKER.governance());
        PRELAUNCH_LOCKER.cancelLocker();

        assertEq(uint256(PRELAUNCH_LOCKER.state()), uint256(LockerPreLaunch.STATE.CANCELED));
    }

    ////////////////////////////////////////////////////////////////
    /// --- Deposit
    ///////////////////////////////////////////////////////////////

    function test_DepositGivenTheStakeIsTrue() external {
        // 1. it mints sdTokens to the PRELAUNCH_LOCKER
        // 2. it stakes the sdTokens in the gauge for the caller
        // 3. it emits the TokenStaked event

        address caller = makeAddr("caller");
        uint256 amount = 1e25;

        // mint the token to the caller and approve the PRELAUNCH_LOCKER to spend the token
        deal(address(RESOLV), caller, amount);
        vm.prank(caller);
        RESOLV.approve(address(PRELAUNCH_LOCKER), amount);

        // 3. expect the event to be emitted
        vm.expectEmit();
        emit TokenStaked(caller, caller, address(GAUGE), amount);

        // expect the internal calls to be made
        vm.expectCall(
            address(SD_TOKEN), abi.encodeWithSelector(ISdToken.mint.selector, address(PRELAUNCH_LOCKER), amount), 1
        );
        vm.expectCall(address(SD_TOKEN), abi.encodeWithSelector(IERC20.approve.selector, address(GAUGE), amount), 1);
        vm.expectCall(
            address(GAUGE), abi.encodeWithSelector(ILiquidityGaugeV4.deposit.selector, amount, caller, false), 1
        );

        // deposit the tokens
        vm.prank(caller);
        PRELAUNCH_LOCKER.deposit(amount, true);

        // assert the tokens have been transferred to the PRELAUNCH_LOCKER
        assertEq(RESOLV.balanceOf(address(caller)), 0);
        assertEq(RESOLV.balanceOf(address(PRELAUNCH_LOCKER)), amount);

        // 1. assert the sdTokens have been minted and transferred to the gauge
        assertEq(SD_TOKEN.balanceOf(address(caller)), 0);
        assertEq(SD_TOKEN.balanceOf(address(PRELAUNCH_LOCKER)), 0);
        assertEq(SD_TOKEN.balanceOf(address(GAUGE)), amount);

        // assert the gauge tracks the caller's balance
        assertEq(GAUGE.balanceOf(address(caller)), amount);
        assertEq(GAUGE.balanceOf(address(PRELAUNCH_LOCKER)), 0);
    }

    function test_DepositGivenTheStakeIsFalse() external {
        // it mints sdTokens to the caller

        address caller = makeAddr("caller");
        uint256 amount = 1e25;

        // mint the token to the caller and approve the PRELAUNCH_LOCKER to spend the token
        deal(address(RESOLV), caller, amount);
        vm.prank(caller);
        RESOLV.approve(address(PRELAUNCH_LOCKER), amount);

        // 3. expect the internal calls to be made
        vm.expectCall(address(SD_TOKEN), abi.encodeWithSelector(ISdToken.mint.selector, address(caller), amount), 1);

        // deposit the tokens
        vm.prank(caller);
        PRELAUNCH_LOCKER.deposit(amount, false);

        // assert the tokens have been transferred to the PRELAUNCH_LOCKER
        assertEq(RESOLV.balanceOf(address(caller)), 0);
        assertEq(RESOLV.balanceOf(address(PRELAUNCH_LOCKER)), amount);

        // 1. assert the sdTokens have been minted to the caller
        assertEq(SD_TOKEN.balanceOf(address(caller)), amount);
        assertEq(SD_TOKEN.balanceOf(address(PRELAUNCH_LOCKER)), 0);
        assertEq(SD_TOKEN.balanceOf(address(GAUGE)), 0);

        // assert the gauge balances have not changed
        assertEq(GAUGE.balanceOf(address(caller)), 0);
        assertEq(GAUGE.balanceOf(address(PRELAUNCH_LOCKER)), 0);
    }

    function test_DepositGivenAReceiverWhenTheStakeIsTrue() external {
        // 1. it stakes the sdTokens in the gauge for the receiver
        // 2. it emits the TokenStaked event

        address caller = makeAddr("caller");
        address receiver = makeAddr("receiver");
        uint256 amount = 1e25;

        // mint the token to the caller and approve the PRELAUNCH_LOCKER to spend the token
        deal(address(RESOLV), caller, amount);
        vm.prank(caller);
        RESOLV.approve(address(PRELAUNCH_LOCKER), amount);

        // 3. expect the event to be emitted
        vm.expectEmit();
        emit TokenStaked(caller, receiver, address(GAUGE), amount);

        // expect the internal calls to be made
        vm.expectCall(
            address(SD_TOKEN), abi.encodeWithSelector(ISdToken.mint.selector, address(PRELAUNCH_LOCKER), amount), 1
        );
        vm.expectCall(address(SD_TOKEN), abi.encodeWithSelector(IERC20.approve.selector, address(GAUGE), amount), 1);
        vm.expectCall(
            address(GAUGE), abi.encodeWithSelector(ILiquidityGaugeV4.deposit.selector, amount, receiver, false), 1
        );

        // deposit the tokens
        vm.prank(caller);
        PRELAUNCH_LOCKER.deposit(amount, true, receiver);

        // assert the tokens have been transferred to the PRELAUNCH_LOCKER
        assertEq(RESOLV.balanceOf(address(caller)), 0);
        assertEq(RESOLV.balanceOf(address(PRELAUNCH_LOCKER)), amount);

        // 1. assert the sdTokens have been minted and transferred to the gauge
        assertEq(SD_TOKEN.balanceOf(address(caller)), 0);
        assertEq(SD_TOKEN.balanceOf(address(PRELAUNCH_LOCKER)), 0);
        assertEq(SD_TOKEN.balanceOf(address(GAUGE)), amount);

        // assert the gauge tracks the receiver's balance
        assertEq(GAUGE.balanceOf(address(receiver)), amount);
        assertEq(GAUGE.balanceOf(address(caller)), 0);
        assertEq(GAUGE.balanceOf(address(PRELAUNCH_LOCKER)), 0);
    }

    function test_DepositGivenAReceiverWhenTheStakeIsFalse() external {
        // it mints sdTokens to the receiver

        address caller = makeAddr("caller");
        address receiver = makeAddr("receiver");
        uint256 amount = 1e25;

        // mint the token to the caller and approve the PRELAUNCH_LOCKER to spend the token
        deal(address(RESOLV), caller, amount);
        vm.prank(caller);
        RESOLV.approve(address(PRELAUNCH_LOCKER), amount);

        // 3. expect the internal calls to be made
        vm.expectCall(address(SD_TOKEN), abi.encodeWithSelector(ISdToken.mint.selector, address(receiver), amount), 1);

        // deposit the tokens
        vm.prank(caller);
        PRELAUNCH_LOCKER.deposit(amount, false, receiver);

        // assert the tokens have been transferred to the PRELAUNCH_LOCKER
        assertEq(RESOLV.balanceOf(address(caller)), 0);
        assertEq(RESOLV.balanceOf(address(PRELAUNCH_LOCKER)), amount);

        // 1. assert the sdTokens have been minted to the receiver
        assertEq(SD_TOKEN.balanceOf(address(caller)), 0);
        assertEq(SD_TOKEN.balanceOf(address(PRELAUNCH_LOCKER)), 0);
        assertEq(SD_TOKEN.balanceOf(address(receiver)), amount);

        // assert the gauge balances have not changed
        assertEq(GAUGE.balanceOf(address(caller)), 0);
        assertEq(GAUGE.balanceOf(address(PRELAUNCH_LOCKER)), 0);
        assertEq(GAUGE.balanceOf(address(receiver)), 0);
    }

    ////////////////////////////////////////////////////////////////
    /// --- Force Cancel Locker
    ///////////////////////////////////////////////////////////////

    function test_ForceCancelLockerSetsTheStateToCANCELED() external {
        // it sets the state to CANCELED
        // It needs a first deposit.
        address caller = makeAddr("caller");
        uint256 amount = 1e25;

        // mint the token to the caller and approve the PRELAUNCH_LOCKER to spend the token
        deal(address(RESOLV), caller, amount);
        vm.prank(caller);
        RESOLV.approve(address(PRELAUNCH_LOCKER), amount);

        vm.prank(caller);
        PRELAUNCH_LOCKER.deposit(amount, true);

        // fast forward the timestamp by the delay and expect the state to be CANCELED
        vm.warp(block.timestamp + PRELAUNCH_LOCKER.FORCE_CANCEL_DELAY());
        PRELAUNCH_LOCKER.forceCancelLocker();
        assertEq(uint256(PRELAUNCH_LOCKER.state()), uint256(LockerPreLaunch.STATE.CANCELED));
    }

    ////////////////////////////////////////////////////////////////
    /// --- Transfer Governance
    ///////////////////////////////////////////////////////////////

    function test_SetsTheNewGovernance() external {
        // it sets the new governance

        address newGovernance = makeAddr("newGovernance");

        vm.prank(PRELAUNCH_LOCKER.governance());
        PRELAUNCH_LOCKER.transferGovernance(newGovernance);

        assertEq(PRELAUNCH_LOCKER.governance(), newGovernance);
    }

    ////////////////////////////////////////////////////////////////
    /// --- Lock
    ///////////////////////////////////////////////////////////////

    modifier setupDepositor() {
        // deploy the locker that will be used once all the protocol is deployed (after the pre-launch period)
        postPreLaunchLocker = address(new LockerMock());

        // deploy the depositor
        depositor = address(
            new DepositorPreLaunch(
                address(RESOLV),
                postPreLaunchLocker,
                address(SD_TOKEN),
                address(GAUGE),
                1_000,
                address(PRELAUNCH_LOCKER)
            )
        );

        _;
    }

    function test_SetsTheDepositorToTheGivenValue() external setupDepositor {
        // it sets the depositor to the given value

        uint256 balance = 1e25;
        deal(address(RESOLV), address(PRELAUNCH_LOCKER), balance);

        // expect the depositor to call the definitive locker
        vm.expectCall(postPreLaunchLocker, abi.encodeWithSelector(LockerMock.createLock.selector), 1);

        vm.prank(PRELAUNCH_LOCKER.governance());
        PRELAUNCH_LOCKER.lock(depositor);

        assertEq(address(PRELAUNCH_LOCKER.depositor()), depositor);
    }

    function test_TransfersTheBalanceOfTokenToTheFinalLocker() external setupDepositor {
        // it transfers the balance of token to the final locker

        uint256 balance = 1e25;
        deal(address(RESOLV), address(PRELAUNCH_LOCKER), balance);

        assertEq(RESOLV.balanceOf(address(PRELAUNCH_LOCKER)), balance);

        vm.prank(PRELAUNCH_LOCKER.governance());
        PRELAUNCH_LOCKER.lock(depositor);

        assertEq(RESOLV.balanceOf(address(PRELAUNCH_LOCKER)), 0);
        assertEq(RESOLV.balanceOf(address(postPreLaunchLocker)), balance);
    }

    function test_TransfersTheOperatorPermissionOfTheSdTokenToTheDepositor() external setupDepositor {
        // it transfers the operator permission of the sdToken to the depositor

        deal(address(SD_TOKEN), address(PRELAUNCH_LOCKER), 10);

        assertEq(SD_TOKEN.operator(), address(PRELAUNCH_LOCKER));

        // airdrop some RESOLV to the PRELAUNCH_LOCKER in order to be able to lock it
        deal(address(RESOLV), address(PRELAUNCH_LOCKER), 10);

        vm.prank(PRELAUNCH_LOCKER.governance());
        PRELAUNCH_LOCKER.lock(depositor);

        assertEq(SD_TOKEN.operator(), address(depositor));
    }

    function test_SetsTheStateToACTIVE() external setupDepositor {
        // it sets the state to ACTIVE
        deal(address(RESOLV), address(PRELAUNCH_LOCKER), 10);

        assertEq(uint256(PRELAUNCH_LOCKER.state()), uint256(LockerPreLaunch.STATE.IDLE));

        vm.prank(PRELAUNCH_LOCKER.governance());
        PRELAUNCH_LOCKER.lock(depositor);

        assertEq(uint256(PRELAUNCH_LOCKER.state()), uint256(LockerPreLaunch.STATE.ACTIVE));
    }

    ////////////////////////////////////////////////////////////////
    /// --- WITHDRAW
    ///////////////////////////////////////////////////////////////

    function test_WithdrawGivenTheStakeIsTrue() external {
        // it transfers caller gauge token and burn the associated sdToken
        // it transfers back the default token to the caller

        address caller = makeAddr("caller");
        uint256 balance = 1e25;
        uint256 amount = 1e22;

        // manually set the state to CANCELED
        vm.prank(PRELAUNCH_LOCKER.governance());
        PRELAUNCH_LOCKER.cancelLocker();

        // set the expected amount of gauge tokens the caller is expected to have
        deal(address(SD_TOKEN), address(caller), amount);
        vm.prank(caller);
        SD_TOKEN.approve(address(GAUGE), amount);
        vm.prank(caller);
        GAUGE.deposit(amount, caller, false);

        // set the total balance to the locker
        deal(address(RESOLV), address(PRELAUNCH_LOCKER), balance);

        // approve the locker to spend the gauge tokens
        vm.prank(caller);
        GAUGE.approve(address(PRELAUNCH_LOCKER), amount);

        // withdraw the amount
        vm.prank(caller);
        PRELAUNCH_LOCKER.withdraw(amount, true);

        // verify the balances are correct after the withdrawal
        assertEq(SD_TOKEN.balanceOf(caller), 0);
        assertEq(SD_TOKEN.balanceOf(address(PRELAUNCH_LOCKER)), 0);

        assertEq(RESOLV.balanceOf(caller), amount);
        assertEq(RESOLV.balanceOf(address(PRELAUNCH_LOCKER)), balance - amount);

        assertEq(GAUGE.balanceOf(caller), 0);
        assertEq(GAUGE.balanceOf(address(PRELAUNCH_LOCKER)), 0);
    }

    function test_WithdrawGivenTheStakeIsFalse() external {
        // it burn the sdToken held by the caller
        // it transfers back the default token to the caller

        address caller = makeAddr("caller");
        uint256 balance = 1e25;
        uint256 amount = 1e22;

        // mint the total balance to the locker
        deal(address(RESOLV), address(PRELAUNCH_LOCKER), balance);

        // mint the amount the caller is expected to have
        deal(address(SD_TOKEN), caller, amount);

        // approve the locker to spend the sdToken held by the caller
        vm.prank(caller);
        SD_TOKEN.approve(address(PRELAUNCH_LOCKER), amount);

        // verify the initial balances are correct
        assertEq(SD_TOKEN.balanceOf(caller), amount);
        assertEq(RESOLV.balanceOf(caller), 0);
        assertEq(RESOLV.balanceOf(address(PRELAUNCH_LOCKER)), balance);

        // manually set the state to CANCELED
        vm.prank(PRELAUNCH_LOCKER.governance());
        PRELAUNCH_LOCKER.cancelLocker();

        // withdraw the amount
        vm.prank(caller);
        PRELAUNCH_LOCKER.withdraw(amount, false);

        // verify the balances are correct after the withdrawal
        assertEq(SD_TOKEN.balanceOf(caller), 0);
        assertEq(RESOLV.balanceOf(caller), amount);
        assertEq(RESOLV.balanceOf(address(PRELAUNCH_LOCKER)), balance - amount);
        assertEq(SD_TOKEN.balanceOf(address(PRELAUNCH_LOCKER)), 0);
    }

    /// @notice Event emitted each time a user stakes their sdTokens.
    /// @param caller The address who called the function.
    /// @param receiver The address who received the gauge RESOLV.
    /// @param gauge The gauge that the sdTokens were staked to.
    /// @param amount The amount of sdTokens staked.
    event TokenStaked(address indexed caller, address indexed receiver, address indexed gauge, uint256 amount);
}

contract LockerMock {
    function createLock(uint256 amount, uint256 unlockTime) external {}
}
