// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";
import {YieldnestProtocol} from "address-book/src/YieldnestEthereum.sol";
import {PreLaunchBaseDepositor} from "src/common/depositor/PreLaunchBaseDepositor.sol";
import {ILiquidityGaugeV4} from "src/common/interfaces/ILiquidityGaugeV4.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {BaseTest} from "test/BaseTest.t.sol";

contract PreLaunchLockerTest is BaseTest {
    PreLaunchLocker internal constant LOCKER = PreLaunchLocker(YieldnestProtocol.PRELAUNCH_LOCKER);
    IERC20 internal constant YND = IERC20(YieldnestProtocol.YND);
    ISdToken internal constant SDYND = ISdToken(YieldnestProtocol.SDYND);
    ILiquidityGaugeV4 internal constant GAUGE = ILiquidityGaugeV4(YieldnestProtocol.GAUGE);

    address internal postPreLaunchLocker;
    address internal depositor;

    function setUp() public virtual {
        vm.createSelectFork("mainnet", 22_537_535);

        // fetch the gauge implementation address from the gauge proxy
        address gaugeImplementation = address(
            uint160(uint256(vm.load(address(GAUGE), bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1))))
        );

        // label the important addresses for the tests
        vm.label(address(LOCKER), "PreLaunchLocker");
        vm.label(address(YND), "YND");
        vm.label(address(SDYND), "SDYND");
        vm.label(address(DAO.GOVERNANCE), "GOVERNANCE");
        vm.label(address(DAO.SDT), "SDT");
        vm.label(address(DAO.VESDT), "VESDT");
        vm.label(address(DAO.VESDT_BOOST_PROXY), "VESDT_BOOST_PROXY");
        vm.label(address(GAUGE), "GAUGE_PROXY");
        vm.label(gaugeImplementation, "GAUGE_IMPLEMENTATION");
    }

    function test_PreLaunchLockerState() external view {
        assertEq(address(LOCKER.token()), address(YND));
        assertEq(address(LOCKER.sdToken()), address(SDYND));
        assertEq(address(LOCKER.gauge()), address(GAUGE));
    }

    function test_GaugeState() external view {
        assertEq(GAUGE.staking_token(), address(SDYND));
        assertEq(GAUGE.admin(), DAO.GOVERNANCE);
        assertEq(GAUGE.SDT(), DAO.SDT);
        assertEq(GAUGE.voting_escrow(), DAO.VESDT);
        assertEq(GAUGE.veBoost_proxy(), DAO.VESDT_BOOST_PROXY);
    }

    ////////////////////////////////////////////////////////////////
    /// --- Cancel Locker
    ///////////////////////////////////////////////////////////////

    function test_SetsTheStateToCANCELED() external {
        // it sets the state to CANCELED

        vm.prank(LOCKER.governance());
        LOCKER.cancelLocker();

        assertEq(uint256(LOCKER.state()), uint256(PreLaunchLocker.STATE.CANCELED));
    }

    ////////////////////////////////////////////////////////////////
    /// --- Deposit
    ///////////////////////////////////////////////////////////////

    function test_DepositGivenTheStakeIsTrue() external {
        // 1. it mints sdTokens to the LOCKER
        // 2. it stakes the sdTokens in the gauge for the caller
        // 3. it emits the TokensStaked event

        address caller = makeAddr("caller");
        uint256 amount = 1e25;

        // mint the token to the caller and approve the LOCKER to spend the token
        deal(address(YND), caller, amount);
        vm.prank(caller);
        YND.approve(address(LOCKER), amount);

        // 3. expect the event to be emitted
        vm.expectEmit();
        emit TokensStaked(caller, caller, address(GAUGE), amount);

        // expect the internal calls to be made
        vm.expectCall(address(SDYND), abi.encodeWithSelector(ISdToken.mint.selector, address(LOCKER), amount), 1);
        vm.expectCall(address(SDYND), abi.encodeWithSelector(IERC20.approve.selector, address(GAUGE), amount), 1);
        vm.expectCall(
            address(GAUGE), abi.encodeWithSelector(ILiquidityGaugeV4.deposit.selector, amount, caller, false), 1
        );

        // deposit the tokens
        vm.prank(caller);
        LOCKER.deposit(amount, true);

        // assert the tokens have been transferred to the LOCKER
        assertEq(YND.balanceOf(address(caller)), 0);
        assertEq(YND.balanceOf(address(LOCKER)), amount);

        // 1. assert the sdTokens have been minted and transferred to the gauge
        assertEq(SDYND.balanceOf(address(caller)), 0);
        assertEq(SDYND.balanceOf(address(LOCKER)), 0);
        assertEq(SDYND.balanceOf(address(GAUGE)), amount);

        // assert the gauge tracks the caller's balance
        assertEq(GAUGE.balanceOf(address(caller)), amount);
        assertEq(GAUGE.balanceOf(address(LOCKER)), 0);
    }

    function test_DepositGivenTheStakeIsFalse() external {
        // it mints sdTokens to the caller

        address caller = makeAddr("caller");
        uint256 amount = 1e25;

        // mint the token to the caller and approve the LOCKER to spend the token
        deal(address(YND), caller, amount);
        vm.prank(caller);
        YND.approve(address(LOCKER), amount);

        // 3. expect the internal calls to be made
        vm.expectCall(address(SDYND), abi.encodeWithSelector(ISdToken.mint.selector, address(caller), amount), 1);

        // deposit the tokens
        vm.prank(caller);
        LOCKER.deposit(amount, false);

        // assert the tokens have been transferred to the LOCKER
        assertEq(YND.balanceOf(address(caller)), 0);
        assertEq(YND.balanceOf(address(LOCKER)), amount);

        // 1. assert the sdTokens have been minted to the caller
        assertEq(SDYND.balanceOf(address(caller)), amount);
        assertEq(SDYND.balanceOf(address(LOCKER)), 0);
        assertEq(SDYND.balanceOf(address(GAUGE)), 0);

        // assert the gauge balances have not changed
        assertEq(GAUGE.balanceOf(address(caller)), 0);
        assertEq(GAUGE.balanceOf(address(LOCKER)), 0);
    }

    function test_DepositGivenAReceiverWhenTheStakeIsTrue() external {
        // 1. it stakes the sdTokens in the gauge for the receiver
        // 2. it emits the TokensStaked event

        address caller = makeAddr("caller");
        address receiver = makeAddr("receiver");
        uint256 amount = 1e25;

        // mint the token to the caller and approve the LOCKER to spend the token
        deal(address(YND), caller, amount);
        vm.prank(caller);
        YND.approve(address(LOCKER), amount);

        // 3. expect the event to be emitted
        vm.expectEmit();
        emit TokensStaked(caller, receiver, address(GAUGE), amount);

        // expect the internal calls to be made
        vm.expectCall(address(SDYND), abi.encodeWithSelector(ISdToken.mint.selector, address(LOCKER), amount), 1);
        vm.expectCall(address(SDYND), abi.encodeWithSelector(IERC20.approve.selector, address(GAUGE), amount), 1);
        vm.expectCall(
            address(GAUGE), abi.encodeWithSelector(ILiquidityGaugeV4.deposit.selector, amount, receiver, false), 1
        );

        // deposit the tokens
        vm.prank(caller);
        LOCKER.deposit(amount, true, receiver);

        // assert the tokens have been transferred to the LOCKER
        assertEq(YND.balanceOf(address(caller)), 0);
        assertEq(YND.balanceOf(address(LOCKER)), amount);

        // 1. assert the sdTokens have been minted and transferred to the gauge
        assertEq(SDYND.balanceOf(address(caller)), 0);
        assertEq(SDYND.balanceOf(address(LOCKER)), 0);
        assertEq(SDYND.balanceOf(address(GAUGE)), amount);

        // assert the gauge tracks the receiver's balance
        assertEq(GAUGE.balanceOf(address(receiver)), amount);
        assertEq(GAUGE.balanceOf(address(caller)), 0);
        assertEq(GAUGE.balanceOf(address(LOCKER)), 0);
    }

    function test_DepositGivenAReceiverWhenTheStakeIsFalse() external {
        // it mints sdTokens to the receiver

        address caller = makeAddr("caller");
        address receiver = makeAddr("receiver");
        uint256 amount = 1e25;

        // mint the token to the caller and approve the LOCKER to spend the token
        deal(address(YND), caller, amount);
        vm.prank(caller);
        YND.approve(address(LOCKER), amount);

        // 3. expect the internal calls to be made
        vm.expectCall(address(SDYND), abi.encodeWithSelector(ISdToken.mint.selector, address(receiver), amount), 1);

        // deposit the tokens
        vm.prank(caller);
        LOCKER.deposit(amount, false, receiver);

        // assert the tokens have been transferred to the LOCKER
        assertEq(YND.balanceOf(address(caller)), 0);
        assertEq(YND.balanceOf(address(LOCKER)), amount);

        // 1. assert the sdTokens have been minted to the receiver
        assertEq(SDYND.balanceOf(address(caller)), 0);
        assertEq(SDYND.balanceOf(address(LOCKER)), 0);
        assertEq(SDYND.balanceOf(address(receiver)), amount);

        // assert the gauge balances have not changed
        assertEq(GAUGE.balanceOf(address(caller)), 0);
        assertEq(GAUGE.balanceOf(address(LOCKER)), 0);
        assertEq(GAUGE.balanceOf(address(receiver)), 0);
    }

    ////////////////////////////////////////////////////////////////
    /// --- Force Cancel Locker
    ///////////////////////////////////////////////////////////////

    function test_ForceCancelLockerSetsTheStateToCANCELED() external {
        // it sets the state to CANCELED

        // fast forward the timestamp by the delay and expect the state to be CANCELED
        vm.warp(block.timestamp + LOCKER.FORCE_CANCEL_DELAY());
        LOCKER.forceCancelLocker();
        assertEq(uint256(LOCKER.state()), uint256(PreLaunchLocker.STATE.CANCELED));
    }

    ////////////////////////////////////////////////////////////////
    /// --- Transfer Governance
    ///////////////////////////////////////////////////////////////

    function test_SetsTheNewGovernance() external {
        // it sets the new governance

        address newGovernance = makeAddr("newGovernance");

        vm.prank(LOCKER.governance());
        LOCKER.transferGovernance(newGovernance);

        assertEq(LOCKER.governance(), newGovernance);
    }

    ////////////////////////////////////////////////////////////////
    /// --- Lock
    ///////////////////////////////////////////////////////////////

    modifier setupDepositor() {
        // deploy the locker that will be used once all the protocol is deployed (after the pre-launch period)
        postPreLaunchLocker = address(new LockerMock());

        // deploy the depositor
        depositor = address(
            new PreLaunchBaseDepositor(
                address(YND), postPreLaunchLocker, address(SDYND), address(GAUGE), 1_000, address(LOCKER)
            )
        );

        _;
    }

    function test_SetsTheDepositorToTheGivenValue() external setupDepositor {
        // it sets the depositor to the given value

        uint256 balance = 1e25;
        deal(address(YND), address(LOCKER), balance);

        // expect the depositor to call the definitive locker
        vm.expectCall(postPreLaunchLocker, abi.encodeWithSelector(LockerMock.createLock.selector), 1);

        vm.prank(LOCKER.governance());
        LOCKER.lock(depositor);

        assertEq(address(LOCKER.depositor()), depositor);
    }

    function test_TransfersTheBalanceOfTokenToTheFinalLocker() external setupDepositor {
        // it transfers the balance of token to the final locker

        uint256 balance = 1e25;
        deal(address(YND), address(LOCKER), balance);

        assertEq(YND.balanceOf(address(LOCKER)), balance);

        vm.prank(LOCKER.governance());
        LOCKER.lock(depositor);

        assertEq(YND.balanceOf(address(LOCKER)), 0);
        assertEq(YND.balanceOf(address(postPreLaunchLocker)), balance);
    }

    function test_TransfersTheOperatorPermissionOfTheSdTokenToTheDepositor() external setupDepositor {
        // it transfers the operator permission of the sdToken to the depositor

        deal(address(SDYND), address(LOCKER), 10);

        assertEq(SDYND.operator(), address(LOCKER));

        // airdrop some YND to the LOCKER in order to be able to lock it
        deal(address(YND), address(LOCKER), 10);

        vm.prank(LOCKER.governance());
        LOCKER.lock(depositor);

        assertEq(SDYND.operator(), address(depositor));
    }

    function test_SetsTheStateToACTIVE() external setupDepositor {
        // it sets the state to ACTIVE
        deal(address(YND), address(LOCKER), 10);

        assertEq(uint256(LOCKER.state()), uint256(PreLaunchLocker.STATE.IDLE));

        vm.prank(LOCKER.governance());
        LOCKER.lock(depositor);

        assertEq(uint256(LOCKER.state()), uint256(PreLaunchLocker.STATE.ACTIVE));
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
        vm.prank(LOCKER.governance());
        LOCKER.cancelLocker();

        // set the expected amount of gauge tokens the caller is expected to have
        deal(address(SDYND), address(caller), amount);
        vm.prank(caller);
        SDYND.approve(address(GAUGE), amount);
        vm.prank(caller);
        GAUGE.deposit(amount, caller, false);

        // set the total balance to the locker
        deal(address(YND), address(LOCKER), balance);

        // approve the locker to spend the gauge tokens
        vm.prank(caller);
        GAUGE.approve(address(LOCKER), amount);

        // withdraw the amount
        vm.prank(caller);
        LOCKER.withdraw(amount, true);

        // verify the balances are correct after the withdrawal
        assertEq(SDYND.balanceOf(caller), 0);
        assertEq(SDYND.balanceOf(address(LOCKER)), 0);

        assertEq(YND.balanceOf(caller), amount);
        assertEq(YND.balanceOf(address(LOCKER)), balance - amount);

        assertEq(GAUGE.balanceOf(caller), 0);
        assertEq(GAUGE.balanceOf(address(LOCKER)), 0);
    }

    function test_WithdrawGivenTheStakeIsFalse() external {
        // it burn the sdToken held by the caller
        // it transfers back the default token to the caller

        address caller = makeAddr("caller");
        uint256 balance = 1e25;
        uint256 amount = 1e22;

        // mint the total balance to the locker
        deal(address(YND), address(LOCKER), balance);

        // mint the amount the caller is expected to have
        deal(address(SDYND), caller, amount);

        // approve the locker to spend the sdToken held by the caller
        vm.prank(caller);
        SDYND.approve(address(LOCKER), amount);

        // verify the initial balances are correct
        assertEq(SDYND.balanceOf(caller), amount);
        assertEq(YND.balanceOf(caller), 0);
        assertEq(YND.balanceOf(address(LOCKER)), balance);

        // manually set the state to CANCELED
        vm.prank(LOCKER.governance());
        LOCKER.cancelLocker();

        // withdraw the amount
        vm.prank(caller);
        LOCKER.withdraw(amount, false);

        // verify the balances are correct after the withdrawal
        assertEq(SDYND.balanceOf(caller), 0);
        assertEq(YND.balanceOf(caller), amount);
        assertEq(YND.balanceOf(address(LOCKER)), balance - amount);
        assertEq(SDYND.balanceOf(address(LOCKER)), 0);
    }

    /// @notice Event emitted each time a user stakes their sdTokens.
    /// @param caller The address who called the function.
    /// @param receiver The address who received the gauge YND.
    /// @param gauge The gauge that the sdTokens were staked to.
    /// @param amount The amount of sdTokens staked.
    event TokensStaked(address indexed caller, address indexed receiver, address indexed gauge, uint256 amount);
}

contract LockerMock {
    function createLock(uint256 amount, uint256 unlockTime) external {}
}

/// @notice Test that ensures the new verified gauge is valid
contract PreLaunchLockerTestVerifiedGauge is PreLaunchLockerTest {
    address internal constant VERIFIED_GAUGE = 0x82ABa41FcE8EdE355380F5F22D5472118Aff0410;

    function setUp() public override {
        // change the gauge implementation address in the gauge proxy
        vm.store(
            address(GAUGE),
            bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1),
            bytes32(uint256(uint160(VERIFIED_GAUGE)))
        );

        super.setUp();
    }
}
