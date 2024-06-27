// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {FXS} from "address-book/lockers/1.sol";
import {Frax} from "address-book/protocols/252.sol";
import {sdTokenOperatorFraxtal} from "src/frax/fxs/token/sdTokenOperatorFraxtal.sol";
import {sdFXSFraxtal} from "src/frax/fxs/token/sdFXSFraxtal.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

contract sdTokenOperatorFraxtalTest is Test {
    address internal constant OPERATOR_1 = address(0xBBBB);
    address internal constant OPERATOR_2 = address(0xABCD);
    address internal constant GOVERNANCE = address(0xABBB);
    address internal constant FRAXTAL_BRIDGE = 0x4200000000000000000000000000000000000010;
    address internal constant INITIAL_DELEGATE = address(0xDEAA);

    sdTokenOperatorFraxtal internal mainOperator;
    sdFXSFraxtal internal sdFXS;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("fraxtal"));
        vm.selectFork(forkId);

        sdFXS = new sdFXSFraxtal("Stake DAO FXS", "sdFXS", Frax.DELEGATION_REGISTRY, INITIAL_DELEGATE);

        // deploy main operator
        mainOperator = new sdTokenOperatorFraxtal(
            address(sdFXS), GOVERNANCE, FXS.SDTOKEN, FRAXTAL_BRIDGE, Frax.DELEGATION_REGISTRY, INITIAL_DELEGATE
        );

        sdFXS.setOperator(address(mainOperator));

        // allow all operators in the main one
        vm.startPrank(GOVERNANCE);
        mainOperator.allowOperator(OPERATOR_1);
        mainOperator.allowOperator(OPERATOR_2);
        vm.stopPrank();
    }

    function test_deploy() external {
        assertEq(mainOperator.governance(), GOVERNANCE);
        assertEq(mainOperator.futureGovernance(), address(0));
        assertEq(address(mainOperator.sdToken()), address(sdFXS));
        assertTrue(mainOperator.operators(OPERATOR_1));
        assertTrue(mainOperator.operators(OPERATOR_2));
    }

    function test_mint() external {
        uint256 amount = 100e18;

        uint256 totalSupplyBefore = ERC20(address(sdFXS)).totalSupply();

        vm.prank(OPERATOR_1);
        mainOperator.mint(address(this), amount);

        assertEq(ERC20(address(sdFXS)).totalSupply() - totalSupplyBefore, amount);
        assertEq(ERC20(address(sdFXS)).balanceOf(address(this)), amount);

        vm.prank(OPERATOR_2);
        mainOperator.mint(address(this), amount);

        assertEq(ERC20(address(sdFXS)).totalSupply() - totalSupplyBefore, amount * 2);
        assertEq(ERC20(address(sdFXS)).balanceOf(address(this)), amount * 2);
    }

    function test_burn() external {
        uint256 amount = 100e18;

        uint256 totalSupply = ERC20(address(sdFXS)).totalSupply();

        vm.prank(OPERATOR_1);
        mainOperator.mint(address(this), amount);

        vm.startPrank(OPERATOR_2);
        mainOperator.mint(address(this), amount);

        skip(1 seconds);

        mainOperator.burn(address(this), amount);

        assertEq(ERC20(address(sdFXS)).totalSupply(), totalSupply + amount);
        assertEq(ERC20(address(sdFXS)).balanceOf(address(this)), amount);

        mainOperator.burn(address(this), amount);

        assertEq(ERC20(address(sdFXS)).totalSupply(), totalSupply);
        assertEq(ERC20(address(sdFXS)).balanceOf(address(this)), 0);

        vm.stopPrank();
    }

    function test_set_sdToken_operator() external {
        address newMainOperator = address(0xABCD);
        vm.prank(GOVERNANCE);
        mainOperator.setSdTokenOperator(newMainOperator);

        assertEq(sdFXS.operator(), newMainOperator);
        vm.prank(newMainOperator);
        sdFXS.mint(address(this), 100e18);
    }

    function test_transfer_governance() external {
        address newGovernance = address(0xABCD);

        vm.prank(GOVERNANCE);
        mainOperator.transferGovernance(newGovernance);

        assertEq(mainOperator.governance(), GOVERNANCE);
        assertEq(mainOperator.futureGovernance(), newGovernance);

        vm.prank(newGovernance);
        mainOperator.acceptGovernance();

        assertEq(mainOperator.governance(), newGovernance);
        assertEq(mainOperator.futureGovernance(), address(0));
    }
}
