// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/src/Test.sol";
import {APWine2SpectraConverter} from "src/integrations/spectra/APWine2SpectraConverter.sol";
import {ISdSpectraDepositor} from "src/interfaces/ISdSpectraDepositor.sol";
import {BaseSpectraTokenTest} from "test/fork/spectra/common/BaseSpectraTokenTest.sol";

contract SpectraTest is BaseSpectraTokenTest {
    APWine2SpectraConverter public converter;
    ISdSpectraDepositor internal spectraDepositor;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal initializer = makeAddr("initializer");

    uint256 internal sdAPWineSupply = 1459843245173853310837177;
    uint256 internal totalSdSpectraToDistribute = sdAPWineSupply * 20;

    uint256 internal ratio = 20 ether;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("base"), 28026639);
        _deploySpectraIntegration();

        spectraDepositor = ISdSpectraDepositor(address(depositor));

        deal(address(spectraToken), address(initializer), 1 ether);

        _initializeLocker();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 592;

        // Deposit existing NFT
        vm.startPrank(GOVERNANCE);
        veSpectra.setApprovalForAll(locker, true);
        ISdSpectraDepositor(address(depositor)).deposit(tokenIds, false, GOVERNANCE);
        vm.stopPrank();

        // Base, destination chain id is not necessary.
        // sdAPWine supply : 1459843245173853310837177
        // We use the balance of the governance after a deposit to have the amount of sdSEPCTRA to distribute
        converter = new APWine2SpectraConverter(sdToken, address(liquidityGauge), address(this), 8453, 20 ether);

        vm.prank(GOVERNANCE);
        IERC20(sdToken).transfer(address(converter), totalSdSpectraToDistribute);
    }

    /////////////////////////
    //  UTILITY FUNCTIONS
    ////////////////////////

    function _initializeLocker() public {
        vm.startPrank(initializer);
        spectraToken.approve(address(spectraDepositor), 1 ether);
        spectraDepositor.createLock(1 ether);
        vm.stopPrank();
    }

    /////////////////////////
    //  TEST FUNCTIONS
    ////////////////////////

    function test_initialState() public view {
        assertEq(IERC20(sdToken).balanceOf(address(converter)), totalSdSpectraToDistribute);
        assertEq(converter.conversionRatio(), ratio);
    }

    function test_resolveConvert() public {
        // Simulate data set by La poste to call convert contract
        bytes memory payload = abi.encode(APWine2SpectraConverter.Payload({amount: 11 ether, receiver: bob}));

        // 1 for chain Id, sender should be converter address in mainnet
        converter.receiveMessage(1, address(converter), payload);

        // receiver is bob, bob should have 11 * convertion ratio sdSPECTRA gauge
        assertEq(IERC20(sdToken).balanceOf(bob), 0);
        assertEq(liquidityGauge.balanceOf(bob), 11 ether * ratio / 10 ** 18);
    }

    function test_resolveConvertAllSupply() public {
        // Simulate data set by La poste to call convert contract
        bytes memory payload = abi.encode(APWine2SpectraConverter.Payload({amount: sdAPWineSupply, receiver: alice}));

        // 1 for chain Id, sender should be converter address in mainnet
        converter.receiveMessage(1, address(converter), payload);

        // receiver is alice, bob should have all the tokens to redeem
        assertEq(IERC20(sdToken).balanceOf(alice), 0);
        assertEq(liquidityGauge.balanceOf(alice), totalSdSpectraToDistribute);
    }

    function test_cantResolveConvertIfWrongOrigin() public {
        // Simulate data set by La poste to call convert contract
        bytes memory payload = abi.encode(APWine2SpectraConverter.Payload({amount: sdAPWineSupply, receiver: alice}));

        // sender should revert if not the converter address in mainnet
        vm.expectRevert(APWine2SpectraConverter.InvalidSender.selector);
        converter.receiveMessage(1, alice, payload);

        // msg.sender should revert if not the la poste address
        vm.startPrank(alice);
        vm.expectRevert(APWine2SpectraConverter.NotLaPoste.selector);
        converter.receiveMessage(1, address(this), payload);
        vm.stopPrank();
    }
}
