// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "forge-std/src/Test.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {IDepositor} from "src/common/interfaces/IDepositor.sol";
import {IveToken} from "src/common/interfaces/IveToken.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {IGaugeController} from "src/common/interfaces/IGaugeController.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {IAccumulator} from "src/common/interfaces/IAccumulator.sol";
import {ISmartWalletChecker} from "src/common/interfaces/ISmartWalletChecker.sol";

import {DAO} from "address-book/src/dao/1.sol";

contract BaseTest is Test {
    ////////////////////////////////////////////////////////////////
    /// --- MAIN CALL
    ///////////////////////////////////////////////////////////////
    function mainCall(address caller, address toCall, bytes memory callData) internal returns (bool success) {
        vm.startPrank(caller);
        (success,) = toCall.call(callData);
        require(success, "low-level call failed");
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////////////////
    /// --- LOCKER
    ///////////////////////////////////////////////////////////////
    function createLock(
        address caller,
        address locker,
        address veToken,
        uint256 initialAmountToLock,
        uint256 initialPeriodToLock,
        uint256 lockMultiplier,
        bytes memory callData
    ) internal {
        IveToken.LockedBalance memory lockedBalanceBefore = IveToken(veToken).locked(locker);
        uint256 veBalanceBefore = IveToken(veToken).balanceOf(locker);

        mainCall(caller, locker, callData);

        IveToken.LockedBalance memory lockedBalance = IveToken(veToken).locked(locker);

        assertEq(lockedBalance.amount, lockedBalanceBefore.amount + int256(initialAmountToLock), "locked amount");
        assertEq(
            lockedBalance.end,
            lockedBalanceBefore.end + ((block.timestamp + initialPeriodToLock) / 1 weeks) * 1 weeks,
            "locked end time"
        );
        assertApproxEqRel(
            IveToken(veToken).balanceOf(locker),
            veBalanceBefore + (initialAmountToLock * lockMultiplier),
            2e16,
            "veBalance"
        ); // 2% Margin of Error
    }

    function increaseAmount(
        address caller,
        address locker,
        address veToken,
        uint256 extraAmountToLock,
        bytes memory callData
    ) internal {
        IveToken.LockedBalance memory lockedBalanceBefore = IveToken(veToken).locked(locker);
        mainCall(caller, locker, callData);

        IveToken.LockedBalance memory lockedBalance = IveToken(veToken).locked(locker);

        assertEq(lockedBalance.amount, lockedBalanceBefore.amount + int256(extraAmountToLock), "locked amount");
    }

    function increaseLock(address caller, address locker, address veToken, uint256 endPeriodLock, bytes memory callData)
        internal
    {
        IveToken.LockedBalance memory lockedBalanceBefore = IveToken(veToken).locked(address(locker));
        mainCall(caller, locker, callData);

        IveToken.LockedBalance memory lockedBalance = IveToken(veToken).locked(address(locker));
        assertApproxEqAbs(
            lockedBalance.end, lockedBalanceBefore.end + (endPeriodLock / 1 weeks) * 1 weeks, 1 weeks, "locked end time"
        );
    }

    function release(
        address caller,
        address locker,
        address token,
        address receiver,
        uint256 initialAmountToWithdraw,
        bytes memory callData
    ) internal {
        uint256 balanceBefore = IERC20(token).balanceOf(receiver);
        mainCall(caller, locker, callData);
        assertEq(IERC20(token).balanceOf(address(locker)), 0, "locker balance !=0");
        assertEq(IERC20(token).balanceOf(receiver), balanceBefore + initialAmountToWithdraw, "amount");
    }

    function claimReward(
        address caller,
        address locker,
        address[] memory rewardsToken,
        address rewardsReceiver,
        bytes[] memory callData
    ) internal {
        uint256[] memory balancesBefore = new uint256[](rewardsToken.length);
        uint256[] memory balancesAfter = new uint256[](rewardsToken.length);

        // Check balances for rewards tokens before
        for (uint8 i = 0; i < rewardsToken.length; ++i) {
            balancesBefore[i] = IERC20(rewardsToken[i]).balanceOf(rewardsReceiver);
        }

        // Claim rewards
        vm.startPrank(caller);
        for (uint8 i = 0; i < callData.length; ++i) {
            (bool success,) = locker.call(callData[i]);
            require(success, "low-level call failed");
        }
        vm.stopPrank();

        // Check rewards obtained
        for (uint8 i = 0; i < rewardsToken.length; ++i) {
            balancesAfter[i] = IERC20(rewardsToken[i]).balanceOf(rewardsReceiver);

            assertEq(balancesBefore[i], 0, "balance before != 0");
            assertGt(balancesAfter[i], balancesBefore[i], "balance after =< before");
            if (balancesAfter[i] <= balancesBefore[i]) {
                console.log("Assert failed for token: ", rewardsToken[i]);
            }
        }
    }

    function voteForGauge(address caller, address locker, address gaugeController, address gauge, bytes memory callData)
        internal
    {
        uint256 voteBefore = IGaugeController(gaugeController).last_user_vote(address(locker), gauge);
        mainCall(caller, locker, callData);
        uint256 voteAfter = IGaugeController(gaugeController).last_user_vote(address(locker), gauge);

        assertEq(voteBefore, 0, "vote before != 0");
        assertGt(voteAfter, voteBefore, "vote after =< before");
    }

    function execute(address caller, address locker, bytes memory callData) internal {
        bool success = mainCall(caller, locker, callData);

        assertEq(success, true, "call fail");
    }

    ////////////////////////////////////////////////////////////////
    /// --- DEPOSITOR
    ///////////////////////////////////////////////////////////////
    function lockToken(
        address caller,
        address locker,
        address depositor,
        address token,
        address veToken,
        address sdToken,
        uint256 amountToLock,
        uint256 incentiveAmount,
        uint256 waitBeforeLock,
        bytes memory callData
    ) internal {
        IveToken.LockedBalance memory lockedBalanceBefore = IveToken(veToken).locked(locker);
        uint256 sdBalanceBefore = IERC20(sdToken).balanceOf(caller);
        timeJump(waitBeforeLock);

        // Force incentive token amount
        vm.store(depositor, bytes32(uint256(4)), bytes32(incentiveAmount));
        require(IDepositor(depositor).incentiveToken() == incentiveAmount, "Force to incentive failed");

        mainCall(caller, depositor, callData);

        assertEq(IERC20(token).balanceOf(locker), 0, "locker balance != 0");
        assertEq(IERC20(token).balanceOf(depositor), 0, "depositor balance != 0");
        assertEq(
            IveToken(veToken).locked(locker).amount, lockedBalanceBefore.amount + int256(amountToLock), "veBalance"
        );
        assertEq(IERC20(sdToken).balanceOf(caller), sdBalanceBefore + incentiveAmount, "incentive amount");
        if (amountToLock != 0) {
            assertApproxEqAbs(
                IveToken(veToken).locked(locker).end,
                (((lockedBalanceBefore.end + waitBeforeLock) / 1 weeks) * 1 weeks),
                1 weeks,
                "locked end"
            );
        }
    }

    function deposit(
        address caller,
        address depositor,
        address token,
        address sdToken,
        address user,
        uint256 amountToDeposit,
        uint256 incentiveAmount,
        uint256 waitBeforeLock,
        bool lock,
        bool stake,
        bytes memory callData
    ) internal {
        timeJump(waitBeforeLock);

        // Force incentive token amount
        vm.store(depositor, bytes32(uint256(4)), bytes32(incentiveAmount));
        require(IDepositor(depositor).incentiveToken() == incentiveAmount, "Force to incentive failed");

        uint256 incentiveTokenBefore = IDepositor(depositor).incentiveToken();
        uint256 balanceDepositorBefore = IERC20(token).balanceOf(depositor);
        uint256 balanceTokenUserBefore = IERC20(token).balanceOf(user);

        mainCall(caller, depositor, callData);

        assertEq(IERC20(token).balanceOf(user), balanceTokenUserBefore - amountToDeposit, "wrong user balance");
        if (lock) {
            amountToDeposit += incentiveAmount;
            assertEq(IDepositor(depositor).incentiveToken(), 0, "incentive amount");
        } else {
            //uint256 callIncentive = (amountToDeposit * IBaseDepositor(depositor).lockIncentive()) /
            //	IBaseDepositor(depositor).FEE_DENOMINATOR(); //not use because stack too deep.

            assertEq(IERC20(token).balanceOf(depositor), balanceDepositorBefore + amountToDeposit, "amount depositor");
            assertEq(
                IDepositor(depositor).incentiveToken(),
                incentiveTokenBefore
                    + (amountToDeposit * IDepositor(depositor).lockIncentive()) / IDepositor(depositor).FEE_DENOMINATOR(),
                "incentive token"
            );
            amountToDeposit -=
                (amountToDeposit * IDepositor(depositor).lockIncentive()) / IDepositor(depositor).FEE_DENOMINATOR();
        }
        if (stake && IDepositor(depositor).gauge() != address(0)) {
            assertEq(ILiquidityGauge(IDepositor(depositor).gauge()).balanceOf(user), amountToDeposit, "gauge balance");
        } else {
            assertEq(IERC20(sdToken).balanceOf(user), amountToDeposit, "sdToken balance");
        }
    }

    ////////////////////////////////////////////////////////////////
    /// --- BASE ACCUMULATOR
    ///////////////////////////////////////////////////////////////
    function notifyExtraReward(
        address caller,
        address accumulator,
        address rewardToken,
        address gauge,
        uint256 rewardAmount,
        bytes memory callData
    ) internal {
        mainCall(caller, accumulator, callData);

        if (rewardAmount > 0) {
            // Only work for Blackpool!
            uint256 fees = IAccumulator(accumulator).claimerFee();
            assertEq(
                IERC20(rewardToken).balanceOf(gauge),
                (rewardAmount * (10000 - fees)) / 10000,
                "reward token balance in gauge"
            );
            assertEq(
                IERC20(rewardToken).balanceOf(caller), (rewardAmount * fees) / 10000, "reward token balance caller"
            );
        }
        assertGt(IERC20(DAO.SDT).balanceOf(gauge), 0, "SDT balance in gauge");
    }

    function notifyExtraReward(
        address caller,
        address accumulator,
        address[] memory rewardToken,
        address gauge,
        uint256[] memory rewardAmount,
        bytes memory callData
    ) internal {
        mainCall(caller, accumulator, callData);

        uint256 fees = IAccumulator(accumulator).claimerFee();
        for (uint8 i; i < rewardToken.length; ++i) {
            assertEq(
                IERC20(rewardToken[i]).balanceOf(gauge),
                (rewardAmount[i] * (10000 - fees)) / 10000,
                "reward token balance in gauge"
            );
            assertEq(
                IERC20(rewardToken[i]).balanceOf(caller),
                (rewardAmount[i] * fees) / 10000,
                "reward token balance caller"
            );
        }
        assertGt(IERC20(DAO.SDT).balanceOf(gauge), 0, "SDT balance in gauge");
    }

    function depositToken(address caller, address accumulator, address token, uint256 amount, bytes memory callData)
        internal
    {
        vm.startPrank(caller);
        IERC20(token).approve(accumulator, amount);
        (bool success,) = accumulator.call(callData);
        require(success, "low-level call failed");
        vm.stopPrank();

        assertEq(IERC20(token).balanceOf(accumulator), amount, "token balance in accumulator");
    }

    function rescueToken(
        address caller,
        address accumulator,
        address token,
        address receipient,
        uint256 amount,
        bytes memory callData
    ) internal {
        mainCall(caller, accumulator, callData);

        assertEq(IERC20(token).balanceOf(receipient), amount, "token balance of receipient");
    }

    ////////////////////////////////////////////////////////////////
    /// --- ACCUMULATOR
    ///////////////////////////////////////////////////////////////
    function claimRewardAndNotify(
        address caller,
        address accumulator,
        address[] memory rewardsToken,
        address rewardsReceiver,
        address gauge,
        bytes[] memory callData
    ) internal {
        claimReward(caller, accumulator, rewardsToken, rewardsReceiver, callData);

        assertGt(IERC20(DAO.SDT).balanceOf(gauge), 0, "SDT balance in gauge");
    }

    ////////////////////////////////////////////////////////////////
    /// --- SDTOKEN
    ///////////////////////////////////////////////////////////////
    function mint(address caller, address sdToken, address to, uint256 mintAmount, bytes memory callData) internal {
        uint256 balanceBefore = IERC20(sdToken).balanceOf(to);
        uint256 supplyBefore = IERC20(sdToken).totalSupply();

        mainCall(caller, sdToken, callData);

        assertEq(IERC20(sdToken).balanceOf(to), balanceBefore + mintAmount, "sdToken balance");
        assertEq(IERC20(sdToken).totalSupply(), supplyBefore + mintAmount, "sdToken supply");
    }

    function burn(address caller, address sdToken, address from, uint256 burnAmount, bytes memory callData) internal {
        uint256 balanceBefore = IERC20(sdToken).balanceOf(from);
        uint256 supplyBefore = IERC20(sdToken).totalSupply();

        mainCall(caller, sdToken, callData);

        assertEq(IERC20(sdToken).balanceOf(from), balanceBefore - burnAmount, "sdToken balance");
        assertEq(IERC20(sdToken).totalSupply(), supplyBefore - burnAmount, "sdToken supply");
    }

    ////////////////////////////////////////////////////////////////
    /// --- SETTERS
    ///////////////////////////////////////////////////////////////
    // All addresses setters
    function setter(
        address caller,
        address targetCall,
        address targetCheck,
        address newValue,
        bytes memory callDataFun,
        bytes memory callDataVar
    ) internal {
        _setter(caller, targetCall, targetCheck, abi.encode(newValue), callDataFun, callDataVar);
    }

    // All bool setters
    function setter(
        address caller,
        address targetCall,
        address targetCheck,
        bool newValue,
        bytes memory callDataFun,
        bytes memory callDataVar
    ) internal {
        _setter(caller, targetCall, targetCheck, abi.encode(newValue), callDataFun, callDataVar);
    }

    // All uint setters
    function setter(
        address caller,
        address targetCall,
        address targetCheck,
        uint256 newValue,
        bytes memory callDataFun,
        bytes memory callDataVar
    ) internal {
        _setter(caller, targetCall, targetCheck, abi.encode(newValue), callDataFun, callDataVar);
    }

    function _setter(
        address caller,
        address targetCall,
        address targetCheck,
        bytes memory newValue,
        bytes memory callDataFun,
        bytes memory callDataVar
    ) internal {
        vm.startPrank(caller);
        (bool success, bytes memory data) = targetCall.call(callDataFun);
        require(success, "low-level call failed");
        vm.stopPrank();

        (success, data) = targetCheck.call(callDataVar);
        require(success, "low-level call failed");

        assertEq(keccak256(data), keccak256(newValue), "value");
    }

    function reverter(
        address[] memory caller,
        address toCall,
        bytes[] memory listCallData,
        bytes[] memory listRevertReason
    ) internal {
        for (uint8 i = 0; i < listCallData.length; ++i) {
            vm.expectRevert(listRevertReason[i]);
            mainCall(caller[i], toCall, listCallData[i]);
        }
    }

    ////////////////////////////////////////////////////////////////
    /// --- HELPERS
    ///////////////////////////////////////////////////////////////
    function timeJump(uint256 _period) public returns (uint256, uint256) {
        skip(_period);
        vm.roll(block.number + _period / 12);
        return (block.timestamp, block.number);
    }

    function lockSDT(address caller) public {
        vm.startPrank(caller);
        deal(DAO.SDT, caller, 1_000_000e18);
        IERC20(DAO.SDT).approve(DAO.VESDT, 1_000_000e18);
        bytes memory createLockCallData = abi.encodeWithSignature(
            "create_lock(uint256,uint256)", 1_000_000e18, block.timestamp + 60 * 60 * 24 * 364 * 4
        );
        (bool success,) = DAO.VESDT.call(createLockCallData);
        require(success, "lock SDT failed");
        vm.stopPrank();

        assertApproxEqRel(IERC20(DAO.VESDT).balanceOf(caller), 1_000_000e18, 1e16);
    }

    function lockSDTWhiteList(address caller) public {
        vm.prank(IveToken(DAO.VESDT).admin());
        ISmartWalletChecker(DAO.SMART_WALLET_CHECKER).approveWallet(caller);
        lockSDT(caller);
    }

    function lockSDTCustom(address caller, address sdt, address vesdt, uint256 amount, uint256 unlockTime) public {
        vm.startPrank(caller);
        deal(sdt, caller, amount);
        IERC20(sdt).approve(vesdt, amount);
        bytes memory createLockCallData = abi.encodeWithSignature("create_lock(uint256,uint256)", amount, unlockTime);
        (bool success,) = vesdt.call(createLockCallData);
        require(success, "lock SDT failed");
        vm.stopPrank();
        uint256 max = 4 * 365 days;

        assertApproxEqRel(IERC20(vesdt).balanceOf(caller), (amount * (unlockTime - block.timestamp)) / max, 2e16);
    }

    function simulateRewards(address[] memory rewardsToken, uint256[] memory rewardsAmount, address rewardReceiver)
        public
    {
        for (uint8 i = 0; i < rewardsToken.length; ++i) {
            uint256 balanceBefore = IERC20(rewardsToken[i]).balanceOf(address(this));
            deal(rewardsToken[i], address(this), rewardsAmount[i]);
            IERC20(rewardsToken[i]).transfer(rewardReceiver, rewardsAmount[i]);
            require((balanceBefore - IERC20(rewardsToken[i]).balanceOf(address(this))) == 0, "!not empty");
        }
    }

    function bytesToAddressCustom(bytes memory payload, uint256 start) public pure returns (address addr) {
        assembly {
            addr := mload(add(payload, start))
        }
    }

    function deployBytecode(bytes memory bytecode, bytes memory args) internal returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }

    function sliceUint(bytes memory bs, uint256 start) internal pure returns (uint256) {
        require(bs.length >= start + 32, "slicing out of range");
        uint256 x;
        assembly {
            x := mload(add(bs, add(0x20, start)))
        }
        return x;
    }
}
