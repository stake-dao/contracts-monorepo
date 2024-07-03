// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

///import {ICakeV3} from "src/base/interfaces/ICakeV3.sol";
//import {Executor} from "src/base/utils/Executor.sol";
import "src/cake/ifo/CakeIFOFactory.sol";

import {CAKE} from "address-book/src/lockers/56.sol";
import {DAO} from "address-book/src/dao/56.sol";
//import {ERC20} from "solady/src/tokens/ERC20.sol";

contract CakeIFOTest is Test {
    CakeIFOFactory private factory;
    CakeIFO private ifo;

    ICakeIFOV8 private constant CAKE_IFO = ICakeIFOV8(0x155c22E60B3934A58123Cf8a8Ff2DfEA4FcBA2b5);
    address private constant FEE_RECEIVER = address(0xFEEE);
    address private constant GOVERNANCE = DAO.GOVERNANCE;
    address private constant EXECUTOR = CAKE.EXECUTOR;
    address private constant LOCKER = CAKE.LOCKER;

    function setUp() external {
        uint256 forkId = vm.createFork(vm.rpcUrl("bnb"), 38_538_797); // ifo needs to start yet
        vm.selectFork(forkId);

        factory = new CakeIFOFactory(LOCKER, EXECUTOR, GOVERNANCE, FEE_RECEIVER);
    }

    function test_factory_creation() external view {
        assertEq(factory.locker(), address(LOCKER));
        assertEq(address(factory.executor()), EXECUTOR);
        assertEq(factory.governance(), GOVERNANCE);
        assertEq(factory.feeReceiver(), FEE_RECEIVER);
    }

    function test_create_ifo_before_start() external {
        vm.prank(GOVERNANCE);
        factory.createIFO(address(CAKE_IFO));
        ifo = CakeIFO(factory.ifos(address(CAKE_IFO)));

        assertEq(address(ifo.cakeIFO()), address(CAKE_IFO));
        assertEq(address(ifo.executor()), EXECUTOR);
        assertEq(address(ifo.dToken()), CAKE_IFO.addresses(0));
        assertEq(address(ifo.oToken()), CAKE_IFO.addresses(1));
        assertEq(ifo.locker(), LOCKER);

        // check periods
        uint256 firstPeriodStart = ifo.firstPeriodStart();
        uint256 firstPeriodEnd = ifo.firstPeriodEnd();
        assertEq(firstPeriodEnd - ifo.firstPeriodStart(), CAKE_IFO.endTimestamp() - firstPeriodEnd);
        assertEq(CAKE_IFO.startTimestamp(), firstPeriodStart);

        // deposit reverts for both period at that time
        bytes32[] memory merkleProof;
        vm.expectRevert(CakeIFO.NotInFirstPeriod.selector);
        ifo.depositPoolFirstPeriod(100e18, 0, 0, 100e18, merkleProof);

        vm.expectRevert(CakeIFO.NotInSecondPeriod.selector);
        ifo.depositPoolSecondPeriod(100e18, 0);
    }

    function test_create_ifo_after_start() external {
        skip(CAKE_IFO.startTimestamp() - block.timestamp + 10 seconds);

        vm.prank(GOVERNANCE);
        factory.createIFO(address(CAKE_IFO));
        ifo = CakeIFO(factory.ifos(address(CAKE_IFO)));

        uint256 firstPeriodStart = ifo.firstPeriodStart();
        uint256 firstPeriodEnd = ifo.firstPeriodEnd();
        assertEq(firstPeriodEnd - ifo.firstPeriodStart(), CAKE_IFO.endTimestamp() - firstPeriodEnd);
        assertLt(CAKE_IFO.startTimestamp(), firstPeriodStart);

        vm.expectRevert(CakeIFO.NotInSecondPeriod.selector);
        ifo.depositPoolSecondPeriod(100e18, 0);
    }

    function test_create_ifo_after_end() external {
        skip(CAKE_IFO.endTimestamp() - block.timestamp + 10 seconds);

        vm.prank(GOVERNANCE);
        vm.expectRevert(CakeIFO.IfoEnded.selector);
        factory.createIFO(address(CAKE_IFO));
    }

    function test_create_same_ifo() external {
        vm.prank(GOVERNANCE);
        factory.createIFO(address(CAKE_IFO));

        vm.expectRevert(CakeIFOFactory.IfoAlreadyCreated.selector);
        vm.prank(GOVERNANCE);
        factory.createIFO(address(CAKE_IFO));
    }
}
