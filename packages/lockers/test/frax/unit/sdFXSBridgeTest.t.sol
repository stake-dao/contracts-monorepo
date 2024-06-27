// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {FXS} from "address-book/lockers/1.sol";
import {Frax} from "address-book/protocols/252.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {IFraxtalBridge} from "src/base/interfaces/IFraxtalBridge.sol";
import {sdFXSFraxtal} from "src/frax/fxs/token/sdFXSFraxtal.sol";
import {sdTokenOperatorFraxtal} from "src/frax/fxs/token/sdTokenOperatorFraxtal.sol";

abstract contract sdFXSBridgeTest is Test {
    address internal USER = address(0xABCD);
    uint256 internal amountToBridge = 10e18;
    string network;

    constructor(string memory _network) {
        network = _network;
    }

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl(network));
        vm.selectFork(forkId);
    }
}

contract sdFXSEthToFraxtalTest is sdFXSBridgeTest("mainnet") {
    IFraxtalBridge internal constant FRAXTAL_BRIDGE = IFraxtalBridge(0x34C0bD5877A5Ee7099D0f5688D65F4bB9158BDE2);
    ERC20 internal sdFxs = ERC20(FXS.SDTOKEN);

    function setUp() public override {
        super.setUp();

        deal(address(sdFxs), USER, amountToBridge);
    }

    function test_bridge_to_fraxtal() public {
        address remoteToken = address(0xABAB);

        assertEq(sdFxs.balanceOf(USER), amountToBridge);
        assertEq(sdFxs.balanceOf(address(FRAXTAL_BRIDGE)), 0);

        vm.startPrank(USER);
        ERC20(FXS.SDTOKEN).approve(address(FRAXTAL_BRIDGE), amountToBridge);
        FRAXTAL_BRIDGE.bridgeERC20(FXS.SDTOKEN, remoteToken, amountToBridge, 0, "");
        vm.stopPrank();

        assertEq(sdFxs.balanceOf(USER), 0);
        assertEq(sdFxs.balanceOf(address(FRAXTAL_BRIDGE)), amountToBridge);
    }
}

contract sdFXSFraxtalToEthTest is sdFXSBridgeTest("fraxtal") {
    sdFXSFraxtal internal sdFxsFraxtal;
    sdTokenOperatorFraxtal internal mainOperator;

    address internal constant INITIAL_DELEGATE = address(0xBABA);
    address internal constant DELEGATION_REGISTRY = Frax.DELEGATION_REGISTRY;
    IFraxtalBridge internal constant FRAXTAL_BRIDGE = IFraxtalBridge(0x4200000000000000000000000000000000000010);
    address internal constant GOVERNANCE = address(0xABBB);

    function setUp() public override {
        super.setUp();

        sdFxsFraxtal = new sdFXSFraxtal("Stake DAO FXS", "sdFXS", DELEGATION_REGISTRY, INITIAL_DELEGATE);
        mainOperator = new sdTokenOperatorFraxtal(
            address(sdFxsFraxtal),
            GOVERNANCE,
            FXS.SDTOKEN,
            address(FRAXTAL_BRIDGE),
            DELEGATION_REGISTRY,
            INITIAL_DELEGATE
        );

        // set the main operator as operator
        sdFxsFraxtal.setOperator(address(mainOperator));

        // allow the bridge to mint throught the main operator
        vm.prank(GOVERNANCE);
        mainOperator.allowOperator(address(FRAXTAL_BRIDGE));

        deal(address(sdFxsFraxtal), USER, amountToBridge);
    }

    function test_bridge_to_eth() public {
        assertEq(ERC20(address(sdFxsFraxtal)).balanceOf(USER), amountToBridge);
        assertEq(ERC20(address(sdFxsFraxtal)).balanceOf(address(FRAXTAL_BRIDGE)), 0);

        vm.prank(USER);
        FRAXTAL_BRIDGE.bridgeERC20(address(mainOperator), FXS.SDTOKEN, amountToBridge, 0, "");

        assertEq(ERC20(address(sdFxsFraxtal)).balanceOf(USER), 0);
    }
}
