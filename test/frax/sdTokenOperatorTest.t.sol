// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {FXS} from "address-book/lockers/1.sol";
import {DAO} from "address-book/dao/1.sol";
import {Frax} from "address-book/protocols/1.sol";
import {sdTokenOperator} from "src/frax/fxs/token/sdTokenOperator.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IDepositor} from "src/base/interfaces/IDepositor.sol";
import {ISdToken} from "src/base/interfaces/IsdToken.sol";

contract sdTokenOperatorTest is Test {
    sdTokenOperator public mainOperator;

    address public operator1 = address(0xBBBB);
    address public operator2 = address(0xABCD);
    address public user = address(0xABBB);

    ISdToken public sdFXS = ISdToken(FXS.SDTOKEN);
    address public governance = DAO.GOVERNANCE;
    address public fxs = Frax.FXS;

    address public fxsHolder = 0x18398afe661a9a66D6bD0D26453226856E0276C1;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        // deploy main operator
        mainOperator = new sdTokenOperator(address(sdFXS), governance);

        // set the new operator via depositor
        vm.prank(governance);
        IDepositor(FXS.DEPOSITOR).setSdTokenOperator(address(mainOperator));
        assertEq(sdFXS.operator(), address(mainOperator));

        // allow all operators in the main one
        vm.startPrank(governance);
        mainOperator.allowOperator(operator1);
        mainOperator.allowOperator(operator2);
        vm.stopPrank();

        deal(fxs, user, 100e18);
    }

    function test_deploy() external {
        assertEq(mainOperator.governance(), governance);
        assertEq(mainOperator.futureGovernance(), address(0));
        assertEq(address(mainOperator.sdToken()), address(sdFXS));
    }

    function test_mint() external {
        uint256 amount = 100e18;

        uint256 totalSupplyBefore = ERC20(address(sdFXS)).totalSupply();
        vm.prank(operator2);
        mainOperator.mint(address(this), amount);
        assertEq(ERC20(address(sdFXS)).totalSupply() - totalSupplyBefore, amount);
        assertEq(ERC20(address(sdFXS)).balanceOf(address(this)), amount);
    }

    function test_burn() external {
        uint256 amount = 100e18;

        uint256 totalSupply = ERC20(address(sdFXS)).totalSupply();

        vm.startPrank(operator2);
        mainOperator.mint(address(this), amount);

        skip(1 seconds);

        mainOperator.burn(address(this), amount);
        vm.stopPrank();

        assertEq(ERC20(address(sdFXS)).totalSupply(), totalSupply);
        assertEq(ERC20(address(sdFXS)).balanceOf(address(this)), 0);
    }

    // function test_deposit() external {
    //     uint256 amountToDeposit = 10e18;

    //     assertGt(ERC20(fxs).balanceOf(address(this)), 10e18);
    //     vm.startPrank(fxsHolder);
    //     ERC20(fxs).approve(operator1, amountToDeposit);
    //     IDepositor(operator1).deposit(amountToDeposit, true, true, address(this));
    //     vm.stopPrank();
    // }

    function test_set_sdToken_operator() external {
        address newMainOperator = address(0xABCD);
        vm.prank(governance);
        mainOperator.setSdTokenOperator(newMainOperator);

        assertEq(sdFXS.operator(), newMainOperator);
        vm.prank(newMainOperator);
        sdFXS.mint(address(this), 100e18);
    }

    function test_transfer_governance() external {
        address newGovernance = address(0xABCD);

        vm.prank(governance);
        mainOperator.transferGovernance(newGovernance);

        assertEq(mainOperator.governance(), governance);
        assertEq(mainOperator.futureGovernance(), newGovernance);

        vm.prank(newGovernance);
        mainOperator.acceptGovernance();

        assertEq(mainOperator.governance(), newGovernance);
        assertEq(mainOperator.futureGovernance(), address(0));
    }
}
