// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

import {ILocker} from "src/common/interfaces/ILocker.sol";
import {Executor} from "src/bnb/cake/utils/Executor.sol";
import {CAKE} from "address-book/src/lockers/56.sol";
import {DAO} from "address-book/src/dao/56.sol";

contract AllowedExecutor {}

contract ExecutorTest is Test {
    Executor internal executor;

    address internal constant MS = DAO.GOVERNANCE;
    ILocker internal constant LOCKER = ILocker(CAKE.LOCKER);

    address internal eoa = address(0xEAA);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("bnb"), 35492855);
        // Deploy Executor
        executor = new Executor(MS);
    }

    function test_initial_data() external view {
        assertEq(executor.governance(), MS);
        assertEq(executor.futureGovernance(), address(0));
    }

    function test_allow_contract_gov() external {
        _allowContract(address(this));
    }

    function test_allow_contract_no_gov() external {
        vm.expectRevert(Executor.Governance.selector);
        executor.allowAddress(address(this));
    }

    function test_allow_eoa_gov() external {
        vm.expectRevert(Executor.NotContract.selector);
        vm.prank(MS);
        executor.allowAddress(eoa);
    }

    function test_disallow_contract_gov() external {
        _allowContract(address(this));
        vm.prank(MS);
        executor.disallowAddress(address(this));
        assertFalse(executor.allowed(address(this)));
    }

    function test_disallow_contract_no_gov() external {
        vm.expectRevert(Executor.Governance.selector);
        executor.disallowAddress(address(this));
    }

    function test_transfer_governance_gov() external {
        assertEq(executor.governance(), MS);
        vm.startPrank(MS);

        executor.transferGovernance(address(this));
        assertEq(executor.governance(), MS);
        assertEq(executor.futureGovernance(), address(this));

        executor.transferGovernance(eoa);
        assertEq(executor.governance(), MS);
        assertEq(executor.futureGovernance(), eoa);

        executor.transferGovernance(address(0));
        assertEq(executor.governance(), MS);
        assertEq(executor.futureGovernance(), address(0));
        vm.stopPrank();
    }

    function test_transfer_governance_no_gov() external {
        vm.expectRevert(Executor.Governance.selector);
        executor.transferGovernance(address(this));
    }

    function test_accept_governance_future_gov() external {
        vm.prank(MS);
        executor.transferGovernance(eoa);
        assertEq(executor.futureGovernance(), eoa);

        vm.prank(eoa);
        executor.acceptGovernance();
        assertEq(executor.governance(), eoa);
        assertEq(executor.futureGovernance(), address(0));

        vm.prank(eoa);
        executor.transferGovernance(MS);

        vm.prank(MS);
        executor.acceptGovernance();
    }

    function test_accept_governance_no_future_gov() external {
        vm.prank(MS);
        executor.transferGovernance(eoa);
        vm.expectRevert(Executor.Governance.selector);
        executor.acceptGovernance();
    }

    function test_execute_gov() external {
        bytes memory governanceData = abi.encodeWithSignature("governance()");
        vm.prank(MS);
        (bool success, bytes memory data) = executor.execute(address(LOCKER), 0, governanceData);
        assertTrue(success);
        assertEq(abi.decode(data, (address)), MS);
    }

    function test_execute_no_gov() external {
        bytes memory governanceData = abi.encodeWithSignature("governance()");
        vm.expectRevert(Executor.Unauthorized.selector);
        executor.execute(address(LOCKER), 0, governanceData);
    }

    function test_call_execute_with_allowed() external {
        vm.startPrank(MS);
        // set the locker goverance
        LOCKER.transferGovernance(address(executor));
        // accept the governance
        executor.execute(address(LOCKER), 0, abi.encodeWithSignature("acceptGovernance()"));

        vm.stopPrank();

        bytes memory governanceData = abi.encodeWithSignature("governance()");

        vm.expectRevert(Executor.Unauthorized.selector);
        (bool success, bytes memory data) = executor.execute(address(LOCKER), 0, governanceData);

        vm.expectRevert(Executor.Unauthorized.selector);
        (success, data) = executor.callExecuteTo(address(LOCKER), address(executor), 0, governanceData);

        AllowedExecutor _allowed = new AllowedExecutor();
        _allowContract(address(_allowed));

        vm.startPrank(address(_allowed));

        (success, data) = executor.execute(address(LOCKER), 0, governanceData);
        (success, data) = executor.callExecuteTo(address(LOCKER), address(executor), 0, governanceData);

        vm.stopPrank();

        assertTrue(success);
    }

    function test_call_execute_to_gov() external {
        vm.startPrank(MS);
        // set the locker goverance
        LOCKER.transferGovernance(address(executor));
        // accept the governance
        executor.execute(address(LOCKER), 0, abi.encodeWithSignature("acceptGovernance()"));

        assertEq(LOCKER.governance(), address(executor));

        executor.execute(address(LOCKER), 0, abi.encodeWithSignature("transferGovernance(address)", MS));

        assertEq(LOCKER.futureGovernance(), address(MS));
        LOCKER.acceptGovernance();

        assertEq(LOCKER.governance(), address(MS));
        vm.stopPrank();
    }

    function _allowContract(address _toAllow) internal {
        assertFalse(executor.allowed(_toAllow));
        vm.prank(MS);
        executor.allowAddress(_toAllow);
        assertTrue(executor.allowed(_toAllow));
    }
}
